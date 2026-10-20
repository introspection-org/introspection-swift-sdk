// docs: patterns/ask-the-user

import IntrospectionSDK

enum AskTheUser {
    static func detectPause(handle: RunHandle) async throws -> [JSONValue] {
        // #region docs:patterns/ask-the-user/detect-pause
        var interrupts: [JSONValue] = []
        for try await event in handle.stream() where event.eventType == .runFinished {
            if let outcome = event.raw["outcome"], outcome["type"]?.stringValue == "interrupt" {
                interrupts = outcome["interrupts"]?.arrayValue ?? []
            }
        }
        // #endregion docs:patterns/ask-the-user/detect-pause
        return interrupts
    }

    static func resume(runner: Runner, taskId: String, interrupts: [JSONValue]) async throws {
        // #region docs:patterns/ask-the-user/resume
        guard let interruptId = interrupts.first?["id"]?.stringValue else { return }
        _ = try await runner.tasks.runs.resume(
            taskId,
            TaskRunResume(resume: [.resolved(interruptId, payload: ["answer": "EU"])])
        )
        // #endregion docs:patterns/ask-the-user/resume
    }
}
