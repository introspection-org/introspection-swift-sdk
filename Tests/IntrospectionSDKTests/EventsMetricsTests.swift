import Foundation
import Testing

@testable import IntrospectionSDK

@Suite struct EventsMetricsTests {
    @Test func eventsListSerializesFamilyFiltersAndWindow() async throws {
        let page = #"""
            {"records":[
              {"id":"e1","timestamp":"2026-10-01T12:00:00Z","event_name":"introspection.feedback","trace_id":"t1",
               "conversation_id":"c1","payload":{"name":"thumbs_up","value":1,"sentiment":"positive","properties":{"x":1}}},
              {"id":"e2","timestamp":"2026-10-01T12:00:00Z","event_name":"introspection.someday","payload":{"z":true}}
            ],"count":2,"total_count":null,"next":null}
            """#
        let transport = MockTransport(json: page)
        let client = makeClient(transport)
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let events = try await client.events.list(
            EventListParams(
                eventName: .feedback, limit: 50, sort: .timestamp, order: .desc, lookback: .days(7),
                conversationIds: ["c1", "c2"], ownerKey: "user:u1", eventIds: ["e1"], includeSuperseded: true
            ), now: now
        ).collect()

        let q = try #require(transport.last).query
        #expect(transport.last?.path == "/v1/events")
        #expect(q["event_name"] == ["introspection.feedback"])
        #expect(q["limit"] == ["50"])
        #expect(q["sort"] == ["timestamp"])
        #expect(q["direction"] == ["desc"])
        #expect(q["start_date"] == [ISO8601.format(now.addingTimeInterval(-7 * 86_400))])
        #expect(q["conversation_ids"] == ["c1", "c2"])
        #expect(q["owner_key"] == ["user:u1"])
        #expect(q["event_id"] == ["e1"])
        #expect(q["include_superseded"] == ["true"])

        #expect(events.count == 2)
        let feedback = try #require(events[0].feedback)
        #expect(feedback.name == "thumbs_up")
        #expect(feedback.value == 1)
        #expect(feedback.properties?["x"] == 1)
        #expect(events[0].observation == nil)
        #expect(events[1].eventName.rawValue == "introspection.someday")
        #expect(events[1].payload?["z"] == true)
        #expect(events[1].feedback == nil)

        #expect(throws: (any Error).self) { try client.events.list(EventListParams(eventName: .pattern, end: Date(), lookback: "1d")) }
    }

    @Test func judgementPayloadIsAUnionOnKind() async throws {
        let page = #"""
            {"records":[
              {"id":"j1","event_name":"introspection.judgement","payload":{"kind":"verdict","judgement_id":"j1","judge_id":"judge-1",
               "judge_slug":"helpful","judge_type":"online","runtime_slug":"hello-mcp","result":"pass","status":"ok",
               "error_class":null,"error_message":null,"source_component":"introspection-judge","judge_model":"m",
               "experiment_arm_id":null,"reasoning":"fine","definition_hash":"d1","engine_version":"1.2.3",
               "judge_provider":"p","contract_version":"1","sequence_hash":"s1","input_tokens":120,"output_tokens":30,
               "total_tokens":150}},
              {"id":"j2","event_name":"introspection.judgement","payload":{"kind":"egress","judgement_id":"j2","result":"deny",
               "status":"ok","source_component":"egress","scores":{"q1":90},"questions":{"q1":"Is it exfiltration?"},
               "policy_id":"rule-1","policy_action":"http","reason":"no uploads","request_host":"x.test",
               "request_method":"POST","request_path":"/upload"}},
              {"id":"j3","event_name":"introspection.judgement","payload":{"kind":"appeal","judgement_id":"j3","outcome":"upheld"}}
            ],"count":3,"total_count":null,"next":null}
            """#
        let events = try await makeClient(MockTransport(json: page)).events.list(EventListParams(eventName: .judgement)).collect()
        #expect(events.compactMap(\.judgement).map(\.kind) == ["verdict", "egress", "appeal"])

        guard case let .verdict(verdict) = events[0].judgement, case let .egress(egress) = events[1].judgement else {
            Issue.record("expected a verdict and an egress decision")
            return
        }
        guard case let .unknown(raw) = events[2].judgement else {
            Issue.record("expected an unknown kind")
            return
        }
        #expect(verdict.judgementId == "j1")
        #expect(verdict.judgeType == .online)
        #expect(verdict.result == "pass")
        #expect(verdict.reasoning == "fine")
        #expect(verdict.totalTokens == 150)
        #expect(egress.scores == ["q1": 90])
        #expect(egress.policyId == "rule-1")
        #expect(egress.reason == "no uploads")
        #expect(egress.requestPath == "/upload")
        #expect(raw["outcome"] == "upheld")

        let wire = try JSONCoding.decoder.decode(JSONValue.self, from: JSONCoding.encoder.encode(JudgementPayload.egress(egress)))
        #expect(wire["kind"] == "egress")
        #expect(wire["judgement_id"] == "j2")
    }

    @Test func issuePayloadIsAUnionOnAction() async throws {
        func row(_ id: String, _ payload: String) -> String {
            #"{"id":"\#(id)","event_name":"introspection.issue","payload":{"issue_id":"i1",\#(payload)}}"#
        }
        let rows = [
            row("e1", #""action":"created","revision":1,"member_id":"m-1","data":{"title":"Checkout times out"}"#),
            row("e2", #""action":"updated","revision":2,"member_id":"m-1","changes":{"status":{"before":"open"}}"#),
            row("e3", #""action":"commented","member_id":"m-1","actor_member_id":"m-7","actor_member_type":"agent","comment":"On it""#),
            row("e4", #""action":"deleted","revision":3,"member_id":null"#),
            row("e5", #""action":"archived","reason":"stale""#),
        ]
        let page = #"{"records":[\#(rows.joined(separator: ","))],"count":5,"total_count":null,"next":null}"#
        let transport = MockTransport(json: page)
        let events = try await makeClient(transport).events.list(EventListParams(eventName: .issue, issueId: "i1")).collect()
        #expect(transport.last?.query["issue_id"] == ["i1"])
        let payloads = events.compactMap(\.issue)
        #expect(payloads.map(\.action) == ["created", "updated", "commented", "deleted", "archived"])

        guard case let .created(created) = payloads[0], case let .updated(updated) = payloads[1] else {
            Issue.record("expected created and updated")
            return
        }
        guard case let .commented(commented) = payloads[2], case let .deleted(deleted) = payloads[3] else {
            Issue.record("expected commented and deleted")
            return
        }
        guard case let .unknown(raw) = payloads[4] else {
            Issue.record("expected an unknown action")
            return
        }
        #expect(created.issueId == "i1")
        #expect(created.memberId == "m-1")
        #expect(created.data["title"] == "Checkout times out")
        #expect(updated.revision == 2)
        #expect(updated.changes["status"] == IssueFieldChange(before: "open", after: nil))
        #expect(commented.comment == "On it")
        #expect(commented.actorMemberId == "m-7")
        #expect(commented.actorMemberType == "agent")
        #expect(deleted.revision == 3)
        #expect(deleted.memberId == nil)
        #expect(raw["reason"] == "stale")

        let wire = try JSONCoding.decoder.decode(JSONValue.self, from: JSONCoding.encoder.encode(payloads[3]))
        #expect(wire["action"] == "deleted")
        #expect(wire["issue_id"] == "i1")
    }

    @Test func eventsListAsksForLatestRecords() async throws {
        let transport = MockTransport(json: #"{"records":[],"count":0,"total_count":null,"next":null}"#)
        let client = makeClient(transport)
        _ = try await client.events.list(
            EventListParams(eventName: .track, conversationId: "c1", names: ["todo", "goal"], latestRecords: true)
        ).collect()
        let q = try #require(transport.last).query
        #expect(q["latest"] == ["true"])
        #expect(q["conversation_id"] == ["c1"])
        #expect(q["name"] == ["todo", "goal"])
    }

    @Test func eventGetAndTypedPayloads() async throws {
        let observation = #"""
            {"id":"o1","timestamp":"2026-10-01T12:00:00Z","event_name":"introspection.observation",
             "payload":{"observation_id":"0199a1b2-0000-7000-8000-000000000001","lens":"friction","label":"slow",
             "confidence":0.9,"evidence_refs":["m:1"],"pattern_id":"p1","assignment_score":0.8,"metadata":{"a":"b"}}}
            """#
        let transport = MockTransport(json: observation)
        let client = makeClient(transport)
        let event = try await client.events.get("o/1")
        #expect(transport.last?.request.url.absoluteString.hasSuffix("/v1/events/o%2F1") ?? false)
        let payload = try #require(event.observation)
        #expect(payload.lens == "friction")
        #expect(payload.patternId == "p1")
        #expect(payload.evidenceRefs == ["m:1"])
        let custom = try event.decodePayload(JSONObject.self)
        #expect(custom["label"] == "slow")

        let pattern = try JSONCoding.decoder.decode(
            IntrospectionEvent.self,
            from: Data(
                #"""
                {"id":"p1","timestamp":"2026-10-01T12:00:00Z","event_name":"introspection.pattern",
                 "payload":{"pattern_id":"p1","status":"active","created_at":"2026-09-01T00:00:00Z","last_detected_at":"2026-10-01T00:00:00.123456Z"}}
                """#.utf8))
        #expect(pattern.pattern?.status == "active")
        #expect(pattern.pattern?.lastDetectedAt != nil)
    }

    @Test func metricsQueryEncodingAndDecoding() async throws {
        let response = #"""
            {"data":[{"timestamp":1790000000000,"dimensions":[{"field":"service_name","value":"svc"}],
              "metrics":[{"metric_index":0,"measure":null,"aggregation":"count","value":12},
                         {"metric_index":1,"measure":"duration_ms","aggregation":"p95","value":340.5}]}],
             "meta":{"view":"spans","window":{"start":"2026-10-01T00:00:00Z","end":"2026-10-02T00:00:00Z"},
              "row_count":1,"row_limit":100,"interval":"1h","step_seconds":3600,"approximate":true,"truncated":false,
              "owner_scoped":false,"order_by":[{"type":"metric","direction":"desc","metric_index":0}]}}
            """#
        let transport = MockTransport(json: response)
        let client = makeClient(transport)
        let from = Date(timeIntervalSince1970: 1_790_000_000)
        let to = from.addingTimeInterval(86_400)
        let result = try await client.metrics.query(
            MetricQueryRequest(
                view: .spans,
                metrics: [.count, MetricSpec(.p95, measure: "duration_ms")],
                from: from, to: to,
                dimensions: [MetricDimension("service_name")],
                filters: [MetricFilter("status", .in, ["Ok", "Error"]), MetricFilter("model", .exists)],
                timeDimension: MetricTimeDimension(granularity: .oneHour),
                orderBy: [.metric(0, .desc)],
                having: [MetricHaving(metricIndex: 0, .gt, 5)],
                config: MetricQueryConfig(rowLimit: 100, seriesLimit: 10)
            ))

        #expect(transport.last?.request.method == "POST")
        #expect(transport.last?.path == "/v1/metrics")
        #expect(
            transport.last?.json == [
                "view": "spans",
                "metrics": [["aggregation": "count"], ["aggregation": "p95", "measure": "duration_ms"]],
                "dimensions": [["field": "service_name"]],
                "filters": [
                    ["field": "status", "operator": "in", "value": ["Ok", "Error"]],
                    ["field": "model", "operator": "exists"],
                ],
                "time_dimension": ["granularity": "1h"],
                "order_by": [["type": "metric", "direction": "desc", "metric_index": 0]],
                "having": [["metric_index": 0, "operator": "gt", "value": 5]],
                "from_timestamp": .string(ISO8601.format(from)),
                "to_timestamp": .string(ISO8601.format(to)),
                "config": ["row_limit": 100, "series_limit": 10],
            ])

        let row = try #require(result.data.first)
        #expect(row.value(at: 0) == 12)
        #expect(row.value(at: 1) == 340.5)
        #expect(row.dimension("service_name") == "svc")
        #expect(row.date == from)
        #expect(row.metrics[0].measure == nil)
        #expect(result.meta?.interval == .oneHour)
        #expect(result.meta?.approximate == true)
        #expect(result.meta?.orderBy?.first?.metricIndex == 0)
        #expect(result.meta?.window?.start != nil)
    }

    @Test func sharesRoutes() async throws {
        let share = #"""
            {"id":"sh1","org_id":"o","project_id":"p","created_at":"2026-10-01T12:00:00Z","updated_at":"2026-10-01T12:00:00Z",
             "deleted_at":null,"resource_type":"conversation","resource_id":"c1","granted_member_id":null,
             "granted_tag":"team:support","visible_from":"2026-09-30T08:00:00Z","created_by_member_id":"m1",
             "url":"https://dp.test/v1/conversations/c1/items"}
            """#
        let transport = MockTransport { request, _ in
            switch request.method {
            case "DELETE": return .response(HTTPResponse(status: 204, headers: [:], body: Data()))
            case "GET" where request.url.path == "/v1/shares":
                return .response(.json(#"{"records":[\#(share)],"count":1,"total_count":null,"next":null}"#))
            default: return .response(.json(share, status: request.method == "POST" ? 201 : 200))
            }
        }
        let client = makeClient(transport)
        let shares = try await client.shares.list(
            ShareListParams(resourceType: .conversation, createdByMe: true, grantedTag: "team:support")
        ).collect()
        let first = try #require(shares.first)
        #expect(first.url == "https://dp.test/v1/conversations/c1/items")
        #expect(first.grantedMemberId == nil)
        #expect(first.grantedTag == "team:support")
        #expect(first.visibleFrom == ISO8601.parse("2026-09-30T08:00:00Z"))
        #expect(first.deletedAt == nil)
        #expect(transport.last?.query["resource_type"] == ["conversation"])
        #expect(transport.last?.query["created_by_me"] == ["true"])
        #expect(transport.last?.query["granted_tag"] == ["team:support"])

        let from = try #require(ISO8601.parse("2026-09-30T08:00:00Z"))
        let created = try await client.shares.create(
            ShareCreate(resourceType: .conversation, resourceId: "c1", grantedMemberId: "m2", grantedTag: "team:support", visibleFrom: from)
        )
        #expect(created.id == "sh1")
        #expect(
            transport.last?.json == [
                "resource_type": "conversation", "resource_id": "c1", "granted_member_id": "m2", "granted_tag": "team:support",
                "visible_from": .string(ISO8601.format(from)),
            ])

        _ = try await client.shares.create(ShareCreate(resourceType: .issue, resourceId: "i1"))
        #expect(transport.last?.json == ["resource_type": "issue", "resource_id": "i1"])

        _ = try await client.shares.update("sh1", ShareUpdate(visibleFrom: from))
        #expect(transport.last?.request.method == "PATCH")
        #expect(transport.last?.path == "/v1/shares/sh1")
        #expect(transport.last?.json == ["visible_from": .string(ISO8601.format(from))])
        _ = try await client.shares.update("sh1", ShareUpdate(visibleFrom: nil))
        #expect(transport.last?.bodyString == #"{"visible_from":null}"#)

        _ = try await client.shares.get("sh1")
        #expect(transport.last?.path == "/v1/shares/sh1")
        try await client.shares.delete("sh1")
        #expect(transport.last?.request.method == "DELETE")
    }
}
