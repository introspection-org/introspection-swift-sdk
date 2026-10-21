// docs: identity/sharing

import IntrospectionSDK

enum Sharing {
    static func share(runner: Runner, taskId: String, grantedMemberId: String) async throws {
        // #region docs:identity/sharing/share
        let task = try await runner.tasks.get(taskId)
        _ = try await runner.shares.create(
            ShareCreate(resourceType: .conversation, resourceId: task.conversationId, grantedMemberId: grantedMemberId)
        )
        // #endregion docs:identity/sharing/share
    }
}
