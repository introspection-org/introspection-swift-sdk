import Foundation
import Testing

@testable import IntrospectionSDK

@Suite struct TasksTests {
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

    @Test func decodesRealisticTask() throws {
        let task = try JSONCoding.decoder.decode(IntrospectionTask.self, from: Data(Self.taskJSON.utf8))
        #expect(task.id == "0192f0a0-0000-7000-8000-000000000001")
        #expect(task.status == .awaitingUser)
        #expect(task.kind == .eval)
        #expect(task.displayIndex == 42)
        #expect(task.runtimeId == "0192f0a0-0000-7000-8000-0000000000dd")
        #expect(task.automationId == nil)
        #expect(task.completedAt == nil)
        #expect(task.createdAt != nil)
        #expect(task.conversationMetadata == ["flow": "checkout"])
        #expect(task.tags == ["customer:acme"])
        #expect(task.agent?.sandboxStatus == "Running")
        #expect(task.agent?.sessionId == "sess-1")
        #expect(task.conversationId == "conv-1")
        #expect(task.metadata?["agent_name"]?.stringValue == "researcher")
        #expect(!task.status.isTerminal)
    }

    @Test func minimalTaskAndUnknownStatusDecode() throws {
        let task = try JSONCoding.decoder.decode(IntrospectionTask.self, from: Data(#"{"id":"t1","status":"hibernating","extra":1}"#.utf8))
        #expect(task.status.rawValue == "hibernating")
        #expect(task.kind == .agent)
        #expect(!task.isArchived)
        #expect(task.tags == [])
        #expect(task.conversationId == "t1")
    }

    @Test func listEncodesEveryFilterAndPages() async throws {
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
        #expect(tasks.map(\.id) == ["0192f0a0-0000-7000-8000-000000000001", "t2"])
        #expect(tasks.last?.status == .completed)

        let first = try #require(transport.requests.first)
        #expect(first.request.method == "GET")
        #expect(first.path == "/v1/tasks")
        let q = first.query
        #expect(q["next"] == ["cursor-1"])
        #expect(q["limit"] == ["1"])
        #expect(q["include_total"] == ["true"])
        #expect(q["statuses"] == ["running", "idle"])
        #expect(q["runtime_id"] == ["rt-1"])
        #expect(q["runtime_ids"] == ["rt-2", "rt-3"])
        #expect(q["updated_after"]?.count == 1)
        #expect(q["require_automation_id"] == ["false"])
        #expect(q["automation_id"] == ["auto-1"])
        #expect(q["member_id"] == ["m-1"])
        #expect(q["conversation_id"] == ["conv-1"])
        #expect(q["conversation_ids"] == ["c-a", "c-b"])
        #expect(q["tag"] == ["customer:acme"])
        #expect(transport.requests[1].query["next"] == ["cursor-2"])
        #expect(transport.requests[1].query["tag"] == ["customer:acme"])
    }

    @Test func createEncodesSnakeCaseBodyAndOmitsNils() async throws {
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
        #expect(response.run.id == "run-1")
        #expect(response.run.status == .queued)
        #expect(response.task.title == "Summarize my week")

        let last = try #require(transport.last)
        #expect(last.request.method == "POST")
        #expect(last.path == "/v1/tasks")
        let json = try #require(last.json)
        #expect(json["prompt"] == "Summarize my week")
        #expect(json["kind"] == "eval")
        #expect(json["agent_name"] == "researcher")
        #expect(json["runtime_id"] == "rt-1")
        #expect(json["bindings_required"] == false)
        #expect(json["repositories"] == [["repo": "acme/api", "ref": "main", "depth": 0]])
        #expect(json["idle_timeout_seconds"] == 0)
        #expect(json["metadata"] == ["source": "ios"])
        #expect(json["conversation_metadata"] == ["flow": "checkout"])
        #expect(json["tags"] == ["customer:acme"])
        #expect(json["files"] == [["id": "f-1", "name": "specs/a.md", "size_bytes": 12]])
        #expect(json["commands"] == true)
        #expect(json["compose"]?["services"]?["db"]?["image"] == "postgres:17")
        #expect(json["fork_share_id"] == "share-1")
        #expect(json["title"] == nil)
        #expect(json["recipe_patch"] == nil)
        #expect(json["collect_sandbox_logs"] == nil)
    }

    @Test func getWithIncludeUpdateDeleteArchive() async throws {
        let transport = MockTransport { request, _ in
            switch request.method {
            case "GET", "PATCH": return .response(.json(TasksTests.taskJSON))
            default: return .response(HTTPResponse(status: 204, headers: [:], body: Data()))
            }
        }
        let client = makeClient(transport)
        let id = "task/1"

        _ = try await client.tasks.get(id)
        #expect(transport.last?.request.url.absoluteString == "https://dp.test/v1/tasks/task%2F1")
        #expect(transport.last?.query["include"] == nil)

        let task = try await client.tasks.get(id, include: [.agent])
        #expect(task.agent?.sessionId == "sess-1")
        #expect(transport.last?.query["include"] == ["agent"])

        _ = try await client.tasks.update(id, TaskUpdate(title: "Renamed", tags: []))
        #expect(transport.last?.request.method == "PATCH")
        #expect(transport.last?.json == ["title": "Renamed", "tags": []])

        try await client.tasks.delete(id)
        #expect(transport.last?.request.method == "DELETE")
        #expect(transport.last?.request.url.absoluteString == "https://dp.test/v1/tasks/task%2F1")

        try await client.tasks.archive(id)
        #expect(transport.last?.request.method == "POST")
        #expect(transport.last?.request.url.absoluteString == "https://dp.test/v1/tasks/task%2F1/archive")

        try await client.tasks.unarchive(id)
        #expect(transport.last?.request.url.absoluteString == "https://dp.test/v1/tasks/task%2F1/unarchive")
    }

    @Test func runsCreateResumeGetCancel() async throws {
        let transport = MockTransport { request, _ in
            if request.url.path.hasSuffix("/cancel") { return .response(.json(#"{"id":"run-1"}"#)) }
            if request.method == "GET" { return .response(.json(TasksTests.runJSON)) }
            return .response(.json(#"{"run":\#(TasksTests.runJSON)}"#, status: 201))
        }
        let client = makeClient(transport)

        let handle = try await client.tasks.runs.create(
            "t1", TaskRunCreate(text: "And next week?", kind: .steer, deliveryId: "d-1", runtimeId: "rt-9"))
        #expect(handle.task == nil)
        #expect(handle.run.id == "run-1")
        #expect(transport.last?.path == "/v1/tasks/t1/runs")
        #expect(
            transport.last?.json == [
                "prompt": ["text": "And next week?"], "kind": "steer", "delivery_id": "d-1", "runtime_id": "rt-9",
            ])

        _ = try await client.tasks.runs.resume(
            "t1",
            TaskRunResume(resume: [
                .resolved("int-1", payload: ["approved": true]), .cancelled("int-2"),
            ]))
        #expect(
            transport.last?.json == [
                "resume": [
                    ["interruptId": "int-1", "status": "resolved", "payload": ["approved": true]],
                    ["interruptId": "int-2", "status": "cancelled"],
                ]
            ])

        let run = try await client.tasks.runs.get("t1", "current")
        #expect(run.taskId == "0192f0a0-0000-7000-8000-000000000001")
        #expect(transport.last?.path == "/v1/tasks/t1/runs/current")

        let cancelled = try await handle.cancel()
        #expect(cancelled.id == "run-1")
        #expect(transport.last?.path == "/v1/tasks/0192f0a0-0000-7000-8000-000000000001/runs/run-1/cancel")
        #expect(transport.last?.request.body == nil)

        _ = try await client.tasks.runs.cancel("t1", "run-1", options: .drain(within: 30))
        #expect(transport.last?.json == ["mode": "drain", "drain_within_seconds": 30])

        _ = try await client.tasks.runs.cancel("t1", "run-1", options: TaskCancelOptions())
        #expect(transport.last?.json == ["mode": "abort"])
    }

    @Test func startReturnsHandleAndTextCollectsDeltas() async throws {
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
        #expect(handle.task?.status == .awaitingUser)
        #expect(transport.requests[0].json?["prompt"] == "Hi")
        #expect(transport.requests[0].json?["title"] == "Greeting")

        let text = try await handle.text()
        #expect(text == "Hello, world")
        #expect(transport.last?.path == "/v1/tasks/0192f0a0-0000-7000-8000-000000000001/runs/run-1/stream")
        #expect(transport.last?.request.headers["Accept"] == "text/event-stream")
    }

    @Test func textThrowsWhenTheRunFails() async throws {
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
        let error = try await #require(throws: IntrospectionError.self) { try await handle.text() }
        #expect(error.kind == .runFailed)
        #expect(error.message == "Sandbox failed to start")
        #expect(error.code == "sandbox_failed")
    }

    @Test func createAndRunByRuntimeGroup() async throws {
        let transport = MockTransport { request, _ in
            request.url.path == "/v1/tasks"
                ? .response(.json(#"{"task":\#(TasksTests.taskJSON),"run":\#(TasksTests.runJSON)}"#, status: 201))
                : .response(.json(#"{"run":\#(TasksTests.runJSON)}"#, status: 201))
        }
        let client = makeClient(transport)

        _ = try await client.tasks.start(prompt: "Hello", TaskCreate(runtimeGroup: "ark"))
        let created = try #require(transport.last?.json)
        #expect(created == ["prompt": "Hello", "runtime_group": "ark"])
        #expect(created["runtime_id"] == nil)

        _ = try await client.tasks.runs.create("t1", TaskRunCreate(text: "Next", runtimeGroup: "ark"))
        #expect(transport.last?.path == "/v1/tasks/t1/runs")
        #expect(transport.last?.json == ["prompt": ["text": "Next"], "runtime_group": "ark"])
    }
}
