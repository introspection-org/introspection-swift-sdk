// docs: patterns/multi-tenant

import IntrospectionSDK

enum MultiTenant {
    static func endUser(client: IntrospectionClient, user: SignedInUser) async throws -> Runner {
        // #region docs:patterns/multi-tenant/end-user
        let runner = try await client.runtimes("support-agent").run(
            identity: RunnerIdentity(userId: user.id, tags: ["customer:acme"])
        )
        // #endregion docs:patterns/multi-tenant/end-user
        return runner
    }

    static func perTaskConfig(runner: Runner, prompt: String) async throws -> RunHandle {
        // #region docs:patterns/multi-tenant/per-task-config
        let handle = try await runner.tasks.start(
            prompt: prompt,
            TaskCreate(
                metadata: ["customer": "acme", "playbook": "acme-v3", "region": "eu"],
                tags: ["customer:acme"]
            )
        )
        // #endregion docs:patterns/multi-tenant/per-task-config
        return handle
    }
}
