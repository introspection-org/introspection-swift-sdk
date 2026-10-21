// docs: patterns/per-user-tools

import IntrospectionSDK

enum PerUserTools {
    static func mintLink(client: IntrospectionClient) async throws -> String {
        // #region docs:patterns/per-user-tools/mint-link
        let link = try await client.connectors.authorize(
            "<connector-id>",
            ConnectorAuthorizeParams(
                app: "<app>",
                identity: RunnerIdentity(userId: "user-4821"),
                runtime: "support-agent",
                expiresIn: 3600
            )
        )
        // Send link.authorizeUrl to the user.
        // #endregion docs:patterns/per-user-tools/mint-link
        return link.authorizeUrl
    }

    static func connectButton(client: IntrospectionClient) async throws -> String {
        // #region docs:patterns/per-user-tools/connect-button
        let mine = try await client.connections.list(app: "<app>").collect()
        let page = try await client.connections.create(app: "<app>", runtime: "support-agent")
        // #endregion docs:patterns/per-user-tools/connect-button
        _ = mine
        return page.authorizeUrl
    }
}
