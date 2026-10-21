// docs: patterns/trigger

import Foundation
import IntrospectionSDK

enum Trigger {
    static func taskPerEvent() async throws -> String {
        // #region docs:patterns/trigger/task-per-event
        let client = IntrospectionClient(
            controlPlaneURL: URL(string: "https://api.introspection.dev")!,
            credentials: BearerToken(ProcessInfo.processInfo.environment["INTROSPECTION_TOKEN"]!)
        )

        // Call from your webhook route, then answer 202 with the task id at once.
        func handleEvent(id: String, text: String) async throws -> String {
            let runner = try await client.runtimes("triage-agent").run()
            let handle = try await runner.tasks.start(
                prompt: "New event \(id):\n\n\(text)",
                TaskCreate(conversationMetadata: ["event_id": id])
            )
            return handle.run.taskId
        }
        // #endregion docs:patterns/trigger/task-per-event
        return try await handleEvent(id: "evt_1", text: "Example event")
    }

    static func batch(client: IntrospectionClient, tickets: [String]) async throws {
        // #region docs:patterns/trigger/batch
        let runner = try await client.runtimes("triage-agent").run()
        for start in stride(from: 0, to: tickets.count, by: 5) {
            let wave = tickets[start..<min(start + 5, tickets.count)]
            try await withThrowingTaskGroup(of: Void.self) { group in
                for ticket in wave {
                    group.addTask {
                        let handle = try await runner.tasks.start(
                            prompt: "Triage ticket \(ticket)", TaskCreate(tags: ["batch:2026-10-15"])
                        )
                        _ = try await handle.text()  // waits for the run to settle
                    }
                }
                try await group.waitForAll()
            }
        }
        // #endregion docs:patterns/trigger/batch
    }
}
