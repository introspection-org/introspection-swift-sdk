import Foundation

extension IntrospectionClient {
    /// A client for an end user signed in with a federated identity provider
    /// (for example Supabase) through a Direct JWKS Application.
    ///
    /// `subjectToken` returns the provider's current access token; the app's own
    /// provider SDK keeps it fresh. The first token exchange runs here, so the
    /// Data Plane URL the platform returns is known before the client is built.
    /// Later exchanges run before expiry and after a 401.
    ///
    /// ```swift
    /// let client = try await IntrospectionClient.federated(
    ///     subjectToken: { try await supabase.auth.session.accessToken },
    ///     clientID: "intro_app_...",
    ///     project: "ark",
    ///     controlPlaneURL: URL(string: "https://api.introspection.dev")!
    /// )
    /// let run = try await client.tasks.start(prompt: "Hello", TaskCreate(runtimeId: runtimeId))
    /// ```
    ///
    /// A federated token is not a runner token, so a task runs on the app's runtime
    /// only when its create and runs name the runtime version (`runtimeId`). Resolve
    /// that id on the app's backend, as the JavaScript browser client does.
    public static func federated(
        subjectToken: @escaping @Sendable () async throws -> String,
        clientID: String,
        project: String,
        controlPlaneURL: URL = AuthAPI.defaultControlPlaneURL,
        dataPlaneURL: URL? = nil,
        transport: any HTTPTransport = URLSessionTransport(),
        options: HTTPClient.Options = HTTPClient.Options(),
        onTokenUpdate: SessionCredentials.TokenUpdate? = nil
    ) async throws -> IntrospectionClient {
        let credentials = SessionCredentials.tokenExchange(
            subjectToken: subjectToken,
            clientID: clientID,
            project: project,
            controlPlane: AuthAPI(controlPlaneURL: controlPlaneURL, transport: transport, options: options),
            onTokenUpdate: onTokenUpdate
        )
        let token = try await credentials.refresh()
        guard let resolved = dataPlaneURL ?? token.dataPlaneURL.flatMap(URL.init(string:)) else {
            throw IntrospectionError(
                kind: .invalidRequest,
                message: "The token exchange returned no Data Plane URL; pass dataPlaneURL explicitly"
            )
        }
        return IntrospectionClient(
            configuration: .init(
                controlPlaneURL: controlPlaneURL,
                dataPlaneURL: resolved,
                controlPlaneCredentials: credentials,
                transport: transport,
                options: options
            ))
    }
}
