import Foundation
import Testing

@testable import IntrospectionSDK

let issueJSON = #"""
    {
      "id": "0199a000-0000-7000-8000-000000000001", "org_id": "o", "project_id": "p",
      "created_at": "2026-10-01T00:00:00Z", "updated_at": "2026-10-02T00:00:00Z",
      "files": [{"file_id": "f-1", "name": "trace.txt", "checksum": "sha256:ab", "source_event_ids": ["e-1"]}],
      "links": [{"url": "https://example.com/ticket/1", "title": "Ticket"}],
      "events": [{"event_id": "e-2"}],
      "spans": [{"trace_id": "0af7651916cd43dd8448eb211c80319c", "span_id": "b7ad6b7169203331"}],
      "title": "Checkout times out", "description": "Users see a spinner.", "priority": "high",
      "tags": ["customer:acme"], "metadata": {"severity": 2, "area": "billing", "beta": true, "owner": null},
      "display_index": 42, "status": "waiting", "revision": 3, "task_id": "t-1", "task_status": "running",
      "member_id": null, "closed_at": null,
      "open_requests": [{"id": "r-1", "question": "Roll back?", "assignee_id": "m-1", "created_at": "2026-10-02T00:00:00Z"}]
    }
    """#

@Suite struct IssuesTests {
    @Test func decodesTheServerModel() async throws {
        let transport = MockTransport(json: issueJSON)
        let issue = try await makeClient(transport).issues.get("0199a000-0000-7000-8000-000000000001")

        #expect(transport.last?.request.method == "GET")
        #expect(transport.last?.path == "/v1/issues/0199a000-0000-7000-8000-000000000001")
        #expect(issue.title == "Checkout times out")
        #expect(issue.priority == .high)
        #expect(issue.status == .waiting)
        #expect(issue.revision == 3)
        #expect(issue.displayIndex == 42)
        #expect(issue.taskStatus == .running)
        #expect(issue.memberId == nil)
        #expect(issue.metadata?["severity"] == 2)
        #expect(issue.files == [IssueFile(fileId: "f-1", name: "trace.txt", checksum: "sha256:ab", sourceEventIds: ["e-1"])])
        #expect(issue.links == [IssueLink(url: "https://example.com/ticket/1", title: "Ticket")])
        #expect(issue.events == [IssueEventReference(eventId: "e-2")])
        #expect(issue.spans == [IssueSpanReference(traceId: "0af7651916cd43dd8448eb211c80319c", spanId: "b7ad6b7169203331")])
        #expect(issue.openRequests?.first?.assigneeId == "m-1")
    }

    @Test func decodesAMinimalIssueAndAnUnknownStatus() throws {
        let issue = try JSONCoding.decoder.decode(Issue.self, from: Data(#"{"id": "i", "title": "t", "status": "snoozed"}"#.utf8))
        #expect(issue.status == IssueStatus(rawValue: "snoozed"))
        #expect(issue.openRequests == nil)
    }

    @Test func listSendsEveryFilter() async throws {
        let transport = MockTransport(json: #"{"records": [\#(issueJSON)], "count": 1, "total_count": 7, "next": "n2"}"#)
        let params = IssueListParams(
            limit: 20, next: "c1", status: [.open, .waiting], owner: [.me], assignedToMe: true, hasOpenRequests: false,
            taskStatus: [.running], excludeTaskStatus: [.failed, .cancelled], displayIndex: 42, tag: "customer:acme",
            metadata: ["b": "2", "a": "1"], search: "checkout", includeTotal: true)
        let page = try await makeClient(transport).issues.list(params).firstPage()

        let query = try #require(transport.last?.query)
        #expect(transport.last?.path == "/v1/issues")
        #expect(query["limit"] == ["20"])
        #expect(query["next"] == ["c1"])
        #expect(query["status"] == ["open", "waiting"])
        #expect(query["owner"] == ["me"])
        #expect(query["assigned_to_me"] == ["true"])
        #expect(query["has_open_requests"] == ["false"])
        #expect(query["task_status"] == ["running"])
        #expect(query["exclude_task_status"] == ["failed", "cancelled"])
        #expect(query["display_index"] == ["42"])
        #expect(query["tag"] == ["customer:acme"])
        #expect(query["metadata"] == ["a:1", "b:2"])
        #expect(query["search"] == ["checkout"])
        #expect(query["include_total"] == ["true"])
        #expect(page.records.first?.displayIndex == 42)
        #expect(page.totalCount == 7)
        #expect(page.next == "n2")
    }

    @Test func listWithoutFiltersSendsNoQuery() async throws {
        let transport = MockTransport(json: #"{"records": [], "count": 0}"#)
        _ = try await makeClient(transport).issues.list().firstPage()
        #expect(transport.last?.query.isEmpty == true)
    }

    @Test func createSendsTheBriefAndIdempotencyKey() async throws {
        let transport = MockTransport(status: 201, json: issueJSON)
        let body = IssueCreate(
            title: "Checkout times out", description: "Users see a spinner.", taskId: "t-1", priority: .high,
            tags: ["customer:acme"], metadata: ["severity": 2], files: [IssueFile(fileId: "f-1")],
            links: [IssueLink(url: "https://example.com/ticket/1")], events: [IssueEventReference(eventId: "e-2")],
            spans: [IssueSpanReference(traceId: "0af7651916cd43dd8448eb211c80319c", spanId: "b7ad6b7169203331")])
        _ = try await makeClient(transport).issues.create(body, idempotencyKey: "attempt-1")

        #expect(transport.last?.request.method == "POST")
        #expect(transport.last?.path == "/v1/issues")
        #expect(transport.last?.request.headers["Idempotency-Key"] == "attempt-1")
        #expect(
            transport.last?.json
                == [
                    "title": "Checkout times out", "description": "Users see a spinner.", "task_id": "t-1", "priority": "high",
                    "tags": ["customer:acme"], "metadata": ["severity": 2], "files": [["file_id": "f-1"]],
                    "links": [["url": "https://example.com/ticket/1"]], "events": [["event_id": "e-2"]],
                    "spans": [["trace_id": "0af7651916cd43dd8448eb211c80319c", "span_id": "b7ad6b7169203331"]],
                ])
    }

    @Test func createWithoutAKeySendsNoIdempotencyHeader() async throws {
        let transport = MockTransport(status: 201, json: issueJSON)
        _ = try await makeClient(transport).issues.create(IssueCreate(title: "t", description: "d", taskId: "t-1"))
        #expect(transport.last?.request.headers["Idempotency-Key"] == nil)
        #expect(transport.last?.json == ["title": "t", "description": "d", "task_id": "t-1"])
    }

    @Test func updateSendsOnlyTheSetFields() async throws {
        let transport = MockTransport(json: issueJSON)
        _ = try await makeClient(transport).issues.update("i-1", IssueUpdate(expectedRevision: 3, status: .closed, tags: []))

        #expect(transport.last?.request.method == "PATCH")
        #expect(transport.last?.path == "/v1/issues/i-1")
        #expect(transport.last?.json == ["expected_revision": 3, "status": "closed", "tags": []])
    }

    @Test func updateARequestWrapsIt() async throws {
        let transport = MockTransport(json: issueJSON)
        let change = IssueRequestMutation(id: "r-1", expectedRevision: 2, status: .resolved, resolution: "Rolled back.")
        _ = try await makeClient(transport).issues.update("i-1", request: change, idempotencyKey: "k")

        #expect(transport.last?.request.method == "PATCH")
        #expect(transport.last?.request.headers["Idempotency-Key"] == "k")
        #expect(
            transport.last?.json
                == ["request": ["id": "r-1", "expected_revision": 2, "status": "resolved", "resolution": "Rolled back."]])
    }

    @Test func deleteSendsTheKey() async throws {
        let transport = MockTransport { _, _ in .response(HTTPResponse(status: 204, headers: [:], body: Data())) }
        try await makeClient(transport).issues.delete("a/b", idempotencyKey: "k")
        #expect(transport.last?.request.method == "DELETE")
        #expect(transport.last?.request.url.absoluteString == "https://dp.test/v1/issues/a%2Fb")
        #expect(transport.last?.request.headers["Idempotency-Key"] == "k")
    }

    @Test func aStaleRevisionIsAConflict() async throws {
        let transport = MockTransport(status: 409, json: #"{"detail": "Issue revision changed"}"#)
        let error = try await #require(throws: IntrospectionError.self) {
            try await makeClient(transport).issues.update("i-1", IssueUpdate(expectedRevision: 1, title: "t"))
        }
        #expect(error.kind == .conflict)
    }
}
