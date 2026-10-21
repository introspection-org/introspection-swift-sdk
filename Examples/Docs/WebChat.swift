// docs: patterns/web-chat

import Foundation
import IntrospectionSDK

enum WebChat {
    static func brokerRoute(user: SignedInUser) async throws -> Data {
        // #region docs:patterns/web-chat/broker-route
        // What the broker route returns to the browser, as JSON with `Cache-Control: no-store`.
        struct BrokerSession: Encodable {
            let token: String
            let runtimeId: String
            let dpUrl: String
        }

        // Create the client once per process: it re-mints its service-account token before expiry.
        let env = ProcessInfo.processInfo.environment
        let cp = try await IntrospectionClient.fromServiceAccount(
            clientId: env["INTROSPECTION_SERVICE_ACCOUNT_CLIENT_ID"]!,
            clientSecret: env["INTROSPECTION_SERVICE_ACCOUNT_CLIENT_SECRET"]!,
            project: env["INTROSPECTION_PROJECT"]!
        )

        // `user` comes from your session, after your auth and rate limit.
        let runtime = try await cp.runtimes.resolve("support-agent")
        let session = try await cp.runtimes.openRunner(runtime.id, RunRequest(identity: RunnerIdentity(userId: user.id)))
        return try JSONEncoder().encode(
            BrokerSession(token: session.sessionToken, runtimeId: runtime.id, dpUrl: session.deployment.endpoint))
        // #endregion docs:patterns/web-chat/broker-route
    }

    static func federatedBroker(idToken: String, runtimeId: String) async throws -> Data {
        // #region docs:patterns/web-chat/federated-broker
        // What the broker route returns to the browser, as JSON with `Cache-Control: no-store`.
        struct BrokerSession: Encodable {
            let token: String
            let runtimeId: String
            let dpUrl: String
        }

        let env = ProcessInfo.processInfo.environment
        let token = try await AuthAPI().tokenExchange(
            subjectToken: idToken,
            clientId: env["INTROSPECTION_FEDERATED_CLIENT_ID"]!,
            project: env["INTROSPECTION_PROJECT"]!
        )
        // An end-user token can't look up runtimes: `runtimeId` comes from your config.
        return try JSONEncoder().encode(BrokerSession(token: token.accessToken, runtimeId: runtimeId, dpUrl: token.dpUrl ?? ""))
        // #endregion docs:patterns/web-chat/federated-broker
    }
}
