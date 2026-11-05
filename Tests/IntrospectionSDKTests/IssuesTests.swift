import Foundation
import Testing

@testable import IntrospectionSDK

private let issueJSON = #"""
    {
      "created_at": "2026-10-01T10:00:00Z",
      "updated_at": "2026-10-02T11:30:00.123456Z",
      "org_id": "0199a1b2-0000-7000-8000-0000000000aa",
      "project_id": "0199a1b2-0000-7000-8000-0000000000bb",
      "id": "0199a1b2-0000-7000-8000-000000000001",
      "files": [
        {"file_id": "0199a1b2-0000-7000-8000-0000000000f1", "name": "trace.log", "checksum": "sha256:abc",
         "source_event_ids": ["0199a1b2-0000-7000-8000-0000000000e1"]}
      ],
      "links": [{"url": "https://github.com/acme/app/pull/7", "title": "Fix the retry"}],
      "events": [{"event_id": "0199a1b2-0000-7000-8000-0000000000e2"}],
      "spans": [{"trace_id": "0123456789abcdef0123456789abcdef", "span_id": "0123456789abcdef"}],
      "title": "Checkout times out",
      "description": "Payments retry forever after a 504.",
      "priority": "high",
      "tags": ["customer:acme"],
      "metadata": {"source": "slack", "count": 3, "ratio": 0.5, "triaged": true, "owner": null},
      "display_index": 42,
      "status": "waiting",
      "revision": 3,
      "task_id": "0199a1b2-0000-7000-8000-0000000000dd",
      "task_status": "awaiting_user",
      "member_id": null,
      "closed_at": null,
      "open_requests": [
        {"id": "0199a1b2-0000-7000-8000-0000000000c1", "question": "Can we refund the duplicate charge?",
         "assignee_id": "0199a1b2-0000-7000-8000-0000000000c2", "created_at": "2026-10-02T11:00:00Z"}
      ]
    }
    """#

private func issueTransport(status: Int = 200) -> MockTransport {
    MockTransport { request, _ in
        request.method == "DELETE"
            ? .response(HTTPResponse(status: 204, headers: [:], body: Data()))
            : .response(.json(issueJSON, status: status))
    }
}

@Suite struct IssuesTests {
    @Test func decodesServerIssue() throws {
        let issue = try JSONCoding.decoder.decode(Issue.self, from: Data(issueJSON.utf8))
        #expect(issue.id == "0199a1b2-0000-7000-8000-000000000001")
        #expect(issue.orgId == "0199a1b2-0000-7000-8000-0000000000aa")
        #expect(issue.projectId == "0199a1b2-0000-7000-8000-0000000000bb")
        #expect(issue.title == "Checkout times out")
        #expect(issue.description == "Payments retry forever after a 504.")
        #expect(issue.priority == .high)
        #expect(issue.status == .waiting)
        #expect(issue.revision == 3)
        #expect(issue.displayIndex == 42)
        #expect(
            issue.files == [
                IssueFile(
                    fileId: "0199a1b2-0000-7000-8000-0000000000f1", name: "trace.log", checksum: "sha256:abc",
                    sourceEventIds: ["0199a1b2-0000-7000-8000-0000000000e1"])
            ])
        #expect(issue.links == [IssueLink(url: "https://github.com/acme/app/pull/7", title: "Fix the retry")])
        #expect(issue.events == [IssueEventReference(eventId: "0199a1b2-0000-7000-8000-0000000000e2")])
        #expect(issue.spans == [IssueSpanReference(traceId: "0123456789abcdef0123456789abcdef", spanId: "0123456789abcdef")])
        #expect(issue.tags == ["customer:acme"])
        #expect(issue.metadata == ["source": "slack", "count": 3, "ratio": 0.5, "triaged": true, "owner": nil])
        #expect(issue.taskId == "0199a1b2-0000-7000-8000-0000000000dd")
        #expect(issue.taskStatus == .awaitingUser)
        #expect(issue.memberId == nil)
        #expect(issue.closedAt == nil)
        let request = try #require(issue.openRequests?.first)
        #expect(request.id == "0199a1b2-0000-7000-8000-0000000000c1")
        #expect(request.question == "Can we refund the duplicate charge?")
        #expect(request.assigneeId == "0199a1b2-0000-7000-8000-0000000000c2")
        #expect(request.createdAt == ISO8601.parse("2026-10-02T11:00:00Z"))
        #expect(issue.createdAt == ISO8601.parse("2026-10-01T10:00:00Z"))
        #expect(issue.updatedAt == ISO8601.parse("2026-10-02T11:30:00.123Z"))

        let minimal = try JSONCoding.decoder.decode(
            Issue.self,
            from: Data(#"{"id":"i","org_id":"o","project_id":"p","title":"t","description":"d","status":"brand_new"}"#.utf8))
        #expect(minimal.status == "brand_new")
        #expect(minimal.revision == nil)
        #expect(minimal.openRequests == nil)
        #expect(minimal.metadata == nil)
    }

    @Test func listEncodesRepeatedFiltersAndPaginates() async throws {
        let transport = MockTransport { request, _ in
            request.url.query?.contains("next=") != true
                ? .response(.json(#"{"records":[\#(issueJSON)],"count":1,"total_count":2,"next":"cur-2"}"#))
                : .response(
                    .json(
                        #"{"records":[{"id":"b","org_id":"o","project_id":"p","title":"second","description":"d"}],"count":1,"total_count":2,"next":null}"#
                    ))
        }
        let params = IssueListParams(
            limit: 1, status: [.open, .waiting], owner: [.project, .me], assignedToMe: true, hasOpenRequests: false,
            taskStatus: [.running, .awaitingUser], excludeTaskStatus: [.completed, .cancelled], displayIndex: 42,
            tag: "customer:acme", metadata: ["source": "slack", "env": "prod"], search: "checkout", includeTotal: true
        )
        let api = makeClient(transport).issues
        let page = try await api.list(params).firstPage()
        #expect(page.totalCount == 2)
        #expect(page.next == "cur-2")
        let all = try await api.list(params).collect()
        #expect(all.map(\.title) == ["Checkout times out", "second"])
        let first = transport.requests[0]
        #expect(first.request.method == "GET")
        #expect(first.path == "/v1/issues")
        #expect(
            first.query == [
                "limit": ["1"], "status": ["open", "waiting"], "owner": ["project", "me"], "assigned_to_me": ["true"],
                "has_open_requests": ["false"], "task_status": ["running", "awaiting_user"],
                "exclude_task_status": ["completed", "cancelled"], "display_index": ["42"], "tag": ["customer:acme"],
                "metadata": ["env:prod", "source:slack"], "search": ["checkout"], "include_total": ["true"],
            ])
        #expect(transport.requests[2].query["next"] == ["cur-2"])
        #expect(transport.requests[2].query["status"] == ["open", "waiting"])
    }

    @Test func listWithoutFiltersSendsNoQuery() async throws {
        let transport = MockTransport(json: #"{"records":[],"count":0,"next":null}"#)
        let all = try await makeClient(transport).issues.list().collect()
        #expect(all.isEmpty)
        #expect(transport.last?.query == [:])
    }

    @Test func createEncodesTheBodyAndIdempotencyKey() async throws {
        let transport = issueTransport(status: 201)
        let api = makeClient(transport).issues
        let created = try await api.create(
            IssueCreate(
                title: "Checkout times out", description: "Payments retry forever.", taskId: "task-1", priority: .urgent,
                files: [IssueFile(fileId: "f-1", sourceEventIds: ["e-1"])], links: [IssueLink(url: "https://example.com/pr/7")],
                events: [IssueEventReference(eventId: "e-2")], spans: [IssueSpanReference(traceId: "t", spanId: "s")],
                tags: ["customer:acme"], metadata: ["count": 3, "triaged": false]
            ),
            idempotencyKey: "create-1"
        )
        #expect(created.revision == 3)
        let sent = try #require(transport.last)
        #expect(sent.request.method == "POST")
        #expect(sent.path == "/v1/issues")
        #expect(sent.request.headers["Idempotency-Key"] == "create-1")
        #expect(
            sent.json == [
                "title": "Checkout times out", "description": "Payments retry forever.", "task_id": "task-1",
                "priority": "urgent", "files": [["file_id": "f-1", "source_event_ids": ["e-1"]]],
                "links": [["url": "https://example.com/pr/7"]], "events": [["event_id": "e-2"]],
                "spans": [["trace_id": "t", "span_id": "s"]], "tags": ["customer:acme"],
                "metadata": ["count": 3, "triaged": false],
            ])

        _ = try await api.create(IssueCreate(title: "t", description: "d", taskId: "task-1"))
        #expect(transport.last?.json == ["title": "t", "description": "d", "task_id": "task-1"])
        #expect(transport.last?.request.headers["Idempotency-Key"] == nil)
    }

    @Test func getEscapesTheId() async throws {
        let transport = issueTransport()
        let issue = try await makeClient(transport).issues.get("i/1")
        #expect(issue.title == "Checkout times out")
        #expect(transport.last?.request.method == "GET")
        #expect(transport.last?.request.url.absoluteString == "https://dp.test/v1/issues/i%2F1")
    }

    @Test func updateOmitsUnsetFieldsAndSendsEmptyListsToClear() async throws {
        let transport = issueTransport()
        let api = makeClient(transport).issues
        _ = try await api.update("i-1", IssueUpdate(expectedRevision: 3, status: .closed), idempotencyKey: "edit-1")
        let sent = try #require(transport.last)
        #expect(sent.request.method == "PATCH")
        #expect(sent.path == "/v1/issues/i-1")
        #expect(sent.request.headers["Idempotency-Key"] == "edit-1")
        #expect(sent.json == ["expected_revision": 3, "status": "closed"])
        #expect(sent.bodyString == #"{"expected_revision":3,"status":"closed"}"#)

        _ = try await api.update(
            "i-1",
            IssueUpdate(
                expectedRevision: 4, title: "New title", description: "New brief", priority: .low, files: [], links: [],
                events: [], spans: [], tags: [], metadata: [:]
            ))
        #expect(
            transport.last?.json == [
                "expected_revision": 4, "title": "New title", "description": "New brief", "priority": "low", "files": [],
                "links": [], "events": [], "spans": [], "tags": [], "metadata": [:],
            ])
        #expect(transport.last?.request.headers["Idempotency-Key"] == nil)
    }

    @Test func updateCreatesAndChangesAHumanRequest() async throws {
        let transport = issueTransport()
        let api = makeClient(transport).issues
        let create = IssueRequestMutation.create(question: "Refund it?", assigneeId: "m-1", id: "r-1")
        _ = try await api.update("i-1", IssueMutation(request: create), idempotencyKey: "ask-1")
        let sent = try #require(transport.last)
        #expect(sent.request.method == "PATCH")
        #expect(sent.path == "/v1/issues/i-1")
        #expect(sent.request.headers["Idempotency-Key"] == "ask-1")
        #expect(
            sent.json == ["request": ["id": "r-1", "expected_revision": 0, "question": "Refund it?", "assignee_id": "m-1"]])

        _ = try await api.update(
            "i-1",
            IssueMutation(
                request: IssueRequestMutation(id: "r-1", expectedRevision: 2, status: .resolved, resolution: "Refunded")))
        #expect(
            transport.last?.json == [
                "request": ["id": "r-1", "expected_revision": 2, "status": "resolved", "resolution": "Refunded"]
            ])
    }

    @Test func newRequestMintsAUUIDv7() {
        let request = IssueRequestMutation.create(question: "q", assigneeId: "m-1")
        #expect(request.expectedRevision == 0)
        #expect(request.id.count == 36)
        #expect(Array(request.id)[14] == "7")
        #expect(request.status == nil)
    }

    @Test func deleteSendsTheIdempotencyKey() async throws {
        let transport = issueTransport()
        let api = makeClient(transport).issues
        try await api.delete("i/1", idempotencyKey: "delete-1")
        #expect(transport.last?.request.method == "DELETE")
        #expect(transport.last?.request.url.absoluteString == "https://dp.test/v1/issues/i%2F1")
        #expect(transport.last?.request.headers["Idempotency-Key"] == "delete-1")
        #expect(transport.last?.request.body == nil)

        try await api.delete("i-2")
        #expect(transport.last?.request.headers["Idempotency-Key"] == nil)
    }
}
