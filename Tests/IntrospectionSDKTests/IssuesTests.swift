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
      "display_key": "I-42",
      "status": "waiting",
      "revision": 3,
      "task_id": "0199a1b2-0000-7000-8000-0000000000dd",
      "task_status": "awaiting_user",
      "member_id": null,
      "created_by_member_id": "0199a1b2-0000-7000-8000-0000000000c1",
      "assignee_member_id": "0199a1b2-0000-7000-8000-0000000000c2",
      "reviewer_member_id": null,
      "closed_at": null,
      "members": [
        {"member_id": "0199a1b2-0000-7000-8000-0000000000c1", "relation": "creator"},
        {"member_id": "0199a1b2-0000-7000-8000-0000000000c2", "relation": "assignee"},
        {"member_id": "0199a1b2-0000-7000-8000-0000000000c3", "relation": "follower"}
      ],
      "comments": [
        {"id": "0199a1b2-0000-7000-8000-0000000000d1", "issue_id": "0199a1b2-0000-7000-8000-000000000001",
         "comment": "Can we refund the duplicate charge?", "member_id": "0199a1b2-0000-7000-8000-0000000000c1",
         "actor_member_id": "0199a1b2-0000-7000-8000-0000000000c9", "actor_member_type": "agent",
         "created_at": "2026-10-02T11:00:00Z"}
      ]
    }
    """#

/// An issue as a read without `include` returns it: the brief, and every related list null.
private func briefJSON(_ id: String = "i", title: String = "t", status: String = "open", extra: String = "") -> String {
    #"{"id":"\#(id)","org_id":"o","project_id":"p","title":"\#(title)","description":"d","priority":"medium","status":"\#(status)","revision":1,"tags":[],"metadata":{}\#(extra)}"#
}

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
        #expect(issue.displayKey == "I-42")
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
        #expect(issue.createdByMemberId == "0199a1b2-0000-7000-8000-0000000000c1")
        #expect(issue.assigneeMemberId == "0199a1b2-0000-7000-8000-0000000000c2")
        #expect(issue.reviewerMemberId == nil)
        #expect(issue.members?.map(\.relation) == [.creator, .assignee, .follower])
        #expect(issue.members?.last?.memberId == "0199a1b2-0000-7000-8000-0000000000c3")
        let comment = try #require(issue.comments?.first)
        #expect(comment.id == "0199a1b2-0000-7000-8000-0000000000d1")
        #expect(comment.issueId == issue.id)
        #expect(comment.comment == "Can we refund the duplicate charge?")
        #expect(comment.memberId == "0199a1b2-0000-7000-8000-0000000000c1")
        #expect(comment.actorMemberType == "agent")
        #expect(comment.createdAt == ISO8601.parse("2026-10-02T11:00:00Z"))
        #expect(issue.createdAt == ISO8601.parse("2026-10-01T10:00:00Z"))
        #expect(issue.updatedAt == ISO8601.parse("2026-10-02T11:30:00.123Z"))

        let brief = try JSONCoding.decoder.decode(Issue.self, from: Data(briefJSON(status: "brand_new").utf8))
        #expect(brief.status == "brand_new")
        #expect(brief.revision == 1)
        #expect(brief.members == nil)
        #expect(brief.links == nil)
        #expect(brief.files == nil)
        #expect(brief.events == nil)
        #expect(brief.spans == nil)
        #expect(brief.comments == nil)
        #expect(brief.metadata == [:])
        #expect(brief.displayKey == nil)
    }

    @Test func listEncodesRepeatedFiltersAndPaginates() async throws {
        let transport = MockTransport { request, _ in
            request.url.query?.contains("next=") != true
                ? .response(.json(#"{"records":[\#(issueJSON)],"count":1,"total_count":2,"next":"cur-2"}"#))
                : .response(.json(#"{"records":[\#(briefJSON("b", title: "second"))],"count":1,"total_count":2,"next":null}"#))
        }
        let params = IssueListParams(
            limit: 1, status: [.open, .waiting], owner: [.project, .me], relation: [.assignee, .reviewer], memberId: "m-1",
            taskStatus: [.running, .awaitingUser], excludeTaskStatus: [.completed, .cancelled], displayIndex: 42,
            tag: "customer:acme", metadata: ["source": "slack", "env": "prod"], includeTotal: true,
            include: [.members, .attachments]
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
                "limit": ["1"], "status": ["open", "waiting"], "owner": ["project", "me"],
                "relation": ["assignee", "reviewer"], "member_id": ["m-1"], "task_status": ["running", "awaiting_user"],
                "exclude_task_status": ["completed", "cancelled"], "display_index": ["42"], "tag": ["customer:acme"],
                "metadata": ["env:prod", "source:slack"], "include_total": ["true"], "include": ["members", "attachments"],
            ])
        #expect(transport.requests[2].query["next"] == ["cur-2"])
        #expect(transport.requests[2].query["status"] == ["open", "waiting"])
    }

    @Test func listFiltersByDisplayKey() async throws {
        let transport = MockTransport(json: #"{"records":[\#(issueJSON)],"count":1,"next":null}"#)
        let api = makeClient(transport).issues
        let found = try await api.list(IssueListParams(limit: 1, displayKey: "I-42", include: [.members])).collect()
        #expect(found.map(\.displayKey) == ["I-42"])
        #expect(transport.last?.query == ["limit": ["1"], "display_key": ["I-42"], "include": ["members"]])

        var params = IssueListParams()
        params.displayKey = "I-7"
        _ = try await api.list(params).collect()
        #expect(transport.last?.query == ["display_key": ["I-7"]])
    }

    @Test func listWithoutFiltersSendsNoQuery() async throws {
        let transport = MockTransport(json: #"{"records":[],"count":0,"next":null}"#)
        let all = try await makeClient(transport).issues.list().collect()
        #expect(all.isEmpty)
        #expect(transport.last?.query == [:])
    }

    @Test func createEncodesTheBody() async throws {
        let transport = issueTransport(status: 201)
        let api = makeClient(transport).issues
        let created = try await api.create(
            IssueCreate(
                title: "Checkout times out", description: "Payments retry forever.", taskId: "task-1", priority: .urgent,
                files: [IssueFile(fileId: "f-1", sourceEventIds: ["e-1"])], links: [IssueLink(url: "https://example.com/pr/7")],
                events: [IssueEventReference(eventId: "e-2")], spans: [IssueSpanReference(traceId: "t", spanId: "s")],
                tags: ["customer:acme"], metadata: ["count": 3, "triaged": false]
            ))
        #expect(created.revision == 3)
        let sent = try #require(transport.last)
        #expect(sent.request.method == "POST")
        #expect(sent.path == "/v1/issues")
        #expect(sent.request.headers["Idempotency-Key"] == nil)
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
        #expect(transport.last?.query == [:])

        let people = IssueCreate(
            title: "t", description: "d", taskId: "task-1", assigneeMemberId: "m-1", reviewerMemberId: "m-2",
            followerMemberIds: ["m-3", "m-4"]
        )
        _ = try await api.create(people, include: [.members, .attachments])
        #expect(
            transport.last?.json == [
                "title": "t", "description": "d", "task_id": "task-1", "assignee_member_id": "m-1",
                "reviewer_member_id": "m-2", "follower_member_ids": ["m-3", "m-4"],
            ])
        #expect(transport.last?.query == ["include": ["members", "attachments"]])
    }

    @Test func getEscapesTheId() async throws {
        let transport = issueTransport()
        let issue = try await makeClient(transport).issues.get("i/1")
        #expect(issue.title == "Checkout times out")
        #expect(transport.last?.request.method == "GET")
        #expect(transport.last?.request.url.absoluteString == "https://dp.test/v1/issues/i%2F1")

        _ = try await makeClient(transport).issues.get("i-1", include: [.members, .attachments, .comments])
        #expect(transport.last?.path == "/v1/issues/i-1")
        #expect(transport.last?.query == ["include": ["members", "attachments", "comments"]])
    }

    @Test func updateAssignsClearsAndLeavesPeople() async throws {
        let transport = issueTransport()
        let api = makeClient(transport).issues
        _ = try await api.update(
            "i-1", IssueUpdate(status: .waiting, assigneeMemberId: "m-1", reviewerMemberId: .some(nil), followerMemberIds: []),
            include: [.members]
        )
        let sent = try #require(transport.last)
        #expect(
            sent.json == ["status": "waiting", "assignee_member_id": "m-1", "reviewer_member_id": nil, "follower_member_ids": []])
        #expect(sent.query == ["include": ["members"]])

        _ = try await api.update("i-1", IssueUpdate(assigneeMemberId: .some(nil)))
        #expect(transport.last?.bodyString == #"{"assignee_member_id":null}"#)
        #expect(transport.last?.query == [:])

        _ = try await api.update("i-1", IssueUpdate(title: "New title"))
        #expect(transport.last?.bodyString == #"{"title":"New title"}"#)
    }

    @Test func commentCreatePostsTheCommentAndDecodesIt() async throws {
        let transport = MockTransport { _, _ in
            .response(
                .json(
                    #"{"id":"c-1","issue_id":"i-1","comment":"Refund it?","member_id":"m-1","actor_member_id":null,"actor_member_type":null,"created_at":"2026-10-02T11:00:00Z"}"#,
                    status: 201))
        }
        let comment = try await makeClient(transport).issues.comments.create("i/1", comment: "Refund it?")
        #expect(comment.id == "c-1")
        #expect(comment.issueId == "i-1")
        #expect(comment.comment == "Refund it?")
        #expect(comment.memberId == "m-1")
        #expect(comment.actorMemberId == nil)
        #expect(comment.createdAt == ISO8601.parse("2026-10-02T11:00:00Z"))
        let sent = try #require(transport.last)
        #expect(sent.request.method == "POST")
        #expect(sent.request.url.absoluteString == "https://dp.test/v1/issues/i%2F1/comments")
        #expect(sent.json == ["comment": "Refund it?"])
    }

    @Test func updateOmitsUnsetFieldsAndSendsEmptyListsToClear() async throws {
        let transport = issueTransport()
        let api = makeClient(transport).issues
        _ = try await api.update("i-1", IssueUpdate(status: .closed))
        let sent = try #require(transport.last)
        #expect(sent.request.method == "PATCH")
        #expect(sent.path == "/v1/issues/i-1")
        #expect(sent.request.headers["If-Match"] == nil)
        #expect(sent.request.headers["Idempotency-Key"] == nil)
        #expect(sent.json == ["status": "closed"])
        #expect(sent.bodyString == #"{"status":"closed"}"#)

        _ = try await api.update(
            "i-1",
            IssueUpdate(
                title: "New title", description: "New brief", priority: .low, files: [], links: [], events: [], spans: [],
                tags: [], metadata: [:]
            ))
        #expect(
            transport.last?.json == [
                "title": "New title", "description": "New brief", "priority": "low", "files": [],
                "links": [], "events": [], "spans": [], "tags": [], "metadata": [:],
            ])
    }

    @Test func updateSendsIfMatchOnlyWhenGiven() async throws {
        let transport = issueTransport()
        let api = makeClient(transport).issues
        let issue = try await api.get("i-1")
        let etag = try #require(issue.etag)
        _ = try await api.update("i-1", IssueUpdate(title: "New title"), ifMatch: etag)
        #expect(transport.last?.request.headers["If-Match"] == #""2026-10-02T11:30:00.123456Z""#)
        #expect(transport.last?.json == ["title": "New title"])
    }

    @Test(arguments: [
        ("2026-11-04T01:00:00.123456Z", #""2026-11-04T01:00:00.123456Z""#),
        ("2026-11-04T01:00:00Z", #""2026-11-04T01:00:00Z""#),
        ("2026-11-04T01:00:00.123456+00:00", #""2026-11-04T01:00:00.123456+00:00""#),
    ])
    func etagIsUpdatedAtAsReceived(updatedAt: String, etag: String) throws {
        let json = briefJSON(extra: #","updated_at":"\#(updatedAt)""#)
        let issue = try JSONCoding.decoder.decode(Issue.self, from: Data(json.utf8))
        #expect(issue.etag == etag)
        #expect(issue.updatedAt == ISO8601.parse(updatedAt))
        let encoded = try JSONCoding.encoder.encode(issue)
        let reencoded = try JSONCoding.decoder.decode(JSONValue.self, from: encoded)
        #expect(reencoded["updated_at"]?.stringValue == updatedAt)
        #expect(try JSONCoding.decoder.decode(Issue.self, from: encoded) == issue)
    }

    @Test func etagIsNilWithoutUpdatedAt() throws {
        let issue = try JSONCoding.decoder.decode(Issue.self, from: Data(briefJSON().utf8))
        #expect(issue.etag == nil)
    }

    @Test func staleIfMatchSurfacesAs412() async throws {
        let transport = MockTransport { _, _ in
            .response(.json(#"{"detail":"The issue has changed since it was read"}"#, status: 412))
        }
        let api = makeClient(transport).issues
        let error = await #expect(throws: IntrospectionError.self) {
            try await api.update("i-1", IssueUpdate(status: .closed), ifMatch: #""1""#)
        }
        #expect(error?.kind == .http)
        #expect(error?.hasStatus(412) == true)
        #expect(error?.message == "The issue has changed since it was read")
        await #expect(throws: IntrospectionError.self) { try await api.delete("i-1", ifMatch: #""1""#) }
        #expect(transport.last?.request.headers["If-Match"] == #""1""#)
    }

    @Test func deleteSendsIfMatchOnlyWhenGiven() async throws {
        let transport = issueTransport()
        let api = makeClient(transport).issues
        try await api.delete("i/1", ifMatch: #""2026-10-02T11:30:00.123456Z""#)
        #expect(transport.last?.request.method == "DELETE")
        #expect(transport.last?.request.url.absoluteString == "https://dp.test/v1/issues/i%2F1")
        #expect(transport.last?.request.headers["If-Match"] == #""2026-10-02T11:30:00.123456Z""#)
        #expect(transport.last?.request.body == nil)

        try await api.delete("i-2")
        #expect(transport.last?.request.headers["If-Match"] == nil)
        #expect(transport.last?.request.headers["Idempotency-Key"] == nil)
    }
}
