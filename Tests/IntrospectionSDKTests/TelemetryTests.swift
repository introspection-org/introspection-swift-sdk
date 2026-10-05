#if Telemetry
import Foundation
import OpenTelemetryApi
import OpenTelemetryProtocolExporterCommon
import OpenTelemetrySdk
import SwiftProtobuf
import Synchronization
import Testing

@testable import IntrospectionSDK
@testable import IntrospectionTelemetry

#if canImport(Compression)
import Compression
#endif

private typealias LogsRequest = Opentelemetry_Proto_Collector_Logs_V1_ExportLogsServiceRequest
private typealias TraceRequest = Opentelemetry_Proto_Collector_Trace_V1_ExportTraceServiceRequest
private typealias ProtoValue = Opentelemetry_Proto_Common_V1_AnyValue.OneOf_Value

private func values(_ attributes: [Opentelemetry_Proto_Common_V1_KeyValue]) -> [String: ProtoValue] {
    Dictionary(attributes.compactMap { kv in kv.value.value.map { (kv.key, $0) } }, uniquingKeysWith: { _, last in last })
}

private func options(_ transport: MockTransport, env: [String: String] = [:], logBatch: TelemetryBatchOptions = .init()) -> TelemetryOptions
{
    TelemetryOptions(logBatch: logBatch, spanBatch: .init(scheduleDelay: .seconds(3600)), transport: transport, environment: env)
}

/// The protobuf body as sent, gunzipped when the exporter compressed it.
private func body(_ recorded: MockTransport.Recorded) throws -> Data {
    let data = Data(recorded.request.body ?? Data())
    guard recorded.request.headers["Content-Encoding"] == "gzip" else { return data }
    #if canImport(Compression)
    // RFC 1952: a 10-byte header, the deflate stream, then CRC-32 and the uncompressed size (little endian).
    try #require(data.count > 18 && data[0] == 0x1f && data[1] == 0x8b)
    let size = data.suffix(4).enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
    let deflated = Data(data[10..<(data.count - 8)])
    var inflated = Data(count: size)
    let written = inflated.withUnsafeMutableBytes { destination in
        deflated.withUnsafeBytes { source in
            compression_decode_buffer(
                destination.bindMemory(to: UInt8.self).baseAddress!, size, source.bindMemory(to: UInt8.self).baseAddress!,
                deflated.count, nil, COMPRESSION_ZLIB)
        }
    }
    try #require(written == size)
    return inflated
    #else
    Issue.record("gzip body on a platform without Compression")
    return data
    #endif
}

private func logRequests(_ transport: MockTransport) throws -> [LogsRequest] {
    try transport.requests.filter { $0.path == "/v1/logs" }.map { try LogsRequest(serializedBytes: try body($0)) }
}

private func traceRequests(_ transport: MockTransport) throws -> [TraceRequest] {
    try transport.requests.filter { $0.path == "/v1/traces" }.map { try TraceRequest(serializedBytes: try body($0)) }
}

private func logRecords(_ transport: MockTransport) throws -> [Opentelemetry_Proto_Logs_V1_LogRecord] {
    try logRequests(transport).flatMap { $0.resourceLogs.flatMap { $0.scopeLogs.flatMap(\.logRecords) } }
}

private func spans(_ transport: MockTransport) throws -> [Opentelemetry_Proto_Trace_V1_Span] {
    try traceRequests(transport).flatMap { $0.resourceSpans.flatMap { $0.scopeSpans.flatMap(\.spans) } }
}

@Suite struct TelemetryLogsTests {
    private func makeLogs(
        _ transport: MockTransport, logBatch: TelemetryBatchOptions = .init(scheduleDelay: .seconds(3600))
    ) throws
        -> IntrospectionLogs
    {
        try IntrospectionLogs(
            token: "tok", baseURL: URL(string: "https://otel.test/v1/logs")!, serviceName: "ark-ios",
            options: options(transport, logBatch: logBatch))
    }

    @Test func aCustomEventIsAnOTLPLogRecordWithTheSharedShape() async throws {
        let transport = MockTransport(json: "{}")
        let logs = try makeLogs(transport)
        try IntrospectionTelemetry.withAnonymousId("device-1") {
            try IntrospectionTelemetry.withConversation("conv_1", previousResponseId: "resp_0") { id in
                #expect(id == "conv_1")
                try IntrospectionTelemetry.withAgent("ark", id: "agent_1") {
                    try logs.logEvent(
                        "ark.feed.entry",
                        attributes: [
                            "entry_id": "e_1", "count": 3, "score": 0.5, "ok": true, "tags": ["a", "b"], "meta": ["url": "https://x/y"],
                            "skipped": nil,
                        ],
                        eventId: "feed-entry:e_1", timestamp: Date(timeIntervalSince1970: 1_700_000_000.5),
                        identity: EventIdentity(userId: "u1"), severity: .warn)
                }
            }
        }
        await logs.flush()

        let request = try #require(transport.requests.last)
        #expect(request.request.url.absoluteString == "https://otel.test/v1/logs")
        #expect(request.request.headers["Authorization"] == "Bearer tok")
        #expect(request.request.headers["Content-Type"] == "application/x-protobuf")
        #expect(request.request.headers["Content-Encoding"] == nil)
        let body = try #require(try logRequests(transport).first)
        let resource = values(try #require(body.resourceLogs.first).resource.attributes)
        #expect(resource["service.name"] == .stringValue("ark-ios"))
        #expect(resource["telemetry.sdk.language"] == .stringValue("swift"))
        let scope = try #require(body.resourceLogs.first?.scopeLogs.first).scope
        #expect(scope.name == "introspection-sdk")
        #expect(scope.version == IntrospectionSDK.version)

        let record = try #require(try logRecords(transport).first)
        #expect(record.eventName == "ark.feed.entry")
        #expect(record.severityNumber == .warn)
        #expect(record.severityText == "WARN")
        #expect(record.timeUnixNano == 1_700_000_000_500_000_000)
        #expect(record.observedTimeUnixNano > 0)
        #expect(
            values(record.attributes) == [
                "event.name": .stringValue("ark.feed.entry"),
                "event.id": .stringValue("feed-entry:e_1"),
                "identity.user.id": .stringValue("u1"),
                "identity.anonymous.id": .stringValue("device-1"),
                "gen_ai.conversation.id": .stringValue("conv_1"),
                "gen_ai.request.previous_response_id": .stringValue("resp_0"),
                "gen_ai.agent.name": .stringValue("ark"),
                "gen_ai.agent.id": .stringValue("agent_1"),
                "properties.entry_id": .stringValue("e_1"),
                "properties.count": .intValue(3),
                "properties.score": .doubleValue(0.5),
                "properties.ok": .boolValue(true),
                "properties.tags": .stringValue(#"["a","b"]"#),
                "properties.meta": .stringValue(#"{"url":"https://x/y"}"#),
            ])
    }

    @Test func trackIsLogEventAtInfoWithAGeneratedId() async throws {
        let transport = MockTransport(json: "{}")
        let logs = try makeLogs(transport)
        try logs.track("Button Clicked", properties: ["button_id": "submit"])
        await logs.flush()
        let record = try #require(try logRecords(transport).first)
        let attributes = values(record.attributes)
        #expect(record.severityText == "INFO")
        #expect(record.severityNumber == .info)
        #expect(attributes["properties.button_id"] == .stringValue("submit"))
        guard case let .stringValue(id) = attributes["event.id"] else {
            Issue.record("no event.id")
            return
        }
        #expect(id.hasPrefix("intro_event_"))
        #expect(attributes["identity.user.id"] == nil)
    }

    @Test(arguments: ["", "introspection.track", "gen_ai.chat"])
    func reservedAndEmptyNamesThrowAndSendNothing(_ name: String) async throws {
        let transport = MockTransport(json: "{}")
        let logs = try makeLogs(transport)
        let error = #expect(throws: IntrospectionError.self) { try logs.logEvent(name) }
        #expect(error?.kind == .invalidRequest)
        #expect(throws: IntrospectionError.self) { try logs.track(name) }
        #expect(IntrospectionLogs.reservedPrefix(of: "introspectionist.x") == nil)
        await logs.flush()
        #expect(transport.requests.isEmpty)
    }

    @Test func feedbackAndIdentifyMatchTheOtherSDKs() async throws {
        let transport = MockTransport(json: "{}")
        let logs = try makeLogs(transport)
        logs.feedback(
            "thumbs_up", comments: "", conversationId: "conv_9", previousResponseId: "resp_9", eventId: "fb_1",
            properties: ["name": "ignored", "value": 1])
        logs.identify("u7", traits: ["plan": "pro"], anonymousId: "anon7")
        await logs.flush()
        let records = try logRecords(transport)
        #expect(records.map(\.eventName) == ["introspection.feedback", "identify"])
        let feedback = values(records[0].attributes)
        #expect(feedback["properties.name"] == .stringValue("thumbs_up"))
        #expect(feedback["properties.comments"] == .stringValue(""))
        #expect(feedback["properties.value"] == .intValue(1))
        #expect(feedback["gen_ai.conversation.id"] == .stringValue("conv_9"))
        #expect(feedback["gen_ai.request.previous_response_id"] == .stringValue("resp_9"))
        #expect(feedback["event.id"] == .stringValue("fb_1"))
        let identify = values(records[1].attributes)
        #expect(identify["identity.user.id"] == .stringValue("u7"))
        #expect(identify["identity.anonymous.id"] == .stringValue("anon7"))
        #expect(identify["context.traits.plan"] == .stringValue("pro"))
    }

    @Test func recordsAreBatchedAndFlushSendsTheRest() async throws {
        let transport = MockTransport(json: "{}")
        let logs = try makeLogs(transport, logBatch: .init(scheduleDelay: .seconds(3600), maxExportBatchSize: 2))
        for index in 0..<5 { try logs.logEvent("app.tick", attributes: ["i": .number(Double(index))]) }
        await logs.flush()
        let requests = try logRequests(transport)
        let counts = requests.map { $0.resourceLogs.flatMap(\.scopeLogs).flatMap(\.logRecords).count }
        #expect(counts.reduce(0, +) == 5)
        #expect(counts.allSatisfy { $0 <= 2 })
    }

    @Test func aFailedExportIsDroppedNotThrown() async throws {
        let transport = MockTransport { _, index in
            index == 0 ? .response(.json(#"{"detail":"boom"}"#, status: 500)) : .response(.json("{}"))
        }
        let logs = try makeLogs(transport)
        try logs.logEvent("app.first")
        await logs.flush()
        try logs.logEvent("app.second")
        await logs.flush()
        #expect(transport.requests.count == 2)
        let second = try LogsRequest(serializedBytes: try body(transport.requests[1]))
        #expect(second.resourceLogs.flatMap(\.scopeLogs).flatMap(\.logRecords).map(\.eventName) == ["app.second"])
        await logs.shutdown()
    }

    @Test func gzipIsOptInAndDecodesToTheSameRecord() async throws {
        let transport = MockTransport(json: "{}")
        let logs = try IntrospectionLogs(
            token: "tok", options: options(transport, env: ["OTEL_EXPORTER_OTLP_COMPRESSION": "GZIP"]))
        try logs.logEvent("app.opened", eventId: "e1")
        await logs.flush()
        let request = try #require(transport.last)
        #if canImport(Compression)
        #expect(request.request.headers["Content-Encoding"] == "gzip")
        #else
        #expect(request.request.headers["Content-Encoding"] == nil)
        #endif
        let record = try #require(try logRecords(transport).first)
        #expect(record.eventName == "app.opened")
        #expect(values(record.attributes)["event.id"] == .stringValue("e1"))
    }

    @Test func aTokenClosureIsReadPerRequestAndA401Refreshes() async throws {
        let refreshing = RotatingCredentials()
        let transport = MockTransport { request, _ in
            request.headers["Authorization"] == "Bearer fresh" ? .response(.json("{}")) : .response(.json("{}", status: 401))
        }
        let logs = try IntrospectionLogs(credentials: refreshing, options: options(transport))
        try logs.logEvent("app.opened")
        await logs.flush()
        #expect(transport.requests.map { $0.request.headers["Authorization"] } == ["Bearer stale", "Bearer fresh"])
        #expect(transport.requests[0].request.url.absoluteString == "https://otel.introspection.dev/v1/logs")

        let dynamic = MockTransport(json: "{}")
        let closure = try IntrospectionLogs(token: { "from-session" }, options: options(dynamic))
        try closure.logEvent("app.opened")
        await closure.flush()
        #expect(dynamic.last?.request.headers["Authorization"] == "Bearer from-session")
    }
}

private final class RotatingCredentials: CredentialProvider {
    private let token = Mutex("stale")

    func authorization() async throws -> String? { "Bearer \(token.withLock { $0 })" }

    func refreshAfterUnauthorized(rejected _: String?) async throws -> Bool {
        token.withLock { $0 = "fresh" }
        return true
    }
}

@Suite struct TelemetryTracesTests {
    private func makeTelemetry(_ transport: MockTransport) throws -> IntrospectionTelemetry {
        try IntrospectionTelemetry(
            token: "tok", baseURL: URL(string: "https://otel.test/")!, serviceName: "ark-ios", options: options(transport))
    }

    @Test func genAISpansCarryTheScopedContextAndOthersAreDropped() async throws {
        let transport = MockTransport(json: "{}")
        let telemetry = try makeTelemetry(transport)
        try await IntrospectionTelemetry.withUserId("u1") {
            try await IntrospectionTelemetry.withConversation("conv_1") { _ in
                try await IntrospectionTelemetry.withAgent("ark", id: "agent_1") {
                    try await telemetry.withGenAISpan(model: "gpt-5", provider: "openai") { span in
                        span.setGenAIInputMessages([.system("Be brief."), .user("Hi")])
                        span.setGenAIOutputMessages([.assistant("Hello", finishReason: "stop")])
                        span.setGenAIUsage(inputTokens: 12, outputTokens: 3)
                        span.setGenAIResponse(model: "gpt-5-2026", id: "resp_1", finishReasons: ["stop"])
                        span.setAttribute(key: GenAIAttributes.conversationId, value: "overridden")
                        span.setAttribute(key: "gen_ai.system", value: "openai")
                        telemetry.tracer.spanBuilder(spanName: "db.query").startSpan().end()
                    }
                    try telemetry.logEvent("app.answered")
                }
            }
        }
        await telemetry.flush()

        let request = try #require(transport.requests.first { $0.path == "/v1/traces" })
        #expect(request.request.url.absoluteString == "https://otel.test/v1/traces")
        #expect(request.request.headers["Authorization"] == "Bearer tok")
        let resource = values(try #require(try traceRequests(transport).first?.resourceSpans.first).resource.attributes)
        #expect(resource["service.name"] == .stringValue("ark-ios"))
        let exported = try spans(transport)
        #expect(exported.map(\.name) == ["chat gpt-5"])
        let span = try #require(exported.first)
        #expect(span.kind == .client)
        let attributes = values(span.attributes)
        #expect(attributes["gen_ai.operation.name"] == .stringValue("chat"))
        #expect(attributes["gen_ai.request.model"] == .stringValue("gpt-5"))
        #expect(attributes["gen_ai.provider.name"] == .stringValue("openai"))
        #expect(attributes["gen_ai.conversation.id"] == .stringValue("conv_1"))
        #expect(attributes["gen_ai.agent.name"] == .stringValue("ark"))
        #expect(attributes["gen_ai.agent.id"] == .stringValue("agent_1"))
        #expect(attributes["identity.user.id"] == .stringValue("u1"))
        #expect(attributes["gen_ai.system"] == nil)
        #expect(attributes["gen_ai.usage.input_tokens"] == .intValue(12))
        #expect(attributes["gen_ai.response.id"] == .stringValue("resp_1"))
        #expect(
            attributes["gen_ai.input.messages"]
                == .stringValue(
                    #"[{"parts":[{"content":"Be brief.","type":"text"}],"role":"system"},{"parts":[{"content":"Hi","type":"text"}],"role":"user"}]"#
                ))
        #expect(
            attributes["gen_ai.output.messages"]
                == .stringValue(#"[{"finish_reason":"stop","parts":[{"content":"Hello","type":"text"}],"role":"assistant"}]"#))

        let record = try #require(try logRecords(transport).first)
        let logAttributes = values(record.attributes)
        #expect(logAttributes["gen_ai.conversation.id"] == .stringValue("conv_1"))
        #expect(logAttributes["identity.user.id"] == .stringValue("u1"))
        #expect(logAttributes["gen_ai.agent.name"] == .stringValue("ark"))
        await telemetry.shutdown()
    }

    @Test func spansOfOneTraceShareAConversationAndNestUnderTheActiveSpan() async throws {
        let transport = MockTransport(json: "{}")
        let telemetry = try makeTelemetry(transport)
        try await telemetry.withGenAISpan(GenAIOperationNames.invokeAgent) { _ in
            try await telemetry.withGenAISpan(model: "m") { _ in
                let manual = telemetry.tracer.spanBuilder(spanName: "llm").startSpan()
                manual.setGenAIInputMessages([.user("x")])
                manual.end()
            }
        }
        struct Failure: Error {}
        await #expect(throws: Failure.self) { try await telemetry.withGenAISpan(model: "m") { _ in throw Failure() } }
        await telemetry.flush()

        let exported = try spans(transport)
        let byName = Dictionary(exported.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let outer = try #require(byName["invoke_agent"])
        let inner = try #require(byName["chat m"])
        let manual = try #require(byName["llm"])
        #expect(inner.parentSpanID == outer.spanID)
        #expect(manual.parentSpanID == inner.spanID)
        #expect(manual.traceID == outer.traceID)
        #expect(values(manual.attributes)["gen_ai.operation.name"] == .stringValue("chat"))
        let conversations = [outer, inner, manual].map { span -> String? in
            if case let .stringValue(id)? = values(span.attributes)["gen_ai.conversation.id"] { return id }
            return nil
        }
        #expect(Set(conversations).count == 1)
        let conversation = try #require(conversations.first ?? nil)
        #expect(conversation.hasPrefix("intro_conv_") && conversation.count == "intro_conv_".count + 32)
        let failed = try #require(exported.first { $0.status.code == .error })
        #expect(failed.traceID != outer.traceID)
    }

    @Test func aStandaloneProcessorFitsAnExistingProvider() async throws {
        let transport = MockTransport(json: "{}")
        let processor = try IntrospectionSpanProcessor(token: "tok", options: options(transport))
        let provider = TracerProviderBuilder().add(spanProcessor: processor).build()
        let span = provider.get(instrumentationName: "app").spanBuilder(spanName: "chat").startSpan()
        span.setAttribute(key: GenAIAttributes.requestModel, value: "m")
        span.end()
        provider.forceFlush()
        #expect(try spans(transport).map(\.name) == ["chat"])
        #expect(transport.last?.request.url.absoluteString == "https://otel.introspection.dev/v1/traces")
    }
}

@Suite(.serialized) struct TelemetryBootstrapTests {
    @Test func bootstrapInstallsOnceAndShutdownUninstalls() async throws {
        let transport = MockTransport(json: "{}")
        let first = try IntrospectionTelemetry.bootstrap(token: "tok", options: options(transport))
        let second = try IntrospectionTelemetry.bootstrap(credentials: BearerToken("other"), options: options(transport))
        #expect(first === second)
        #expect(IntrospectionTelemetry.current === first)
        #expect(OpenTelemetry.instance.tracerProvider as AnyObject === first.tracerProvider)
        try IntrospectionTelemetry.current?.track("app.opened")
        await first.shutdown()
        #expect(IntrospectionTelemetry.current == nil)
        #expect(transport.last?.request.headers["Authorization"] == "Bearer tok")
    }
}

@Suite struct TelemetryEnvironmentTests {
    @Test func explicitBeatsEnvironmentBeatsDefault() throws {
        let env = [
            "INTROSPECTION_BASE_OTEL_URL": "https://otel.env.test/v1/traces/", "INTROSPECTION_SERVICE_NAME": "env-service",
            "OTEL_BLRP_SCHEDULE_DELAY": "250", "OTEL_BLRP_MAX_EXPORT_BATCH_SIZE": "7", "OTEL_BSP_MAX_QUEUE_SIZE": "99",
            "OTEL_BSP_EXPORT_TIMEOUT": "nonsense", "OTEL_EXPORTER_OTLP_HEADERS": "x-team=ark, x-note=a%20b,broken, x-tenant=env",
        ]
        let fromEnv = try ResolvedTelemetry(baseURL: nil, serviceName: nil, options: TelemetryOptions(environment: env))
        #expect(fromEnv.baseURL.absoluteString == "https://otel.env.test")
        #expect(fromEnv.serviceName == "env-service")
        #expect(fromEnv.logBatch.scheduleDelay == .milliseconds(250))
        #expect(fromEnv.logBatch.maxExportBatchSize == 7)
        #expect(fromEnv.logBatch.maxQueueSize == 2048)
        #expect(fromEnv.spanBatch.maxQueueSize == 99)
        #expect(fromEnv.spanBatch.exportTimeout == .seconds(30))
        #expect(fromEnv.spanBatch.maxExportBatchSize == 512)
        #expect(fromEnv.headers == ["x-team": "ark", "x-note": "a b", "x-tenant": "env"])
        #expect(fromEnv.compression == .none)
        let gzip = try ResolvedTelemetry(
            baseURL: nil, serviceName: nil, options: TelemetryOptions(environment: ["OTEL_EXPORTER_OTLP_COMPRESSION": "gzip"]))
        #expect(gzip.compression == .gzip)
        let explicitNone = try ResolvedTelemetry(
            baseURL: nil, serviceName: nil,
            options: TelemetryOptions(compression: TelemetryCompression.none, environment: ["OTEL_EXPORTER_OTLP_COMPRESSION": "gzip"]))
        #expect(explicitNone.compression == .none)

        let explicit = try ResolvedTelemetry(
            baseURL: URL(string: "https://otel.arg.test")!, serviceName: "arg-service",
            options: TelemetryOptions(
                logBatch: .init(scheduleDelay: .seconds(1), maxExportBatchSize: 3), additionalHeaders: ["x-tenant": "arg"], environment: env
            ))
        #expect(explicit.headers["x-tenant"] == "arg")
        #expect(explicit.baseURL.absoluteString == "https://otel.arg.test")
        #expect(explicit.serviceName == "arg-service")
        #expect(explicit.logBatch.scheduleDelay == .seconds(1))
        #expect(explicit.logBatch.maxExportBatchSize == 3)

        let defaults = try ResolvedTelemetry(baseURL: nil, serviceName: nil, options: TelemetryOptions(environment: [:]))
        #expect(defaults.baseURL == TelemetryEnvironment.defaultBaseOTelURL)
        #expect(defaults.serviceName == "introspection-client")
        #expect(
            defaults.logBatch == .init(scheduleDelay: .seconds(5), exportTimeout: .seconds(30), maxQueueSize: 2048, maxExportBatchSize: 100)
        )
        #expect(
            defaults.spanBatch
                == .init(scheduleDelay: .seconds(5), exportTimeout: .seconds(30), maxQueueSize: 2048, maxExportBatchSize: 512))
    }

    @Test func theTokenComesFromTheArgumentThenTheEnvironment() async throws {
        #expect(throws: IntrospectionError.self) { try IntrospectionTelemetry.fromEnvironment(options: TelemetryOptions(environment: [:])) }
        #expect(throws: IntrospectionError.self) {
            try IntrospectionLogs.fromEnvironment(options: TelemetryOptions(environment: ["INTROSPECTION_TOKEN": ""]))
        }
        #expect(throws: IntrospectionError.self) {
            try IntrospectionSpanProcessor.fromEnvironment(options: TelemetryOptions(environment: ["INTROSPECTION_BASE_OTEL_URL": ""]))
        }
        #expect(try ResolvedTelemetry.token("arg", environment: ["INTROSPECTION_TOKEN": "env"]) == "arg")
        #expect(try ResolvedTelemetry.token(nil, environment: ["INTROSPECTION_TOKEN": "env"]) == "env")

        let transport = MockTransport(json: "{}")
        let telemetry = try IntrospectionTelemetry.fromEnvironment(
            options: TelemetryOptions(
                transport: transport,
                environment: [
                    "INTROSPECTION_TOKEN": "env-token", "INTROSPECTION_BASE_OTEL_URL": "https://otel.env.test",
                    "OTEL_EXPORTER_OTLP_HEADERS": "Authorization=Bearer spoof,x-team=ark",
                ]))
        try telemetry.track("app.opened")
        await telemetry.flush()
        #expect(transport.last?.request.url.absoluteString == "https://otel.env.test/v1/logs")
        #expect(transport.last?.request.headers["Authorization"] == "Bearer env-token")
        #expect(transport.last?.request.headers["x-team"] == "ark")
        #expect(telemetry.logs.serviceName == "introspection-client")
    }

    @Test func messagesEncodeLikeTheOtherSDKs() {
        let message = GenAIMessage(
            role: "assistant",
            parts: [
                .toolCall(id: "c1", name: "search", arguments: #"{"q":"x"}"#), .toolCallResponse(id: "c1", response: nil),
                .thinking(content: "hm", signature: nil),
            ])
        #expect(
            jsonString([message])
                == #"[{"parts":[{"arguments":"{\"q\":\"x\"}","id":"c1","name":"search","type":"tool_call"},{"id":"c1","type":"tool_call_response"},{"content":"hm","type":"thinking"}],"role":"assistant"}]"#
        )
        #expect(AttributeValue(json: .number(.infinity)) == .string("inf"))
        #expect(AttributeValue(json: .number(1e20)) == .double(1e20))
        #expect(TelemetryContext.current == TelemetryContext())
    }
}
#endif
