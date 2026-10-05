import Foundation
import Testing

@testable import IntrospectionSDK

@Suite struct EventLoggerTests {
    private static let fixedNow = Date(timeIntervalSince1970: 1_700_000_100.5)

    private func makeLogger(
        _ transport: MockTransport, otelURL: String = "https://otel.test/",
        configuration: EventLogger.Configuration = .init(flushInterval: .seconds(3600))
    ) -> EventLogger {
        EventLogger(
            otelURL: URL(string: otelURL)!, http: makeClient(transport).dataPlane, configuration: configuration, now: { Self.fixedNow })
    }

    private func records(_ request: MockTransport.Recorded) -> [JSONValue] {
        request.json?["resourceLogs"]?[0]?["scopeLogs"]?[0]?["logRecords"]?.arrayValue ?? []
    }

    private func attribute(_ record: JSONValue, _ key: String) -> JSONValue? {
        record["attributes"]?.arrayValue?.first { $0["key"]?.stringValue == key }?["value"]
    }

    private func waitForRequests(_ transport: MockTransport, _ count: Int) async throws {
        for _ in 0..<500 where transport.requests.count < count {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func oneEventIsEncodedAsOTLPJSON() async throws {
        let transport = MockTransport(json: "{}")
        let logger = makeLogger(transport, configuration: .init(serviceName: "ark-ios", flushInterval: .seconds(3600)))
        try logger.logEvent(
            "ark.feed.entry",
            attributes: [
                "entry_id": "e_1", "count": 3, "score": 0.5, "ok": true, "tags": ["a", "b"], "meta": ["url": "https://x/y"],
                "skipped": nil,
            ],
            eventId: "feed-entry:e_1",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000.123),
            identity: EventIdentity(userId: "u1", anonymousId: "anon1"),
            severity: .warn
        )
        #expect(transport.requests.isEmpty)
        await logger.flush()

        let request = try #require(transport.last).request
        #expect(request.method == "POST")
        #expect(request.url.absoluteString == "https://otel.test/v1/logs")
        #expect(request.headers["Content-Type"] == "application/json")
        #expect(request.headers["Authorization"] == "Bearer dp-token")
        let v = IntrospectionSDK.version
        let expected =
            #"{"resourceLogs":[{"resource":{"attributes":["#
            + #"{"key":"service.name","value":{"stringValue":"ark-ios"}},"#
            + #"{"key":"telemetry.sdk.language","value":{"stringValue":"swift"}},"#
            + #"{"key":"telemetry.sdk.name","value":{"stringValue":"introspection-sdk"}},"#
            + #"{"key":"telemetry.sdk.version","value":{"stringValue":"\#(v)"}}]},"#
            + #""scopeLogs":[{"logRecords":[{"attributes":["#
            + #"{"key":"event.name","value":{"stringValue":"ark.feed.entry"}},"#
            + #"{"key":"event.id","value":{"stringValue":"feed-entry:e_1"}},"#
            + #"{"key":"identity.user.id","value":{"stringValue":"u1"}},"#
            + #"{"key":"identity.anonymous.id","value":{"stringValue":"anon1"}},"#
            + #"{"key":"properties.count","value":{"intValue":"3"}},"#
            + #"{"key":"properties.entry_id","value":{"stringValue":"e_1"}},"#
            + #"{"key":"properties.meta","value":{"stringValue":"{\"url\":\"https://x/y\"}"}},"#
            + #"{"key":"properties.ok","value":{"boolValue":true}},"#
            + #"{"key":"properties.score","value":{"doubleValue":0.5}},"#
            + #"{"key":"properties.tags","value":{"stringValue":"[\"a\",\"b\"]"}}],"#
            + #""eventName":"ark.feed.entry","observedTimeUnixNano":"1700000100500000000","severityNumber":13,"#
            + #""severityText":"WARN","timeUnixNano":"1700000000123000000"}],"#
            + #""scope":{"name":"introspection-sdk","version":"\#(v)"}}]}]}"#
        #expect(transport.last?.bodyString == expected)
    }

    @Test func defaultsFillTheIdAndTimestampsAndIdentityMergesFieldByField() async throws {
        let transport = MockTransport(json: "{}")
        let logger = makeLogger(
            transport,
            configuration: .init(flushInterval: .seconds(3600), identity: EventIdentity(userId: "default-user", anonymousId: "device-1")))
        try logger.logEvent("app.opened", identity: EventIdentity(userId: "u2"))
        try logger.logEvent("app.closed", eventId: "")
        await logger.flush()

        let sent = records(try #require(transport.last))
        #expect(sent.count == 2)
        #expect(sent[0]["timeUnixNano"] == "1700000100500000000")
        #expect(sent[0]["severityText"] == "INFO")
        #expect(sent[0]["severityNumber"] == 9)
        #expect(attribute(sent[0], "identity.user.id") == ["stringValue": "u2"])
        #expect(attribute(sent[0], "identity.anonymous.id") == ["stringValue": "device-1"])
        #expect(attribute(sent[1], "identity.user.id") == ["stringValue": "default-user"])
        let millis = String(UInt64(Self.fixedNow.timeIntervalSince1970 * 1000), radix: 16)
        for record in sent {
            let id = try #require(attribute(record, "event.id")?["stringValue"]?.stringValue)
            #expect(id.hasPrefix("intro_event_\(millis)-"))
            #expect(id.count == "intro_event_\(millis)-".count + 8)
        }
    }

    @Test func aFullBatchIsSentWithoutWaitingAndFlushSendsTheRest() async throws {
        let transport = MockTransport(json: "{}")
        let logger = makeLogger(transport, configuration: .init(maxBatchSize: 2, flushInterval: .seconds(3600)))
        for index in 0..<3 { try logger.track("app.tick", properties: ["i": .number(Double(index))]) }
        try await waitForRequests(transport, 1)
        #expect(records(try #require(transport.requests.first)).count == 2)

        await logger.flush()
        #expect(transport.requests.count == 2)
        #expect(records(transport.requests[1]).count == 1)
        #expect(attribute(records(transport.requests[1])[0], "properties.i") == ["intValue": "2"])

        await logger.flush()
        #expect(transport.requests.count == 2)
    }

    @Test func theFlushIntervalSendsAPartialBatch() async throws {
        let transport = MockTransport(json: "{}")
        let logger = makeLogger(transport, configuration: .init(flushInterval: .milliseconds(20)))
        try logger.logEvent("app.opened")
        try await waitForRequests(transport, 1)
        #expect(transport.requests.count == 1)
        #expect(records(transport.requests[0]).count == 1)
    }

    @Test func eventsBeyondTheQueueAreDropped() async throws {
        let transport = MockTransport(json: "{}")
        let logger = makeLogger(transport, configuration: .init(maxBatchSize: 10, maxQueueSize: 1, flushInterval: .seconds(3600)))
        try logger.logEvent("app.first")
        try logger.logEvent("app.second")
        await logger.flush()
        let sent = records(try #require(transport.last))
        #expect(sent.map { $0["eventName"] } == ["app.first"])
    }

    @Test(arguments: ["", "introspection.track", "introspection.feedback", "gen_ai.chat"])
    func reservedAndEmptyNamesAreRejected(_ name: String) async throws {
        let transport = MockTransport(json: "{}")
        let logger = makeLogger(transport)
        let error = #expect(throws: IntrospectionError.self) { try logger.logEvent(name) }
        #expect(error?.kind == .invalidRequest)
        #expect(throws: IntrospectionError.self) { try logger.track(name) }
        await logger.flush()
        #expect(transport.requests.isEmpty)
    }

    @Test func namesThatOnlyResembleAReservedPrefixAreAccepted() async throws {
        let transport = MockTransport(json: "{}")
        let logger = makeLogger(transport)
        try logger.logEvent("introspectionist.signup")
        try logger.logEvent("gen_ai_app.x")
        #expect(EventLogger.reservedPrefix(of: "gen_ai.x") == "gen_ai.")
        #expect(EventLogger.reservedPrefix(of: "Introspection.x") == nil)
        await logger.flush()
        #expect(records(try #require(transport.last)).count == 2)
    }

    @Test func trackIsLogEventAtInfo() async throws {
        let transport = MockTransport(json: "{}")
        let logger = makeLogger(transport)
        try logger.track("Button Clicked", properties: ["button_id": "submit"], eventId: "click:1")
        await logger.flush()
        let last = try #require(transport.last)
        let record = try #require(records(last).first)
        #expect(record["eventName"] == "Button Clicked")
        #expect(record["severityText"] == "INFO")
        #expect(attribute(record, "event.name") == ["stringValue": "Button Clicked"])
        #expect(attribute(record, "event.id") == ["stringValue": "click:1"])
        #expect(attribute(record, "properties.button_id") == ["stringValue": "submit"])
    }

    @Test func aFailedExportIsLoggedNotThrownAndLaterEventsStillSend() async throws {
        let transport = MockTransport { _, index in
            index == 0
                ? .response(.json(#"{"detail":"boom"}"#, status: 500)) : .response(.json(#"{"partialSuccess":{"rejectedLogRecords":"1"}}"#))
        }
        let logger = makeLogger(transport)
        try logger.logEvent("app.first")
        await logger.flush()
        try logger.logEvent("app.second")
        await logger.flush()
        #expect(transport.requests.count == 2)
        #expect(records(transport.requests[1]).map { $0["eventName"] } == ["app.second"])
    }

    @Test func numbersJSONCannotHoldAreSentAsStrings() {
        #expect(OTLPAnyValue(.number(.infinity)) == .string("inf"))
        #expect(OTLPAnyValue(.number(1e20)) == .double(1e20))
        #expect(OTLPAnyValue(.number(-4)) == .int(-4))
        #expect(OTLPAnyValue(.null) == nil)
        #expect(EventLogger.unixNano(Date(timeIntervalSince1970: -1)) == "0")
    }

    @Test(arguments: ["https://otel.test", "https://otel.test/v1/logs", "https://otel.test/v1/logs/"])
    func theLogsPathIsAppendedOnce(_ url: String) async throws {
        let transport = MockTransport(json: "{}")
        let logger = makeLogger(transport, otelURL: url)
        #expect(logger.otelURL.absoluteString == "https://otel.test")
        try logger.logEvent("app.opened")
        await logger.flush()
        #expect(transport.last?.request.url.absoluteString == "https://otel.test/v1/logs")
    }

    @Test func theClientLogsWithItsDataPlaneCredentialsToItsOTelURL() async throws {
        let transport = MockTransport(json: "{}")
        #expect(makeClient(transport).eventLogger.otelURL == EventLogger.defaultOTelURL)
        let client = IntrospectionClient(
            configuration: .init(
                controlPlaneURL: URL(string: "https://cp.test")!, dataPlaneCredentials: BearerToken("dp-token"), transport: transport,
                otelURL: URL(string: "https://collector.test")!, eventLogging: .init(serviceName: "svc")))
        try client.logEvent("app.opened", attributes: ["a": 1])
        try client.track("app.tracked")
        #expect(throws: IntrospectionError.self) { try client.logEvent("introspection.x") }
        await client.eventLogger.flush()
        let request = try #require(transport.last)
        #expect(request.request.url.absoluteString == "https://collector.test/v1/logs")
        #expect(request.request.headers["Authorization"] == "Bearer dp-token")
        #expect(records(request).count == 2)
    }

    @Test func aConnectionLoggerUsesTheConnectionsCurrentCredentials() async throws {
        let transport = MockTransport(json: "{}")
        let client = makeClient(transport)
        let logger = EventLogger(otelURL: URL(string: "https://otel.test")!, connection: client)
        try logger.logEvent("runner.event")
        await logger.flush()
        #expect(transport.last?.request.url.absoluteString == "https://otel.test/v1/logs")
        #expect(transport.last?.request.headers["Authorization"] == "Bearer dp-token")
    }

    @Test func severitiesMapToOTelNumbers() {
        #expect(LogEventSeverity.allCases.map(\.number) == [5, 9, 13, 17])
        #expect(LogEventSeverity.allCases.map(\.rawValue) == ["DEBUG", "INFO", "WARN", "ERROR"])
    }
}

@Suite struct TrackEventReadTests {
    @Test func trackEventsDecodeWithAnyPropertyTypes() async throws {
        let page = #"""
            {"records":[
              {"id":"t1","timestamp":"2026-10-05T08:00:00Z","event_name":"introspection.track","service_name":"ark-ios",
               "payload":{"name":"ark.feed.entry","properties":{"entry_id":"e_1","count":3,"score":0.5,"ok":true,
                "tags":["a",1,null],"meta":{"nested":{"deep":[true]}},"gone":null}}},
              {"id":"t2","event_name":"introspection.track","payload":{"name":"app.opened"}}
            ],"count":2,"next":null}
            """#
        let transport = MockTransport(json: page)
        let events = try await makeClient(transport).events.list(EventListParams(eventName: .track, names: ["ark.feed.entry"])).collect()
        let first = try #require(events[0].track)
        #expect(first.name == "ark.feed.entry")
        #expect(first.properties?["entry_id"] == "e_1")
        #expect(first.properties?["count"]?.intValue == 3)
        #expect(first.properties?["score"] == 0.5)
        #expect(first.properties?["ok"] == true)
        #expect(first.properties?["tags"] == ["a", 1, nil])
        #expect(first.properties?["meta"]?["nested"]?["deep"] == [true])
        #expect(first.properties?["gone"] == .null)
        #expect(events[1].track == TrackPayload(name: "app.opened"))
        #expect(events[0].feedback == nil)
    }

    @Test func aTrackPayloadWithoutANameIsNotATrackPayload() throws {
        let event = try JSONCoding.decoder.decode(
            IntrospectionEvent.self, from: Data(#"{"id":"t","event_name":"introspection.track","payload":{"properties":{}}}"#.utf8))
        #expect(event.track == nil)
        #expect(event.payload?["properties"] == [:])
    }

    @Test func namesAreSentAsRepeatedNameOnEveryPage() async throws {
        let transport = MockTransport { _, index in
            let body =
                index == 0
                ? #"{"records":[{"id":"t1","event_name":"introspection.track","payload":{"name":"a.one"}}],"next":"c2"}"#
                : #"{"records":[{"id":"t2","event_name":"introspection.track","payload":{"name":"b.two"}}],"next":null}"#
            return .response(.json(body))
        }
        let events = try await makeClient(transport).events.list(
            EventListParams(eventName: .track, limit: 1, names: ["a.one", "b two/x"])
        ).collect()
        #expect(events.compactMap(\.track?.name) == ["a.one", "b.two"])
        #expect(transport.requests.count == 2)
        for request in transport.requests {
            #expect(request.query["event_name"] == ["introspection.track"])
            #expect(request.query["name"] == ["a.one", "b two/x"])
        }
        #expect(transport.requests[0].query["next"] == nil)
        #expect(transport.requests[1].query["next"] == ["c2"])
        #expect(transport.requests[0].request.url.query?.contains("name=b%20two%2Fx") == true)
    }
}
