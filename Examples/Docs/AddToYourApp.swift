// docs: patterns/add-to-your-app

import Foundation
import IntrospectionSDK

#if Telemetry
import IntrospectionTelemetry
#endif

enum AddToYourApp {
    static func openRunner(user: SignedInUser) async throws -> Runner {
        // #region docs:patterns/add-to-your-app/open-runner
        let env = ProcessInfo.processInfo.environment
        let client = try await IntrospectionClient.fromServiceAccount(
            clientId: env["INTROSPECTION_SERVICE_ACCOUNT_CLIENT_ID"]!,
            clientSecret: env["INTROSPECTION_SERVICE_ACCOUNT_CLIENT_SECRET"]!,
            project: env["INTROSPECTION_PROJECT"]!
        )

        let runner = try await client.runtimes("refund-agent").run(identity: RunnerIdentity(userId: user.id))
        // #endregion docs:patterns/add-to-your-app/open-runner
        return runner
    }

    static func startTask(runner: Runner, user: SignedInUser) async throws {
        // #region docs:patterns/add-to-your-app/start-task
        // Your app's code: remember which task belongs to the order, and forward events to the browser.
        func saveAgentBinding(orderId: String, taskId: String, userId: String) async throws {}
        func sendEventToBrowser(_ event: AGUIEvent) async throws {}

        let handle = try await runner.tasks.start(
            prompt: "Review order 1842 against the refund policy and draft the next response.",
            TaskCreate(metadata: ["order_id": "1842"])
        )
        try await saveAgentBinding(orderId: "1842", taskId: handle.run.taskId, userId: user.id)

        for try await event in handle.stream() {
            try await sendEventToBrowser(event)
        }
        // #endregion docs:patterns/add-to-your-app/start-task
    }

    static func reconnect(runner: Runner, binding: AgentBinding) async throws {
        // #region docs:patterns/add-to-your-app/reconnect
        // Your app's code: forward one event to the browser, for example over server-sent events.
        func sendEventToBrowser(_ event: AGUIEvent) async throws {}

        let task = try await runner.tasks.get(binding.taskId)
        let runId = task.metadata?["active_run_id"]?.stringValue ?? task.metadata?["latest_run_id"]?.stringValue
        guard let runId else { return }

        for try await event in runner.tasks.runs.stream(binding.taskId, runId) {
            try await sendEventToBrowser(event)
        }
        // #endregion docs:patterns/add-to-your-app/reconnect
    }

    #if Telemetry
    // IntrospectionLogs needs the `Telemetry` package trait.
    static func feedback(runner: Runner, binding: AgentBinding) async throws {
        // #region docs:patterns/add-to-your-app/feedback
        // An API key: this client keeps one token for life.
        let outcomes = try IntrospectionLogs(
            token: ProcessInfo.processInfo.environment["INTROSPECTION_API_KEY"], serviceName: "refund-app"
        )

        let task = try await runner.tasks.get(binding.taskId)
        outcomes.feedback(
            "thumbs_down",
            comments: "Missed the final-sale rule",
            conversationId: task.conversationId,
            previousResponseId: task.metadata?["last_response"]?["response_id"]?.stringValue
        )
        await outcomes.flush()
        // #endregion docs:patterns/add-to-your-app/feedback
    }
    #endif
}
