// docs: reference/authentication

import Foundation
import IntrospectionSDK

#if canImport(AuthenticationServices) && !os(watchOS)
import AuthenticationServices
#endif

enum Authentication {
    static func apiKey() -> IntrospectionClient {
        // #region docs:reference/authentication/api-key
        let token = ProcessInfo.processInfo.environment["INTROSPECTION_TOKEN"]!
        let client = IntrospectionClient(
            controlPlaneURL: URL(string: "https://api.introspection.dev")!,
            credentials: BearerToken(token)
        )
        // #endregion docs:reference/authentication/api-key
        return client
    }

    static func serviceAccount() async throws -> IntrospectionClient {
        // #region docs:reference/authentication/service-account
        let env = ProcessInfo.processInfo.environment
        // Re-mints the token before it expires and after a 401.
        let client = try await IntrospectionClient.fromServiceAccount(
            clientId: env["INTROSPECTION_SERVICE_ACCOUNT_CLIENT_ID"]!,
            clientSecret: env["INTROSPECTION_SERVICE_ACCOUNT_CLIENT_SECRET"]!,
            project: env["INTROSPECTION_PROJECT"]!
        )
        // #endregion docs:reference/authentication/service-account
        return client
    }

    /// A CLI's sign-in, end to end: the user approves in a browser while the tool polls.
    static func deviceLogin() async throws -> (login: OAuthToken, development: OAuthToken) {
        let auth = AuthAPI()
        let device = try await auth.deviceAuthorization(project: "<project>")
        print("Open \(device.verificationUriComplete ?? device.verificationUri) and confirm \(device.userCode)")
        let login = try await auth.pollDeviceToken(device)
        // The credential `introspection dev` attaches with, minted again when it expires.
        let development = try await auth.developmentCredential(accessToken: login.accessToken)
        return (login, development)
    }

    static func signOut(_ login: OAuthToken) async throws {
        if let cpSession = login.cpSession { try await AuthAPI().oidcLogout(cpSession: cpSession) }
    }

    #if canImport(AuthenticationServices) && !os(watchOS)
    @MainActor
    static func hostedLogin(anchor: ASPresentationAnchor) async throws -> IntrospectionClient {
        // #region docs:reference/authentication/hosted-login
        let auth = AuthClient(
            configuration: .init(
                controlPlaneURL: URL(string: "https://api.introspection.dev")!,
                clientID: "<spa-client-id>",  // public client, no secret
                project: "<project>",
                method: .hostedLogin,
                storage: KeychainSessionStorage()
            ))

        // Opens the system sign-in sheet; the redirect URI must be registered on the application.
        try await HostedLoginPresenter(anchor: anchor).signIn(with: auth, redirectURI: "myapp://callback")
        let client = try await auth.client()
        // #endregion docs:reference/authentication/hosted-login
        return client
    }
    #endif
}
