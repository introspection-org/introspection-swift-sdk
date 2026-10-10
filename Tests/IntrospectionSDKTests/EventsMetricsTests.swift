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
                conversationIds: ["c1", "c2"], ownerKey: "user:u1", eventIds: ["e1"], includeSuperseded: true,
                latestRequests: true
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
        #expect(q["request"] == ["true"])

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
