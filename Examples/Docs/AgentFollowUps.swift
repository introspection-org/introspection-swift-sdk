// docs: patterns/agent-follow-ups

import IntrospectionSDK

enum AgentFollowUps {
    static func timeZone(runner: Runner, prompt: String) async throws {
        // #region docs:patterns/agent-follow-ups/time-zone
        _ = try await runner.tasks.start(prompt: prompt, TaskCreate(metadata: ["timezone": "Europe/London"]))
        // #endregion docs:patterns/agent-follow-ups/time-zone
    }
}
