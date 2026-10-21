// docs: reference/swift

import Foundation
import IntrospectionSDK

enum SwiftReference {
    static func runTask(apiKey: String) async throws {
        // #region docs:reference/swift/run-task
        let client = IntrospectionClient(
            controlPlaneURL: URL(string: "https://api.introspection.dev")!,
            credentials: BearerToken(apiKey)
        )
        let runner = try await client.runtimes("support-agent").run(identity: RunnerIdentity(userId: "user_123"))

        let answer = try await runner.tasks.start(prompt: "Summarize the open tickets.").text()
        print(answer)

        let handle = try await runner.tasks.start(prompt: "Say hello.")
        for try await event in handle.stream() where event.eventType == .textMessageContent {
            print(event.delta ?? "", terminator: "")
        }
        // #endregion docs:reference/swift/run-task
    }

    static func continueControl(runner: Runner, handle: RunHandle, interruptId: String) async throws {
        // #region docs:reference/swift/continue-control
        let next = try await runner.tasks.runs.create(handle.run.taskId, text: "Now draft the reply.")
        print(try await next.text())

        _ = try await runner.tasks.runs.resume(
            handle.run.taskId,
            TaskRunResume(resume: [
                TaskResumeEntry(interruptId: interruptId, status: "resolved", payload: ["approved": true])
            ]))

        _ = try await handle.cancel()  // abort the turn, keep the sandbox warm
        _ = try await handle.cancel(options: .drain(within: 60))
        // #endregion docs:reference/swift/continue-control
    }

    static func files(runner: Runner, notes: Data) async throws {
        // #region docs:reference/swift/files
        let uploaded = try await runner.files.upload(FileUpload(data: notes, filename: "notes.txt"))
        _ = try await runner.tasks.start(
            prompt: "Summarize the attached notes.",
            TaskCreate(files: [TaskFileRef(id: uploaded.id)])
        )
        // #endregion docs:reference/swift/files
    }

    static func conversationsEventsMetrics(runner: Runner) async throws {
        // #region docs:reference/swift/conversations-events-metrics
        for try await conversation in try runner.conversations.list(ConversationListParams(metadata: ["flow": "support"])) {
            print(conversation.id)
        }

        let result = try await runner.metrics.query(
            MetricQueryRequest(
                view: "conversations",
                metrics: [MetricSpec("sum", measure: "total_cost_usd")],
                from: Date().addingTimeInterval(-7 * 86_400),
                to: Date()
            ))
        // #endregion docs:reference/swift/conversations-events-metrics
        _ = result
    }

    #if canImport(Security)
    static func signIn(email: String, code: String) async throws -> IntrospectionClient {
        // #region docs:reference/swift/sign-in
        let auth = AuthClient(
            configuration: .init(
                controlPlaneURL: URL(string: "https://api.introspection.dev")!,
                clientID: "intro_app_...",
                project: "my-project",
                method: .emailCode,
                storage: KeychainSessionStorage()
            ))
        try await auth.signInWithOTP(email: email)
        _ = try await auth.verifyOTP(email: email, token: code)
        let client = try await auth.client()
        // #endregion docs:reference/swift/sign-in
        return client
    }
    #endif
}
