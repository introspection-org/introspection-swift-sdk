import Foundation
import Testing

@testable import IntrospectionSDK

/// A response from a newer server, carrying fields and enum values this SDK does not know, still decodes.
@Suite struct ForwardCompatibilityTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONCoding.decoder.decode(T.self, from: Data(json.utf8))
    }

    private func reencoded<T: Codable>(_ value: T) throws -> JSONValue {
        try JSONCoding.decoder.decode(JSONValue.self, from: JSONCoding.encoder.encode(value))
    }

    @Test func annotationStatePageIgnoresUnknownFields() throws {
        let page = try decode(
            Page<AnnotationState>.self,
            #"""
            {
              "records": [
                {
                  "trace_id": "0123456789abcdef0123456789abcdef",
                  "span_id": "0123456789abcdef",
                  "labels": ["bug"],
                  "comment_count": 1,
                  "review_priority": "urgent",
                  "future_object": {"nested_new_field": [1, 2, 3], "status": "brand_new"}
                }
              ],
              "count": 1,
              "next": "p2",
              "server_hint": {"shape": "new"}
            }
            """#
        )
        let state = try #require(page.records.first)
        #expect(state.traceId == "0123456789abcdef0123456789abcdef")
        #expect(state.labels == ["bug"])
        #expect(state.commentCount == 1)
        #expect(page.next == "p2")
    }

    @Test func taskKeepsUnknownStatusKindAndNestedFields() throws {
        let task = try decode(
            IntrospectionTask.self,
            #"""
            {
              "id": "t1",
              "status": "teleporting",
              "kind": "simulation",
              "brand_new_field": {"a": 1},
              "agent": {"sandbox_status": "Running", "sandbox_region": "mars-1"}
            }
            """#
        )
        #expect(task.status.rawValue == "teleporting")
        #expect(task.kind.rawValue == "simulation")
        #expect(task.agent?.sandboxStatus == "Running")
        let wire = try reencoded(task)
        #expect(wire["status"] == .string("teleporting"))
        #expect(wire["kind"] == .string("simulation"))
    }

    @Test func tagKeepsUnknownKind() throws {
        let page = try decode(
            Page<SDKTag>.self,
            #"""
            {
              "records": [
                {"kind": "access", "name": "vip"},
                {"kind": "routing", "name": "eu", "priority": 3}
              ],
              "count": 2
            }
            """#
        )
        #expect(page.records.map(\.kind) == [.access, "routing"])
        #expect(page.records[1].kind.rawValue == "routing")
        #expect(try reencoded(page.records[1])["kind"] == .string("routing"))
    }

    @Test func integrationRepositoriesKeepUnknownProvider() throws {
        let repositories = try decode(
            IntegrationRepositories.self,
            #"{"type": "gitlab", "records": [{"id": 1, "path": "group/project"}], "total": 1}"#
        )
        #expect(repositories.integrationType.rawValue == "gitlab")
    }

    @Test func connectionTokenResultKeepsAnUnknownStatus() throws {
        let json = #"{"status":"step_up_required","challenge_url":"https://consent.test/c"}"#
        let result = try decode(ConnectionTokenResult.self, json)
        guard case let .unknown(raw) = result else {
            Issue.record("expected .unknown, got \(result)")
            return
        }
        #expect(raw["challenge_url"]?.stringValue == "https://consent.test/c")
        #expect(try reencoded(result) == decode(JSONValue.self, json))
        #expect(try decode(ConnectionTokenResult.self, #"{"token":"t"}"#).token?.token == "t")
    }

    @Test func repositoryContentKeepsAnUnknownType() throws {
        let json = #"{"type":"symlink","path":"docs/link","target":"README.md"}"#
        let content = try decode(RepositoryContent.self, json)
        guard case let .unknown(raw) = content else {
            Issue.record("expected .unknown, got \(content)")
            return
        }
        #expect(raw["target"]?.stringValue == "README.md")
        #expect(content.path == "docs/link")
        #expect(try reencoded(content) == decode(JSONValue.self, json))
    }
}
