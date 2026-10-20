// docs: patterns/approve-outside

import IntrospectionSDK

enum ApproveOutside {
    static func reportOutcome(runner: Runner, taskId: String) async throws {
        // #region docs:patterns/approve-outside/report-outcome
        _ = try await runner.tasks.runs.create(
            taskId,
            TaskRunCreate(
                text: #"<user_action kind="draft" action="sent" id="d-17" by="maria">Sent text</user_action>"#,
                kind: .steer
            )
        )
        // #endregion docs:patterns/approve-outside/report-outcome
    }
}
