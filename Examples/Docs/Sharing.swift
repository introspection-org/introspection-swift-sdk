// docs: identity/sharing

import IntrospectionSDK

enum Sharing {
    static func share(runner: Runner, taskId: String, grantedMemberId: String) async throws {
        // #region docs:identity/sharing/share
        _ = try await runner.shares.create(
            ShareCreate(resourceType: .conversation, resourceId: taskId, grantedMemberId: grantedMemberId)
        )
        // #endregion docs:identity/sharing/share
    }
}
