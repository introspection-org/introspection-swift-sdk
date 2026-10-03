import Foundation
import XCTest

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

final class AutomationsTests: XCTestCase {
    func testDecodesServerAutomation() throws {
        let automation = try JSONCoding.decoder.decode(Automation.self, from: Data(automationJSON.utf8))
        XCTAssertEqual(automation.name, "Weekly digest")
        XCTAssertEqual(automation.triggerType, .cron)
        XCTAssertNil(automation.kind)
        XCTAssertEqual(automation.canManage, true)
        XCTAssertEqual(automation.ownerRole, "operator")
        XCTAssertEqual(automation.tags, ["digest"])
        XCTAssertEqual(automation.lastTriggeredAt, ISO8601.parse("2026-09-28T09:00:00Z"))
        XCTAssertNotNil(automation.nextTriggerAt)
        let metadata = try XCTUnwrap(automation.typedMetadata)
        XCTAssertEqual(metadata.cronSchedules, ["0 9 * * 1", "0 17 * * 5"])
        XCTAssertEqual(metadata.timezone, "Europe/London")
        XCTAssertEqual(metadata.repositories, [AutomationRepositoryRef(repo: "acme/app", ref: "main")])
        XCTAssertEqual(metadata.conditions?.map(\.type), [.hasNewTasksSinceLastRun, "brand_new_condition"])

        let minimal = try JSONCoding.decoder.decode(
            Automation.self, from: Data(#"{"id":"a","name":"n","trigger_type":"manual","kind":"observation_clustering"}"#.utf8))
        XCTAssertEqual(minimal.kind, .observationClustering)
        XCTAssertNil(minimal.metadata)
    }

    func testListEncodesFiltersAndPaginates() async throws {
        let transport = MockTransport { request, index in
            index == 0
                ? .response(.json(#"{"records":[\#(automationJSON)],"count":1,"total_count":2,"next":"cur-2"}"#))
                : .response(.json(#"{"records":[{"id":"b","name":"second","trigger_type":"manual"}],"count":1,"next":null}"#))
        }
        let all = try await makeClient(transport).automations
            .list(AutomationListParams(limit: 1, kind: .observationSynthesis, enabled: true))
            .collect()
        XCTAssertEqual(all.map(\.name), ["Weekly digest", "second"])
        XCTAssertEqual(transport.requests.count, 2)
        let first = transport.requests[0]
        XCTAssertEqual(first.path, "/v1/automations")
        XCTAssertEqual(first.query, ["limit": ["1"], "kind": ["observation_synthesis"], "enabled": ["true"]])
        XCTAssertEqual(transport.requests[1].query["next"], ["cur-2"])
    }

    func testCreateEncodesOnlySetFields() async throws {
        let transport = MockTransport(status: 201, json: automationJSON)
        let metadata = try AutomationMetadata(cronSchedules: ["0 9 * * 1"], timezone: "UTC").jsonObject()
        let created = try await makeClient(transport).automations.create(
            AutomationCreate(
                name: "Weekly digest", triggerType: .cron, cronSchedule: "0 9 * * 1",
                prompt: "Summarize my week", metadata: metadata
            ))
        XCTAssertEqual(created.name, "Weekly digest")
        XCTAssertEqual(transport.last?.request.method, "POST")
        XCTAssertEqual(transport.last?.path, "/v1/automations")
        XCTAssertEqual(
            transport.last?.json,
            [
                "name": "Weekly digest", "trigger_type": "cron", "cron_schedule": "0 9 * * 1",
                "prompt": "Summarize my week", "metadata": ["cron_schedules": ["0 9 * * 1"], "timezone": "UTC"],
            ])

        _ = try await makeClient(transport).automations.create(
            AutomationCreate(
                name: "Nudge", triggerType: .manual, prompt: "Check in", enabled: false
            ))
        XCTAssertEqual(
            transport.last?.json,
            ["name": "Nudge", "trigger_type": "manual", "prompt": "Check in", "enabled": false])
    }

    func testGetUpdateDeleteAndTrigger() async throws {
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
        XCTAssertEqual(transport.last?.request.url.absoluteString, "https://dp.test/v1/automations/a%2F1")

        _ = try await api.update("a/1", AutomationUpdate(enabled: false))
        XCTAssertEqual(transport.last?.request.method, "PATCH")
        XCTAssertEqual(transport.last?.json, ["enabled": false])

        try await api.delete("a/1")
        XCTAssertEqual(transport.last?.request.method, "DELETE")

        let triggered = try await api.trigger("a/1")
        XCTAssertEqual(transport.last?.request.url.absoluteString, "https://dp.test/v1/automations/a%2F1/trigger")
        XCTAssertEqual(triggered.status, .triggered)
        XCTAssertEqual(triggered.taskId, "t-9")
        XCTAssertNil(triggered.reason)
    }
}
