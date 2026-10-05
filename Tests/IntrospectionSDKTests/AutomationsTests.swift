import Foundation
import Testing

@testable import IntrospectionSDK

private let automationJSON = #"""
    {
      "id": "0199a1b2-0000-7000-8000-000000000001",
      "org_id": "0199a1b2-0000-7000-8000-0000000000aa",
      "project_id": "0199a1b2-0000-7000-8000-0000000000bb",
      "name": "Weekly digest",
      "description": "Summarize the week",
      "enabled": true,
      "agent_member_id": null,
      "runtime_group_id": "0199a1b2-0000-7000-8000-0000000000dd",
      "task_id": "0199a1b2-0000-7000-8000-0000000000ee",
      "created_by_member_id": "0199a1b2-0000-7000-8000-0000000000cc",
      "execution_blocked_reason": null,
      "can_manage": true,
      "tags": ["digest"],
      "trigger_type": "cron",
      "cron_schedule": "0 9 * * 1",
      "kind": null,
      "prompt": "Summarize my week",
      "metadata": {
        "cron_schedules": ["0 9 * * 1", "0 17 * * 5"],
        "timezone": "Europe/London",
        "repositories": [{"repo": "acme/app", "ref": "main"}],
        "conditions": [{"type": "has_new_tasks_since_last_run"}, {"type": "brand_new_condition"}]
      },
      "last_triggered_at": "2026-09-28T09:00:00Z",
      "next_trigger_at": "2026-10-05T09:00:00.123456Z",
      "created_at": "2026-09-01T10:00:00Z",
      "updated_at": "2026-09-28T09:00:01Z",
      "owner_role": "operator"
    }
    """#

@Suite struct AutomationsTests {
    @Test func decodesServerAutomation() throws {
        let automation = try JSONCoding.decoder.decode(Automation.self, from: Data(automationJSON.utf8))
        #expect(automation.name == "Weekly digest")
        #expect(automation.triggerType == .cron)
        #expect(automation.kind == nil)
        #expect(automation.canManage == true)
        #expect(automation.runtimeGroupId == "0199a1b2-0000-7000-8000-0000000000dd")
        #expect(automation.taskId == "0199a1b2-0000-7000-8000-0000000000ee")
        #expect(automation.createdByMemberId == "0199a1b2-0000-7000-8000-0000000000cc")
        #expect(automation.ownerRole == "operator")
        #expect(automation.tags == ["digest"])
        #expect(automation.lastTriggeredAt == ISO8601.parse("2026-09-28T09:00:00Z"))
        #expect(automation.nextTriggerAt == ISO8601.parse("2026-10-05T09:00:00.123Z"))
        let metadata = try #require(automation.typedMetadata)
        #expect(metadata.cronSchedules == ["0 9 * * 1", "0 17 * * 5"])
        #expect(metadata.timezone == "Europe/London")
        #expect(metadata.repositories == [AutomationRepositoryRef(repo: "acme/app", ref: "main")])
        #expect(metadata.conditions?.map(\.type) == [.hasNewTasksSinceLastRun, "brand_new_condition"])

        let minimal = try JSONCoding.decoder.decode(
            Automation.self, from: Data(#"{"id":"a","name":"n","trigger_type":"manual","kind":"observation_clustering"}"#.utf8))
        #expect(minimal.kind == .observationClustering)
        #expect(minimal.metadata == nil)
        #expect(minimal.runtimeGroupId == nil)
        #expect(minimal.taskId == nil)
        #expect(minimal.nextTriggerAt == nil)
    }

    @Test func listEncodesFiltersAndPaginates() async throws {
        let transport = MockTransport { request, index in
            index == 0
                ? .response(.json(#"{"records":[\#(automationJSON)],"count":1,"total_count":2,"next":"cur-2"}"#))
                : .response(.json(#"{"records":[{"id":"b","name":"second","trigger_type":"manual"}],"count":1,"next":null}"#))
        }
        let all = try await makeClient(transport).automations
            .list(AutomationListParams(limit: 1, kind: .observationSynthesis, enabled: true, scheduled: false))
            .collect()
        #expect(all.map(\.name) == ["Weekly digest", "second"])
        #expect(transport.requests.count == 2)
        let first = transport.requests[0]
        #expect(first.path == "/v1/automations")
        #expect(first.query == ["limit": ["1"], "kind": ["observation_synthesis"], "enabled": ["true"], "scheduled": ["false"]])
        #expect(transport.requests[1].query["next"] == ["cur-2"])
    }

    @Test func listEncodesTaskId() {
        #expect(AutomationListParams(taskId: "task-1").query.items == [URLQueryItem(name: "task_id", value: "task-1")])
        #expect(AutomationListParams(kind: .projectCheckIn, taskId: "task-1").query.items.map(\.name) == ["kind", "task_id"])
    }

    @Test func listKeepsTaskIdOnEveryPage() async throws {
        let transport = MockTransport { _, index in
            index == 0
                ? .response(.json(#"{"records":[\#(automationJSON)],"count":1,"next":"cur-2"}"#))
                : .response(.json(#"{"records":[{"id":"b","name":"second","trigger_type":"manual"}],"count":1,"next":null}"#))
        }
        let all = try await makeClient(transport).automations.list(AutomationListParams(taskId: "task-1")).collect()
        #expect(all.map(\.name) == ["Weekly digest", "second"])
        #expect(transport.requests.count == 2)
        #expect(transport.requests[0].query == ["task_id": ["task-1"]])
        #expect(transport.requests[1].query == ["task_id": ["task-1"], "next": ["cur-2"]])
    }

    @Test func listDecodesTheCheckInAndUnknownKinds() async throws {
        let transport = MockTransport(
            json: #"""
                {"records":[
                  {"id":"a","name":"Check-in","trigger_type":"cron","kind":"project_check_in","prompt":"p","owner_role":"operator"},
                  {"id":"b","name":"Later","trigger_type":"cron","kind":"not_yet_invented"}
                ],"count":2,"next":null}
                """#)
        let all = try await makeClient(transport).automations.list().collect()
        #expect(all.compactMap(\.kind) == [.projectCheckIn, "not_yet_invented"])
        #expect(all[0].ownerRole == "operator")
    }

    @Test func createEncodesOnlySetFields() async throws {
        let transport = MockTransport(status: 201, json: automationJSON)
        let metadata = try AutomationMetadata(cronSchedules: ["0 9 * * 1"], timezone: "UTC").jsonObject()
        let created = try await makeClient(transport).automations.create(
            AutomationCreate(
                name: "Weekly digest", triggerType: .cron, cronSchedule: "0 9 * * 1",
                prompt: "Summarize my week", metadata: metadata
            ))
        #expect(created.name == "Weekly digest")
        #expect(transport.last?.request.method == "POST")
        #expect(transport.last?.path == "/v1/automations")
        #expect(
            transport.last?.json == [
                "name": "Weekly digest", "trigger_type": "cron", "cron_schedule": "0 9 * * 1",
                "prompt": "Summarize my week", "metadata": ["cron_schedules": ["0 9 * * 1"], "timezone": "UTC"],
            ])

        _ = try await makeClient(transport).automations.create(
            AutomationCreate(
                name: "Nudge", triggerType: .manual, prompt: "Check in", enabled: false
            ))
        #expect(transport.last?.json == ["name": "Nudge", "trigger_type": "manual", "prompt": "Check in", "enabled": false])
    }

    @Test func createsAOneOffReminderIntoAnExistingTask() async throws {
        let transport = MockTransport(status: 201, json: automationJSON)
        let slot = try #require(ISO8601.parse("2026-10-10T09:00:00Z"))
        _ = try await makeClient(transport).automations.create(
            AutomationCreate(
                name: "Friday check-in", triggerType: .manual, prompt: "How did the week go?", runtimeGroupId: "rg-1",
                taskId: "task-1", nextTriggerAt: slot
            ))
        #expect(
            transport.last?.json == [
                "name": "Friday check-in", "trigger_type": "manual", "prompt": "How did the week go?", "runtime_group_id": "rg-1",
                "task_id": "task-1", "next_trigger_at": "2026-10-10T09:00:00.000Z",
            ])
    }

    @Test func getUpdateDeleteAndTrigger() async throws {
        let transport = MockTransport { request, _ in
            switch (request.method, request.url.path) {
            case ("DELETE", _): return .response(HTTPResponse(status: 204, headers: [:], body: Data()))
            case ("POST", _):
                return .response(.json(#"{"status":"triggered","automation_id":"a/1","task_id":"t-9","reason":null}"#, status: 202))
            default: return .response(.json(automationJSON))
            }
        }
        let api = makeClient(transport).automations
        _ = try await api.get("a/1")
        #expect(transport.last?.request.url.absoluteString == "https://dp.test/v1/automations/a%2F1")

        _ = try await api.update("a/1", AutomationUpdate(enabled: false))
        #expect(transport.last?.request.method == "PATCH")
        #expect(transport.last?.json == ["enabled": false])

        let slot = try #require(ISO8601.parse("2026-10-12T08:30:00Z"))
        _ = try await api.update("a/1", AutomationUpdate(nextTriggerAt: slot))
        #expect(transport.last?.json == ["next_trigger_at": "2026-10-12T08:30:00.000Z"])

        _ = try await api.update("a/1", AutomationUpdate(runtimeGroupId: "rg-2", taskId: "task-2"))
        #expect(transport.last?.json == ["runtime_group_id": "rg-2", "task_id": "task-2"])

        try await api.delete("a/1")
        #expect(transport.last?.request.method == "DELETE")

        let triggered = try await api.trigger("a/1")
        #expect(transport.last?.request.url.absoluteString == "https://dp.test/v1/automations/a%2F1/trigger")
        #expect(triggered.status == .triggered)
        #expect(triggered.taskId == "t-9")
        #expect(triggered.reason == nil)
        #expect(triggered.automationId == "a/1")
    }

    @Test func handTriggerSkipCarriesItsReason() async throws {
        let transport = MockTransport(
            status: 202, json: #"{"status":"skipped","automation_id":"a1","task_id":null,"reason":"Target task is archived"}"#)
        let skipped = try await makeClient(transport).automations.trigger("a1")
        #expect(skipped.status == .skipped)
        #expect(skipped.taskId == nil)
        #expect(skipped.reason == "Target task is archived")
    }

    @Test func readsTriggerAndSkipEvents() async throws {
        let triggered = #"""
            {"id":"0199a1b2-0000-5000-8000-000000000001","timestamp":"2026-10-05T09:00:02Z",
             "event_name":"introspection.automation.triggered","conversation_id":"conv-1",
             "runtime_group_id":"rg-1","runtime_id":"rt-1",
             "payload":{"automation_id":"a1","automation_name":"Weekly digest","prompt":"Summarize my week",
                        "trigger_type":"cron","slot":"2026-10-05T09:00:00Z","task_id":"t1","posted":true,
                        "member_id":"m1","runtime_group_id":"rg-1","triggered_by_member_id":null}}
            """#
        let skipped = #"""
            {"id":"0199a1b2-0000-5000-8000-000000000002","timestamp":"2026-10-06T09:00:00Z",
             "event_name":"introspection.automation.skipped","runtime_group_id":"rg-1",
             "payload":{"automation_id":"a1","trigger_type":"manual","slot":"2026-10-06T09:00:00Z","task_id":"t1",
                        "reason":"target_busy"}}
            """#
        let transport = MockTransport(json: #"{"records":[\#(triggered),\#(skipped)],"count":2,"next":null}"#)
        let events = try await makeClient(transport).events
            .list(EventListParams(eventName: .automationTriggered, automationId: "a1", taskId: "t1"))
            .collect()
        #expect(transport.last?.query["event_name"] == ["introspection.automation.triggered"])
        #expect(transport.last?.query["automation_id"] == ["a1"])
        #expect(transport.last?.query["task_id"] == ["t1"])

        let run = try #require(events[0].automationTriggered)
        #expect(run.automationName == "Weekly digest")
        #expect(run.triggerType == .cron)
        #expect(run.slot == ISO8601.parse("2026-10-05T09:00:00Z"))
        #expect(run.posted == true)
        #expect(run.taskId == "t1")
        #expect(run.memberId == "m1")
        #expect(run.triggeredByMemberId == nil)
        #expect(events[0].automationSkipped == nil)

        let skip = try #require(events[1].automationSkipped)
        #expect(skip.reason == .targetBusy)
        #expect(skip.triggerType == .manual)
        #expect(skip.taskId == "t1")
        #expect(events[1].automationTriggered == nil)
    }
}
