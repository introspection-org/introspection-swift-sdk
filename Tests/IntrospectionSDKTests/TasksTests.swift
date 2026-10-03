import Foundation
import XCTest

@testable import IntrospectionSDK

final class TasksTests: XCTestCase {
    static let taskJSON = #"""
        {
          "id": "0192f0a0-0000-7000-8000-000000000001",
          "org_id": "0192f0a0-0000-7000-8000-0000000000aa",
          "project_id": "0192f0a0-0000-7000-8000-0000000000bb",
          "created_at": "2026-09-30T12:00:00.123456Z",
          "updated_at": "2026-09-30T12:05:00+00:00",
          "title": "Summarize my week",
          "display_index": 42,
          "status": "awaiting_user",
          "kind": "eval",
          "member_id": "0192f0a0-0000-7000-8000-0000000000cc",
          "automation_id": null,
          "runtime_id": "0192f0a0-0000-7000-8000-0000000000dd",
          "is_archived": false,
          "started_at": "2026-09-30T12:00:01Z",
          "completed_at": null,
          "last_user_message_at": "2026-09-30T12:04:00Z",
          "metadata": {"conversation_id": "conv-1", "agent_name": "researcher", "pending_interrupts": [{"id": "i1"}]},
          "conversation_metadata": {"flow": "checkout"},
          "tags": ["customer:acme"],
          "agent": {"sandbox_status": "Running", "session_id": "sess-1"}
        }
        """#

    static let runJSON =
        #"{"id":"run-1","task_id":"0192f0a0-0000-7000-8000-000000000001","status":"queued","created_at":"2026-09-30T12:00:00Z","updated_at":null}"#

    func testDecodesRealisticTask() throws {
        let task = try JSONCoding.decoder.decode(IntrospectionTask.self, from: Data(Self.taskJSON.utf8))
        XCTAssertEqual(task.id, "0192f0a0-0000-7000-8000-000000000001")
        XCTAssertEqual(task.status, .awaitingUser)
        XCTAssertEqual(task.kind, .eval)
        XCTAssertEqual(task.displayIndex, 42)
        XCTAssertEqual(task.runtimeId, "0192f0a0-0000-7000-8000-0000000000dd")
        XCTAssertNil(task.automationId)
        XCTAssertNil(task.completedAt)
        XCTAssertNotNil(task.createdAt)
        XCTAssertEqual(task.conversationMetadata, ["flow": "checkout"])
        XCTAssertEqual(task.tags, ["customer:acme"])
        XCTAssertEqual(task.agent?.sandboxStatus, "Running")
        XCTAssertEqual(task.agent?.sessionId, "sess-1")
        XCTAssertEqual(task.conversationId, "conv-1")
        XCTAssertEqual(task.metadata?["agent_name"]?.stringValue, "researcher")
        XCTAssertFalse(task.status.isTerminal)
    }

    func testMinimalTaskAndUnknownStatusDecode() throws {
        let task = try JSONCoding.decoder.decode(IntrospectionTask.self, from: Data(#"{"id":"t1","status":"hibernating","extra":1}"#.utf8))
        XCTAssertEqual(task.status.rawValue, "hibernating")
        XCTAssertEqual(task.kind, .agent)
        XCTAssertFalse(task.isArchived)
        XCTAssertEqual(task.tags, [])
        XCTAssertEqual(task.conversationId, "t1")
    }

    func testListEncodesEveryFilterAndPages() async throws {
        let transport = MockTransport { request, index in
            let records = "[\(TasksTests.taskJSON)]"
            return index == 0
                ? .response(.json(#"{"records":\#(records),"count":1,"total_count":2,"next":"cursor-2"}"#))
                : .response(.json(#"{"records":[{"id":"t2","status":"completed"}],"count":1,"next":null}"#))
        }
        let client = makeClient(transport)
        let params = TaskListParams(
            limit: 1, next: "cursor-1", includeTotal: true, statuses: [.running, .idle],
            runtimeId: "rt-1", runtimeIds: ["rt-2", "rt-3"],
            updatedAfter: Date(timeIntervalSince1970: 1_790_000_000),
            requireAutomationId: false, automationId: "auto-1", memberId: "m-1",
            conversationId: "conv-1", conversationIds: ["c-a", "c-b"], tag: "customer:acme"
        )
        let tasks = try await client.tasks.list(params).collect()
        XCTAssertEqual(tasks.map(\.id), ["0192f0a0-0000-7000-8000-000000000001", "t2"])
        XCTAssertEqual(tasks.last?.status, .completed)

        let first = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(first.request.method, "GET")
        XCTAssertEqual(first.path, "/v1/tasks")
        let q = first.query
        XCTAssertEqual(q["next"], ["cursor-1"])
        XCTAssertEqual(q["limit"], ["1"])
        XCTAssertEqual(q["include_total"], ["true"])
        XCTAssertEqual(q["statuses"], ["running", "idle"])
        XCTAssertEqual(q["runtime_id"], ["rt-1"])
        XCTAssertEqual(q["runtime_ids"], ["rt-2", "rt-3"])
        XCTAssertEqual(q["updated_after"]?.count, 1)
        XCTAssertEqual(q["require_automation_id"], ["false"])
        XCTAssertEqual(q["automation_id"], ["auto-1"])
        XCTAssertEqual(q["member_id"], ["m-1"])
        XCTAssertEqual(q["conversation_id"], ["conv-1"])
        XCTAssertEqual(q["conversation_ids"], ["c-a", "c-b"])
        XCTAssertEqual(q["tag"], ["customer:acme"])
        XCTAssertEqual(transport.requests[1].query["next"], ["cursor-2"])
        XCTAssertEqual(transport.requests[1].query["tag"], ["customer:acme"])
    }

    func testCreateEncodesSnakeCaseBodyAndOmitsNils() async throws {
        let transport = MockTransport { _, _ in
            .response(.json(#"{"task":\#(TasksTests.taskJSON),"run":\#(TasksTests.runJSON)}"#, status: 201))
        }
        let client = makeClient(transport)
        let body = TaskCreate(
            prompt: "Summarize my week",
            kind: .eval,
            agentName: "researcher",
            runtimeId: "rt-1",
            bindingsRequired: false,
            repositories: [TaskRepoRequest(repo: "acme/api", ref: "main", depth: 0)],
            idleTimeoutSeconds: 0,
            metadata: ["source": "ios"],
            conversationMetadata: ["flow": "checkout"],
            tags: ["customer:acme"],
            files: [TaskFileRef(id: "f-1", name: "specs/a.md", sizeBytes: 12)],
            commands: true,
            compose: ["services": ["db": ["image": "postgres:17"]]],
            forkShareId: "share-1"
        )
        let response = try await client.tasks.create(body)
        XCTAssertEqual(response.run.id, "run-1")
        XCTAssertEqual(response.run.status, .queued)
        XCTAssertEqual(response.task.title, "Summarize my week")

        let last = try XCTUnwrap(transport.last)
        XCTAssertEqual(last.request.method, "POST")
        XCTAssertEqual(last.path, "/v1/tasks")
        let json = try XCTUnwrap(last.json)
        XCTAssertEqual(json["prompt"], "Summarize my week")
        XCTAssertEqual(json["kind"], "eval")
        XCTAssertEqual(json["agent_name"], "researcher")
        XCTAssertEqual(json["runtime_id"], "rt-1")
        XCTAssertEqual(json["bindings_required"], false)
        XCTAssertEqual(json["repositories"], [["repo": "acme/api", "ref": "main", "depth": 0]])
        XCTAssertEqual(json["idle_timeout_seconds"], 0)
        XCTAssertEqual(json["metadata"], ["source": "ios"])
        XCTAssertEqual(json["conversation_metadata"], ["flow": "checkout"])
        XCTAssertEqual(json["tags"], ["customer:acme"])
        XCTAssertEqual(json["files"], [["id": "f-1", "name": "specs/a.md", "size_bytes": 12]])
        XCTAssertEqual(json["commands"], true)
        XCTAssertEqual(json["compose"]?["services"]?["db"]?["image"], "postgres:17")
        XCTAssertEqual(json["fork_share_id"], "share-1")
        XCTAssertNil(json["title"])
        XCTAssertNil(json["recipe_patch"])
        XCTAssertNil(json["collect_sandbox_logs"])
    }

    func testGetWithIncludeUpdateDeleteArchive() async throws {
        let transport = MockTransport { request, _ in
            switch request.method {
            case "GET", "PATCH": return .response(.json(TasksTests.taskJSON))
            default: return .response(HTTPResponse(status: 204, headers: [:], body: Data()))
            }
        }
        let client = makeClient(transport)
        let id = "task/1"

        _ = try await client.tasks.get(id)
        XCTAssertEqual(transport.last?.request.url.absoluteString, "https://dp.test/v1/tasks/task%2F1")
        XCTAssertNil(transport.last?.query["include"])

        let task = try await client.tasks.get(id, include: [.agent])
        XCTAssertEqual(task.agent?.sessionId, "sess-1")
        XCTAssertEqual(transport.last?.query["include"], ["agent"])

        _ = try await client.tasks.update(id, TaskUpdate(title: "Renamed", tags: []))
        XCTAssertEqual(transport.last?.request.method, "PATCH")
        XCTAssertEqual(transport.last?.json, ["title": "Renamed", "tags": []])

        try await client.tasks.delete(id)
        XCTAssertEqual(transport.last?.request.method, "DELETE")
        XCTAssertEqual(transport.last?.request.url.absoluteString, "https://dp.test/v1/tasks/task%2F1")

        try await client.tasks.archive(id)
        XCTAssertEqual(transport.last?.request.method, "POST")
        XCTAssertEqual(transport.last?.request.url.absoluteString, "https://dp.test/v1/tasks/task%2F1/archive")

        try await client.tasks.unarchive(id)
        XCTAssertEqual(transport.last?.request.url.absoluteString, "https://dp.test/v1/tasks/task%2F1/unarchive")
    }

    func testRunsCreateResumeGetCancel() async throws {
        let transport = MockTransport { request, _ in
            if request.url.path.hasSuffix("/cancel") { return .response(.json(#"{"id":"run-1"}"#)) }
            if request.method == "GET" { return .response(.json(TasksTests.runJSON)) }
            return .response(.json(#"{"run":\#(TasksTests.runJSON)}"#, status: 201))
        }
        let client = makeClient(transport)

        let handle = try await client.tasks.runs.create(
            "t1", TaskRunCreate(text: "And next week?", kind: .steer, deliveryId: "d-1", runtimeId: "rt-9"))
        XCTAssertNil(handle.task)
        XCTAssertEqual(handle.run.id, "run-1")
        XCTAssertEqual(transport.last?.path, "/v1/tasks/t1/runs")
        XCTAssertEqual(
            transport.last?.json,
            [
                "prompt": ["text": "And next week?"], "kind": "steer", "delivery_id": "d-1", "runtime_id": "rt-9",
            ])

        _ = try await client.tasks.runs.resume(
            "t1",
            TaskRunResume(resume: [
                .resolved("int-1", payload: ["approved": true]), .cancelled("int-2"),
            ]))
        XCTAssertEqual(
            transport.last?.json,
            [
                "resume": [
                    ["interruptId": "int-1", "status": "resolved", "payload": ["approved": true]],
                    ["interruptId": "int-2", "status": "cancelled"],
                ]
            ])

        let run = try await client.tasks.runs.get("t1", "current")
        XCTAssertEqual(run.taskId, "0192f0a0-0000-7000-8000-000000000001")
        XCTAssertEqual(transport.last?.path, "/v1/tasks/t1/runs/current")

        let cancelled = try await handle.cancel()
        XCTAssertEqual(cancelled.id, "run-1")
        XCTAssertEqual(transport.last?.path, "/v1/tasks/0192f0a0-0000-7000-8000-000000000001/runs/run-1/cancel")
        XCTAssertNil(transport.last?.request.body)

        _ = try await client.tasks.runs.cancel("t1", "run-1", options: .drain(within: 30))
        XCTAssertEqual(transport.last?.json, ["mode": "drain", "drain_within_seconds": 30])

        _ = try await client.tasks.runs.cancel("t1", "run-1", options: TaskCancelOptions())
        XCTAssertEqual(transport.last?.json, ["mode": "abort"])
    }

    func testStartReturnsHandleAndTextCollectsDeltas() async throws {
        let sse = """
            event: ag_ui
            id: 1
            data: {"type":"TEXT_MESSAGE_START","messageId":"m1","role":"assistant"}

            event: ag_ui
            id: 2
            data: {"type":"TEXT_MESSAGE_CONTENT","messageId":"m1","delta":"Hello, "}

            event: ag_ui
            id: 3
            data: {"type":"TEXT_MESSAGE_CHUNK","messageId":"m1","delta":"world"}

            event: ag_ui
            id: c-1
            data: {"type":"RUN_FINISHED","threadId":"t","runId":"run-1"}


            """
        let transport = MockTransport { request, _ in
            if request.method == "POST" {
                return .response(.json(#"{"task":\#(TasksTests.taskJSON),"run":\#(TasksTests.runJSON)}"#, status: 201))
            }
            return .stream(status: 200, headers: ["content-type": "text/event-stream"], chunks: [Data(sse.utf8)], error: nil)
        }
        let client = makeClient(transport)
        let handle = try await client.tasks.start(prompt: "Hi", TaskCreate(title: "Greeting"))
        XCTAssertEqual(handle.task?.status, .awaitingUser)
        XCTAssertEqual(transport.requests[0].json?["prompt"], "Hi")
        XCTAssertEqual(transport.requests[0].json?["title"], "Greeting")

        let text = try await handle.text()
        XCTAssertEqual(text, "Hello, world")
        XCTAssertEqual(transport.last?.path, "/v1/tasks/0192f0a0-0000-7000-8000-000000000001/runs/run-1/stream")
        XCTAssertEqual(transport.last?.request.headers["Accept"], "text/event-stream")
    }

    func testTextThrowsWhenTheRunFails() async throws {
        let sse = """
            event: ag_ui
            id: 1
            data: {"type":"TEXT_MESSAGE_CONTENT","messageId":"m1","delta":"Hel"}

            event: ag_ui
            id: 2
            data: {"type":"RUN_ERROR","message":"Sandbox failed to start","code":"sandbox_failed"}


            """
        let transport = MockTransport { request, _ in
            if request.method == "POST" {
                return .response(.json(#"{"task":\#(TasksTests.taskJSON),"run":\#(TasksTests.runJSON)}"#, status: 201))
            }
            return .stream(status: 200, headers: ["content-type": "text/event-stream"], chunks: [Data(sse.utf8)], error: nil)
        }
        let handle = try await makeClient(transport).tasks.start(prompt: "Hi")
        do {
            _ = try await handle.text()
            XCTFail("expected the run failure to surface")
        } catch let error as IntrospectionError {
            XCTAssertEqual(error.kind, .runFailed)
            XCTAssertEqual(error.message, "Sandbox failed to start")
            XCTAssertEqual(error.code, "sandbox_failed")
        }
    }
}
