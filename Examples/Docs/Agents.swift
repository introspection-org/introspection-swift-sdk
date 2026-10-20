// docs: identity/agents

import IntrospectionSDK

enum Agents {
    static func howAgentsAct(client: IntrospectionClient, user: SignedInUser) async throws -> Runner {
        // #region docs:identity/agents/how-agents-act
        let runner = try await client.runtimes("support-agent").run(identity: RunnerIdentity(userId: user.id))
        // #endregion docs:identity/agents/how-agents-act
        return runner
    }
}
