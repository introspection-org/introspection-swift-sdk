import Foundation
import Testing

@testable import IntrospectionSDK

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
