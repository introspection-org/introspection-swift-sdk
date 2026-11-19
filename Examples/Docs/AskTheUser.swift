// docs: patterns/ask-the-user

import IntrospectionSDK

enum AskTheUser {
    static func detectPause(handle: RunHandle) async throws -> [AGUI.Interrupt] {
        // #region docs:patterns/ask-the-user/detect-pause
        var interrupts: [AGUI.Interrupt] = []
        for try await event in handle.stream() {
            if case let .runFinished(finished) = event.payload, case let .interrupt(outcome) = finished.outcome {
                interrupts = outcome.interrupts
            }
        }
        // #endregion docs:patterns/ask-the-user/detect-pause
        return interrupts
    }

    static func resume(runner: Runner, taskId: String, interrupts: [AGUI.Interrupt]) async throws {
        // #region docs:patterns/ask-the-user/resume
        guard let interruptId = interrupts.first?.id else { return }
        _ = try await runner.tasks.runs.resume(
            taskId,
            TaskRunResume(resume: [.resolved(interruptId, payload: ["answer": "EU"])])
        )
        // #endregion docs:patterns/ask-the-user/resume
    }
}
