import Foundation

/// A signed-in member's session: the platform token plus who it belongs to.
public struct AuthSession: Codable, Sendable, Hashable {
    public var token: SessionToken
    public var user: AuthUser

    public init(token: SessionToken) {
        self.token = token
        user = AuthUser(claims: token.claims)
    }

    public var accessToken: String { token.accessToken }
    public var expiresAt: Date? { token.expiresAt }
    /// The Data Plane URL the platform returned with the token.
    public var dataPlaneURL: URL? { token.dataPlaneURL.flatMap(URL.init(string:)) }

    enum CodingKeys: String, CodingKey { case token, user }
}

/// The member a session belongs to, from the token's claims.
public struct AuthUser: Codable, Sendable, Hashable {
    public var memberId: String?
    public var orgId: String?
    public var projectId: String?
    /// `business`, `customer` or `agent`.
    public var memberType: String?
    public var email: String?

    public init(memberId: String? = nil, orgId: String? = nil, projectId: String? = nil, memberType: String? = nil, email: String? = nil) {
        self.memberId = memberId
        self.orgId = orgId
        self.projectId = projectId
        self.memberType = memberType
        self.email = email
    }

    init(claims: JWTClaims?) {
        self.init(
            memberId: claims?.memberId ?? claims?.subject,
            orgId: claims?.orgId,
            projectId: claims?.projectId,
            memberType: claims?.memberType,
            email: claims?.email
        )
    }

    enum CodingKeys: String, CodingKey {
        case memberId = "member_id"
        case orgId = "org_id"
        case projectId = "project_id"
        case memberType = "member_type"
        case email
    }
}

/// What changed, mirroring Supabase's `AuthChangeEvent`.
public enum AuthChangeEvent: String, Sendable, Hashable {
    /// Emitted once to each new listener with the session restored from storage (or nil).
    case initialSession
    case signedIn
    case signedOut
    case tokenRefreshed
}

/// Where a session is kept between launches. Use `KeychainSessionStorage` on
/// Apple platforms; `InMemorySessionStorage` keeps nothing across launches.
public protocol SessionStorage: Sendable {
    func load(key: String) async throws -> Data?
    func save(_ data: Data, key: String) async throws
    func remove(key: String) async throws
}

public actor InMemorySessionStorage: SessionStorage {
    private var values: [String: Data] = [:]
    public init() {}
    public func load(key: String) -> Data? { values[key] }
    public func save(_ data: Data, key: String) { values[key] = data }
    public func remove(key: String) { values[key] = nil }
}

/// How sessions are obtained and renewed.
///
/// With a federated identity provider (a `jwks` Application, for example
/// Supabase), the provider's own SDK owns sign-in and the session; use
/// `SessionCredentials.tokenExchange` instead of `AuthClient`.
public enum AuthMethod: Sendable {
    /// The platform's native email-code sign-in (`signInWithOTP` / `verifyOTP`),
    /// refreshed with the platform refresh grant. Requires a Control Plane with
    /// native email sign-in (proposed in `docs/design/native-email-auth.md`).
    case emailCode
    /// The platform's hosted login (an `spa` Application), refreshed with the
    /// platform refresh grant. Sign in with `HostedLoginPresenter`, or complete a
    /// callback yourself with `completeHostedLogin(_:callbackURL:)`.
    case hostedLogin
}

/// Sign-in, session persistence and refresh for an app, shaped like the Supabase
/// Auth client: `signInWithOTP`, `verifyOTP`, `session`, `refreshSession`,
/// `signOut` and `authStateChanges`. Hand `credentials` to `IntrospectionClient`,
/// or use `client()`.
public actor AuthClient {
    public struct Configuration: Sendable {
        public var controlPlaneURL: URL
        /// The Application's client id.
        public var clientID: String
        /// The project the session is scoped to (slug or id).
        public var project: String
        public var method: AuthMethod
        public var storage: any SessionStorage
        /// Storage key; change it to keep separate sessions per environment.
        public var storageKey: String
        /// Refresh this many seconds before expiry.
        public var leeway: TimeInterval
        public var transport: any HTTPTransport

        public init(
            controlPlaneURL: URL,
            clientID: String,
            project: String,
            method: AuthMethod,
            storage: any SessionStorage = InMemorySessionStorage(),
            storageKey: String = "introspection.auth.session",
            leeway: TimeInterval = 60,
            transport: any HTTPTransport = URLSessionTransport()
        ) {
            self.controlPlaneURL = controlPlaneURL
            self.clientID = clientID
            self.project = project
            self.method = method
            self.storage = storage
            self.storageKey = storageKey
            self.leeway = leeway
            self.transport = transport
        }
    }

    public nonisolated let configuration: Configuration
    /// The Control Plane auth endpoints this client uses.
    public nonisolated let api: AuthAPI
    private let now: @Sendable () -> Date

    private var current: AuthSession?
    private var generation: UInt64 = 0
    private var storageWrite: Task<Void, any Error>?
    private var restored = false
    private var restoring: Task<Void, Never>?
    private var refreshing: Task<AuthSession, any Error>?
    private var listeners: [UUID: AsyncStream<(AuthChangeEvent, AuthSession?)>.Continuation] = [:]

    public init(configuration: Configuration, now: @escaping @Sendable () -> Date = { Date() }) {
        self.configuration = configuration
        api = AuthAPI(controlPlaneURL: configuration.controlPlaneURL, transport: configuration.transport)
        self.now = now
    }

    // MARK: Sign-in

    /// Send a one-time code to `email`. The response is the same whether or not the
    /// email has an account.
    public func signInWithOTP(email: String) async throws {
        try requireMethod(.emailCode)
        try await api.http.empty(
            "POST", "/v1/oauth/email/code",
            body: .encode(
                EmailCodeRequest(
                    clientId: configuration.clientID, email: email, project: configuration.project
                )))
    }

    /// Verify the code sent to `email` and sign in. Throws `CancellationError` when a
    /// sign-out or another sign-in completes while the code is being verified.
    @discardableResult
    public func verifyOTP(email: String, token code: String) async throws -> AuthSession {
        try requireMethod(.emailCode)
        let generation = self.generation
        let response = try await api.token(
            grantType: OAuthGrantType.emailCode, clientId: configuration.clientID,
            parameters: [
                ("email", email), ("code", code), ("project", configuration.project),
            ])
        return try await signedIn(SessionToken(oauth: response, receivedAt: now()), ifCurrent: generation)
    }

    /// Start a hosted login: open `request.url` in a browser session and pass the
    /// callback URL to `completeHostedLogin(_:callbackURL:)`.
    public nonisolated func hostedLoginRequest(redirectURI: String, scope: String = "*") -> HostedLoginRequest {
        api.hostedLogin(clientID: configuration.clientID, redirectURI: redirectURI, project: configuration.project, scope: scope)
    }

    /// Finish a hosted login from its callback URL. Throws `CancellationError` when a
    /// sign-out or another sign-in completes while the code is being exchanged.
    @discardableResult
    public func completeHostedLogin(_ request: HostedLoginRequest, callbackURL: URL) async throws -> AuthSession {
        let generation = self.generation
        let response = try await api.completeHostedLogin(request, callbackURL: callbackURL)
        return try await signedIn(SessionToken(oauth: response, receivedAt: now()), ifCurrent: generation)
    }

    /// Adopt a platform token obtained elsewhere (for example from a login service).
    @discardableResult
    public func setSession(_ token: OAuthToken) async throws -> AuthSession {
        try await signedIn(SessionToken(oauth: token, receivedAt: now()))
    }

    // MARK: Session

    /// The current session, restored from storage on first use and refreshed when
    /// it is within `leeway` of expiry. Nil when signed out.
    public var session: AuthSession? {
        get async throws {
            await restoreIfNeeded()
            guard let current else { return nil }
            if let expiresAt = current.expiresAt, expiresAt.addingTimeInterval(-configuration.leeway) <= now() {
                return try await refreshSession()
            }
            return current
        }
    }

    /// Renew the session now, or join the renewal already in flight. A refresh the
    /// server rejects signs the user out and throws `.authentication`.
    @discardableResult
    public func refreshSession() async throws -> AuthSession {
        await restoreIfNeeded()
        if let refreshing { return try await refreshing.value }
        guard let session = current else {
            throw IntrospectionError(kind: .authentication, message: "Not signed in")
        }
        let generation = self.generation
        let task = Task<AuthSession, any Error> {
            defer { if self.generation == generation { self.refreshing = nil } }
            do {
                let next = AuthSession(token: try await self.renew(session.token))
                try Task.checkCancellation()
                guard self.generation == generation else { throw CancellationError() }
                try await self.store(next)
                try Task.checkCancellation()
                guard self.generation == generation else { throw CancellationError() }
                self.current = next
                self.emit(.tokenRefreshed, next)
                return next
            } catch let error as IntrospectionError where Self.isRejection(error) {
                guard self.generation == generation else { throw CancellationError() }
                await self.clear()
                throw IntrospectionError(
                    kind: .authentication, message: "The session is no longer valid: \(error.message)",
                    status: error.status, code: error.code, requestId: error.requestId, underlying: error
                )
            }
        }
        refreshing = task
        return try await task.value
    }

    /// Sign out: revoke the platform session when it has one, then forget it locally.
    /// The local session is cleared even if revocation fails.
    public func signOut() async throws {
        await restoreIfNeeded()
        let session = current
        await clear()
        if let sessionId = session?.token.sessionId ?? session?.token.claims?.jti,
            let orgId = session?.token.orgId ?? session?.user.orgId,
            session?.token.refreshToken != nil
        {
            try await api.revoke(sessionId: sessionId, orgId: orgId, clientId: configuration.clientID)
        }
    }

    /// Session changes. A new listener first receives `.initialSession`.
    public func authStateChanges() async -> AsyncStream<(AuthChangeEvent, AuthSession?)> {
        await restoreIfNeeded()
        let id = UUID()
        let (stream, continuation) = AsyncStream<(AuthChangeEvent, AuthSession?)>.makeStream()
        continuation.yield((.initialSession, current))
        listeners[id] = continuation
        continuation.onTermination = { _ in Task { await self.removeListener(id) } }
        return stream
    }

    // MARK: Using the session

    /// A `CredentialProvider` backed by this client's session.
    public nonisolated var credentials: any CredentialProvider { AuthClientCredentials(auth: self) }

    /// A client authenticated as the signed-in member. The Data Plane URL defaults
    /// to the one returned with the session; `otelURL` and `eventLogging` configure custom events.
    public func client(
        dataPlaneURL: URL? = nil, options: HTTPClient.Options = HTTPClient.Options(), otelURL: URL? = nil,
        eventLogging: EventLogger.Configuration = EventLogger.Configuration()
    ) async throws -> IntrospectionClient {
        guard let session = try await session else {
            throw IntrospectionError(kind: .authentication, message: "Not signed in")
        }
        return IntrospectionClient(
            configuration: .init(
                controlPlaneURL: configuration.controlPlaneURL,
                dataPlaneURL: dataPlaneURL ?? session.dataPlaneURL ?? configuration.controlPlaneURL,
                controlPlaneCredentials: credentials,
                transport: configuration.transport,
                options: options,
                otelURL: otelURL,
                eventLogging: eventLogging
            ))
    }

    // MARK: Internals

    private func requireMethod(_ expected: AuthMethodKind) throws {
        guard AuthMethodKind(configuration.method) == expected else {
            throw IntrospectionError(kind: .invalidRequest, message: "This operation requires the \(expected) sign-in method")
        }
    }

    private func renew(_ token: SessionToken) async throws -> SessionToken {
        guard let refreshToken = token.refreshToken,
            let sessionId = token.sessionId ?? token.claims?.jti,
            let orgId = token.orgId ?? token.claims?.orgId
        else {
            throw IntrospectionError(kind: .authentication, message: "The session has no refresh token")
        }
        let response = try await api.refresh(
            refreshToken: refreshToken, clientId: configuration.clientID, sessionId: sessionId, orgId: orgId
        )
        return SessionToken(oauth: response, receivedAt: now(), previous: token)
    }

    /// `expected` is the generation read before a sign-in request was sent; a sign-out or
    /// sign-in since then has superseded the response.
    private func signedIn(_ token: SessionToken, ifCurrent expected: UInt64? = nil) async throws -> AuthSession {
        if let expected, generation != expected { throw CancellationError() }
        generation &+= 1
        let generation = self.generation
        refreshing?.cancel()
        refreshing = nil
        restored = true
        current = nil
        let session = AuthSession(token: token)
        try await store(session)
        guard self.generation == generation else { throw CancellationError() }
        current = session
        emit(.signedIn, session)
        return session
    }

    private func store(_ session: AuthSession) async throws {
        let data = try JSONCoding.encoder.encode(session)
        let previous = storageWrite
        let configuration = self.configuration
        // Storage is async too: writes must finish in session-transition order.
        let write = Task {
            _ = try? await previous?.value
            try await configuration.storage.save(data, key: configuration.storageKey)
        }
        storageWrite = write
        try await write.value
    }

    private func clear() async {
        generation &+= 1
        refreshing?.cancel()
        refreshing = nil
        let hadSession = current != nil
        current = nil
        restored = true
        if hadSession { emit(.signedOut, nil) }
        let previous = storageWrite
        let configuration = self.configuration
        let write = Task {
            _ = try? await previous?.value
            try await configuration.storage.remove(key: configuration.storageKey)
        }
        storageWrite = write
        _ = try? await write.value
    }

    /// Concurrent first callers share one load, so none of them sees the session as absent while it is read.
    private func restoreIfNeeded() async {
        guard !restored else { return }
        if let restoring { return await restoring.value }
        let task = Task {
            let data = try? await self.configuration.storage.load(key: self.configuration.storageKey)
            if !self.restored, let data, let session = try? JSONCoding.decoder.decode(AuthSession.self, from: data) {
                self.current = session
            }
            self.restored = true
            self.restoring = nil
        }
        restoring = task
        await task.value
    }

    private func emit(_ event: AuthChangeEvent, _ session: AuthSession?) {
        for continuation in listeners.values { continuation.yield((event, session)) }
    }

    private func removeListener(_ id: UUID) {
        listeners[id] = nil
    }

    /// A rejection by the server, as opposed to a network failure that should not sign the user out.
    static func isRejection(_ error: IntrospectionError) -> Bool {
        switch error.kind {
        case .authentication, .runnerExpired, .forbidden, .validation: return true
        default: return error.oauthError == "invalid_grant"
        }
    }
}

/// `CredentialProvider` over an `AuthClient`.
struct AuthClientCredentials: CredentialProvider {
    let auth: AuthClient

    func authorization() async throws -> String? {
        guard let session = try await auth.session else { return nil }
        return "Bearer \(session.accessToken)"
    }

    func refreshAfterUnauthorized(rejected authorization: String?) async throws -> Bool {
        guard let session = try await auth.session else { return false }
        if let authorization, authorization != "Bearer \(session.accessToken)" { return true }
        _ = try await auth.refreshSession()
        return true
    }
}

enum AuthMethodKind: String, CustomStringConvertible {
    case emailCode = "email code"
    case hostedLogin = "hosted login"

    init(_ method: AuthMethod) {
        switch method {
        case .emailCode: self = .emailCode
        case .hostedLogin: self = .hostedLogin
        }
    }

    var description: String { rawValue }
}

struct EmailCodeRequest: Encodable {
    let clientId: String
    let email: String
    let project: String

    enum CodingKeys: String, CodingKey {
        case clientId = "client_id"
        case email, project
    }
}
