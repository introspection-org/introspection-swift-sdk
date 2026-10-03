import Foundation

// MARK: JWT claims

/// The payload of a JWT, decoded WITHOUT verifying its signature. Use it to
/// read `exp`, `jti`, `org_id` and the like from a token you already trust.
public struct JWTClaims: Sendable, Hashable {
    /// Every claim, verbatim.
    public let raw: JSONObject

    /// Decode the payload segment of `token`; throws `.decoding` when it is not a JWT.
    public init(token: String) throws {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2,
            let data = OAuthBase64URL.decode(String(segments[1])),
            let object = try? JSONCoding.decoder.decode(JSONObject.self, from: data)
        else {
            throw IntrospectionError(kind: .decoding, message: "Not a JWT: the payload segment is not base64url JSON")
        }
        raw = object
    }

    public init(raw: JSONObject) {
        self.raw = raw
    }

    public subscript(_ claim: String) -> JSONValue? { raw[claim] }

    public var expiresAt: Date? { raw["exp"]?.doubleValue.map(Date.init(timeIntervalSince1970:)) }
    public var issuedAt: Date? { raw["iat"]?.doubleValue.map(Date.init(timeIntervalSince1970:)) }
    public var notBefore: Date? { raw["nbf"]?.doubleValue.map(Date.init(timeIntervalSince1970:)) }
    /// The token id; on Introspection access tokens, the session id.
    public var jti: String? { raw["jti"]?.stringValue }
    public var subject: String? { raw["sub"]?.stringValue }
    public var issuer: String? { raw["iss"]?.stringValue }
    /// `aud` as a list, whether the token carries a string or an array.
    public var audience: [String] {
        switch raw["aud"] {
        case let .string(value)?: return [value]
        case let .array(values)?: return values.compactMap(\.stringValue)
        default: return []
        }
    }
    public var orgId: String? { raw["org_id"]?.stringValue }
    public var projectId: String? { raw["project_id"]?.stringValue }
    public var memberId: String? { raw["member_id"]?.stringValue }
    public var memberType: String? { raw["member_type"]?.stringValue }
    public var orgRole: String? { raw["org_role"]?.stringValue }
    public var deploymentId: String? { raw["deployment_id"]?.stringValue }
    public var environment: String? { raw["environment"]?.stringValue }
    /// Introspection token type: `access_token`, `api_key`, `dev`, ...
    public var tokenType: String? { raw["type"]?.stringValue }
    public var scope: String? { raw["scope"]?.stringValue }
    public var email: String? { raw["email"]?.stringValue }
}

// MARK: Session token

/// An access token plus what is needed to renew it. `Codable` so an app can
/// keep it in the keychain.
public struct SessionToken: Codable, Sendable, Hashable {
    public var accessToken: String
    public var expiresAt: Date?
    /// Rotated by every refresh.
    public var refreshToken: String?
    /// The CP session id (the access token's `jti`).
    public var sessionId: String?
    public var orgId: String?
    public var projectId: String?
    /// The Data Plane URL the server returned with the token, if any.
    public var dataPlaneURL: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresAt = "expires_at"
        case refreshToken = "refresh_token"
        case sessionId = "session_id"
        case orgId = "org_id"
        case projectId = "project_id"
        case dataPlaneURL = "dp_url"
    }

    public init(
        accessToken: String,
        expiresAt: Date? = nil,
        refreshToken: String? = nil,
        sessionId: String? = nil,
        orgId: String? = nil,
        projectId: String? = nil,
        dataPlaneURL: String? = nil
    ) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
        self.refreshToken = refreshToken
        self.sessionId = sessionId
        self.orgId = orgId
        self.projectId = projectId
        self.dataPlaneURL = dataPlaneURL
    }

    /// From a token-endpoint response; missing ids are read from the JWT, then from `previous`.
    public init(oauth: OAuthToken, receivedAt: Date = Date(), previous: SessionToken? = nil) {
        let claims = try? JWTClaims(token: oauth.accessToken)
        self.init(
            accessToken: oauth.accessToken,
            expiresAt: oauth.expiresIn.map { receivedAt.addingTimeInterval(TimeInterval($0)) } ?? claims?.expiresAt,
            refreshToken: oauth.refreshToken ?? previous?.refreshToken,
            sessionId: oauth.sessionId ?? claims?.jti ?? previous?.sessionId,
            orgId: oauth.orgId ?? claims?.orgId ?? previous?.orgId,
            projectId: oauth.projectId ?? claims?.projectId ?? previous?.projectId,
            dataPlaneURL: oauth.dpUrl ?? previous?.dataPlaneURL
        )
    }

    /// From a `POST /v1/tokens` response; the session id is the JWT `jti`.
    public init(dataPlaneToken token: DataPlaneToken) {
        let claims = try? JWTClaims(token: token.accessToken)
        self.init(
            accessToken: token.accessToken,
            expiresAt: token.expiresAt ?? claims?.expiresAt,
            refreshToken: token.refreshToken,
            sessionId: claims?.jti,
            orgId: token.orgId ?? claims?.orgId,
            projectId: token.projectId ?? claims?.projectId,
            dataPlaneURL: token.dataPlaneURL?.absoluteString
        )
    }

    /// The decoded (unverified) claims of `accessToken`.
    public var claims: JWTClaims? { try? JWTClaims(token: accessToken) }
}

// MARK: SessionCredentials

/// A refreshing `CredentialProvider`: renews the token `leeway` seconds before
/// it expires and after a 401, with concurrent callers sharing one in-flight
/// refresh. A failed refresh surfaces as `IntrospectionError` `.authentication`.
public actor SessionCredentials: CredentialProvider {
    /// Produce a new token from the current one.
    public typealias Refresh = @Sendable (SessionToken) async throws -> SessionToken
    /// Called after every successful refresh, before any caller sees the new token.
    public typealias TokenUpdate = @Sendable (SessionToken) async -> Void

    public private(set) var token: SessionToken
    public let leeway: TimeInterval
    private let refresher: Refresh
    private let onTokenUpdate: TokenUpdate?
    private let now: @Sendable () -> Date
    private var inFlight: Task<SessionToken, Error>?

    public init(
        token: SessionToken,
        leeway: TimeInterval = 60,
        now: @escaping @Sendable () -> Date = { Date() },
        onTokenUpdate: TokenUpdate? = nil,
        refresh: @escaping Refresh
    ) {
        self.token = token
        self.leeway = leeway
        self.now = now
        self.onTokenUpdate = onTokenUpdate
        refresher = refresh
    }

    public func authorization() async throws -> String? {
        var current = token
        if let expiresAt = current.expiresAt, expiresAt.addingTimeInterval(-leeway) <= now() {
            current = try await refresh()
        }
        return "Bearer \(current.accessToken)"
    }

    public func refreshAfterUnauthorized(rejected authorization: String?) async throws -> Bool {
        // A request that carried an older token only needs a retry; one that carried
        // the current token proves it is no longer accepted.
        if inFlight == nil, let authorization, authorization != "Bearer \(token.accessToken)" {
            return true
        }
        _ = try await refresh()
        return true
    }

    /// Refresh now, or join the refresh already in flight.
    @discardableResult
    public func refresh() async throws -> SessionToken {
        if let inFlight { return try await inFlight.value }
        let current = token
        let task = Task<SessionToken, Error> {
            defer { self.inFlight = nil }
            let next: SessionToken
            do {
                next = try await self.refresher(current)
            } catch let error as IntrospectionError where error.kind == .authentication || error.kind == .runnerExpired {
                throw error
            } catch {
                let inner = error as? IntrospectionError
                throw IntrospectionError(
                    kind: .authentication,
                    message: "Session refresh failed: \(inner?.message ?? String(describing: error))",
                    status: inner?.status ?? 0, code: inner?.oauthError ?? inner?.code,
                    requestId: inner?.requestId, body: inner?.body, underlying: error
                )
            }
            self.token = next
            await self.onTokenUpdate?(next)
            return next
        }
        inFlight = task
        return try await task.value
    }

    /// Replace the token (for example after a fresh login).
    public func update(_ token: SessionToken) {
        self.token = token
    }
}

extension SessionCredentials {
    /// Credentials for the platform hosted login (primary path): refreshes through
    /// CP `POST /v1/oauth/token` `grant_type=refresh_token` with the login's
    /// `client_id`, `session_id` and `org_id`. Persist rotated refresh tokens in `onTokenUpdate`.
    public static func platformSession(
        token: OAuthToken,
        clientID: String,
        orgID: String? = nil,
        controlPlane: AuthAPI,
        leeway: TimeInterval = 60,
        onTokenUpdate: TokenUpdate? = nil
    ) -> SessionCredentials {
        var session = SessionToken(oauth: token)
        if let orgID { session.orgId = orgID }
        return refreshing(session, clientID: clientID, controlPlane: controlPlane, leeway: leeway, onTokenUpdate: onTokenUpdate)
    }

    /// Credentials for a session restored from storage (any CP-refreshable session).
    public static func platformSession(
        restoring token: SessionToken,
        clientID: String,
        controlPlane: AuthAPI,
        leeway: TimeInterval = 60,
        onTokenUpdate: TokenUpdate? = nil
    ) -> SessionCredentials {
        refreshing(token, clientID: clientID, controlPlane: controlPlane, leeway: leeway, onTokenUpdate: onTokenUpdate)
    }

    /// Credentials for a Data Plane session minted by `POST /v1/tokens` with
    /// `include_refresh_token` (secondary, Zitadel-direct path): refreshes with `client_id=dataplane`.
    public static func dataPlaneSession(
        token: SessionToken,
        controlPlane: AuthAPI,
        leeway: TimeInterval = 60,
        onTokenUpdate: TokenUpdate? = nil
    ) -> SessionCredentials {
        refreshing(token, clientID: OAuthClientID.dataPlane, controlPlane: controlPlane, leeway: leeway, onTokenUpdate: onTokenUpdate)
    }

    /// Credentials for federated login through a `jwks` (or `spa`) Application:
    /// RFC 8693 token exchange at CP `POST /v1/oauth/token`.
    ///
    /// `subjectToken` returns a current token from the app's own IdP (for example a
    /// freshly refreshed Supabase access token). No refresh token is issued, so the
    /// exchange simply runs again before expiry and after a 401. The first exchange
    /// happens on the first request. The server accepts only the `id_token` subject
    /// type (or none) on this grant, whatever kind of JWT the IdP issued.
    public static func tokenExchange(
        subjectToken: @escaping @Sendable () async throws -> String,
        clientID: String,
        project: String,
        controlPlane: AuthAPI,
        subjectTokenType: String = OAuthTokenType.idToken,
        scope: String? = nil,
        leeway: TimeInterval = 60,
        onTokenUpdate: TokenUpdate? = nil
    ) -> SessionCredentials {
        SessionCredentials(
            token: SessionToken(accessToken: "", expiresAt: .distantPast),
            leeway: leeway,
            onTokenUpdate: onTokenUpdate
        ) { current in
            let subject = try await subjectToken()
            let response = try await controlPlane.tokenExchange(
                subjectToken: subject, clientId: clientID, project: project,
                subjectTokenType: subjectTokenType, scope: scope
            )
            return SessionToken(oauth: response, previous: current)
        }
    }

    /// `tokenExchange` against a Control Plane URL.
    public static func tokenExchange(
        subjectToken: @escaping @Sendable () async throws -> String,
        clientID: String,
        project: String,
        controlPlaneURL: URL = AuthAPI.defaultControlPlaneURL,
        transport: any HTTPTransport = URLSessionTransport(),
        subjectTokenType: String = OAuthTokenType.idToken,
        scope: String? = nil,
        leeway: TimeInterval = 60,
        onTokenUpdate: TokenUpdate? = nil
    ) -> SessionCredentials {
        tokenExchange(
            subjectToken: subjectToken, clientID: clientID, project: project,
            controlPlane: AuthAPI(controlPlaneURL: controlPlaneURL, transport: transport),
            subjectTokenType: subjectTokenType, scope: scope, leeway: leeway, onTokenUpdate: onTokenUpdate
        )
    }

    private static func refreshing(
        _ token: SessionToken,
        clientID: String,
        controlPlane: AuthAPI,
        leeway: TimeInterval,
        onTokenUpdate: TokenUpdate?
    ) -> SessionCredentials {
        SessionCredentials(token: token, leeway: leeway, onTokenUpdate: onTokenUpdate) { current in
            guard let refreshToken = current.refreshToken,
                let sessionId = current.sessionId ?? current.claims?.jti,
                let orgId = current.orgId ?? current.claims?.orgId
            else {
                throw IntrospectionError(
                    kind: .authentication,
                    message: "The session cannot be refreshed: it has no refresh token, session id or org id"
                )
            }
            let response = try await controlPlane.refresh(
                refreshToken: refreshToken, clientId: clientID, sessionId: sessionId, orgId: orgId
            )
            return SessionToken(oauth: response, previous: current)
        }
    }
}
