import Foundation

// MARK: Constants

/// `grant_type` values the Control Plane token endpoint accepts.
public enum OAuthGrantType {
    public static let clientCredentials = "client_credentials"
    public static let authorizationCode = "authorization_code"
    public static let refreshToken = "refresh_token"
    public static let deviceCode = "urn:ietf:params:oauth:grant-type:device_code"
    public static let tokenExchange = "urn:ietf:params:oauth:grant-type:token-exchange"
    public static let jwtBearer = "urn:ietf:params:oauth:grant-type:jwt-bearer"
    /// Native email-code sign-in (proposed; see `AuthClient.verifyOTP`).
    public static let emailCode = "urn:introspection:params:oauth:grant-type:email_code"
}

/// RFC 8693 token type URIs.
public enum OAuthTokenType {
    public static let idToken = "urn:ietf:params:oauth:token-type:id_token"
    public static let accessToken = "urn:ietf:params:oauth:token-type:access_token"
}

/// First-party OAuth client ids on the Control Plane.
public enum OAuthClientID {
    /// Sessions minted by `POST /v1/tokens` with `include_refresh_token`.
    public static let dataPlane = "dataplane"
    /// The CLI: the only client allowed to drive the device flow.
    public static let cli = "cli"
}

extension IntrospectionError {
    /// The RFC 6749 section 5.2 `error` code of a token-endpoint failure (`invalid_grant`, `slow_down`, ...).
    public var oauthError: String? { body?["error"]?.stringValue }
    /// The token-endpoint `error_description`, when sent.
    public var oauthErrorDescription: String? { body?["error_description"]?.stringValue }
}

// MARK: Models

/// A token-endpoint response. Fields the SDK does not model are kept in `extra`.
public struct OAuthToken: Codable, Sendable, Hashable {
    public var accessToken: String
    public var tokenType: String?
    /// Lifetime in seconds.
    public var expiresIn: Int?
    public var scope: String?
    /// Rotated on every refresh: persist the new one.
    public var refreshToken: String?
    public var idToken: String?
    /// The session row id (the access token's `jti`); needed to refresh or revoke.
    public var sessionId: String?
    public var orgId: String?
    public var projectId: String?
    /// Data Plane API base URL for the token's project, when the CP can resolve it.
    public var dpUrl: String?
    public var cpUrl: String?
    public var gitUrl: String?
    public var platformUrl: String?
    /// Encoded `intro_cp_session` cookie value (device flow only).
    public var cpSession: String?
    public var memberId: String?
    public var memberName: String?
    /// RFC 8693 actor claim, when the session is delegated.
    public var act: JSONValue?
    /// Every other field of the response.
    public var extra: JSONObject

    enum CodingKeys: String, CodingKey, CaseIterable {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case scope
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case sessionId = "session_id"
        case orgId = "org_id"
        case projectId = "project_id"
        case dpUrl = "dp_url"
        case cpUrl = "cp_url"
        case gitUrl = "git_url"
        case platformUrl = "platform_url"
        case cpSession = "cp_session"
        case memberId = "member_id"
        case memberName = "member_name"
        case act
    }

    public init(
        accessToken: String,
        tokenType: String? = "Bearer",
        expiresIn: Int? = nil,
        scope: String? = nil,
        refreshToken: String? = nil,
        idToken: String? = nil,
        sessionId: String? = nil,
        orgId: String? = nil,
        projectId: String? = nil,
        dpUrl: String? = nil,
        extra: JSONObject = [:]
    ) {
        self.accessToken = accessToken
        self.tokenType = tokenType
        self.expiresIn = expiresIn
        self.scope = scope
        self.refreshToken = refreshToken
        self.idToken = idToken
        self.sessionId = sessionId
        self.orgId = orgId
        self.projectId = projectId
        self.dpUrl = dpUrl
        self.extra = extra
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        tokenType = try container.decodeIfPresent(String.self, forKey: .tokenType)
        if let seconds = try? container.decodeIfPresent(Double.self, forKey: .expiresIn) {
            expiresIn = Int(seconds)
        } else if let text = try? container.decodeIfPresent(String.self, forKey: .expiresIn) {
            expiresIn = Int(text)
        }
        scope = try container.decodeIfPresent(String.self, forKey: .scope)
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
        idToken = try container.decodeIfPresent(String.self, forKey: .idToken)
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        orgId = try container.decodeIfPresent(String.self, forKey: .orgId)
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId)
        dpUrl = try container.decodeIfPresent(String.self, forKey: .dpUrl)
        cpUrl = try container.decodeIfPresent(String.self, forKey: .cpUrl)
        gitUrl = try container.decodeIfPresent(String.self, forKey: .gitUrl)
        platformUrl = try container.decodeIfPresent(String.self, forKey: .platformUrl)
        cpSession = try container.decodeIfPresent(String.self, forKey: .cpSession)
        memberId = try container.decodeIfPresent(String.self, forKey: .memberId)
        memberName = try container.decodeIfPresent(String.self, forKey: .memberName)
        act = try container.decodeIfPresent(JSONValue.self, forKey: .act)
        var all = (try? decoder.singleValueContainer().decode(JSONObject.self)) ?? [:]
        for key in CodingKeys.allCases { all.removeValue(forKey: key.rawValue) }
        extra = all
    }

    public func encode(to encoder: Encoder) throws {
        var object = extra
        object[CodingKeys.accessToken.rawValue] = .string(accessToken)
        let optionals: [(CodingKeys, String?)] = [
            (.tokenType, tokenType), (.scope, scope), (.refreshToken, refreshToken), (.idToken, idToken),
            (.sessionId, sessionId), (.orgId, orgId), (.projectId, projectId), (.dpUrl, dpUrl),
            (.cpUrl, cpUrl), (.gitUrl, gitUrl), (.platformUrl, platformUrl), (.cpSession, cpSession),
            (.memberId, memberId), (.memberName, memberName),
        ]
        for (key, value) in optionals {
            if let value { object[key.rawValue] = .string(value) }
        }
        if let expiresIn { object[CodingKeys.expiresIn.rawValue] = .number(Double(expiresIn)) }
        if let act { object[CodingKeys.act.rawValue] = act }
        var container = encoder.singleValueContainer()
        try container.encode(object)
    }

    /// When the access token expires, from `expires_in` relative to `receivedAt`, else the JWT `exp`.
    public func expiresAt(receivedAt: Date = Date()) -> Date? {
        if let expiresIn { return receivedAt.addingTimeInterval(TimeInterval(expiresIn)) }
        return (try? JWTClaims(token: accessToken))?.expiresAt
    }
}

/// RFC 8628 device authorization response from `POST /v1/oauth/device/code`.
public struct DeviceAuthorization: Codable, Sendable, Hashable {
    /// Polled at the token endpoint; keep it secret.
    public let deviceCode: String
    /// The short code the user types on the activation page.
    public let userCode: String
    public let verificationUri: String
    public let verificationUriComplete: String?
    /// Seconds until `deviceCode` expires.
    public let expiresIn: Int
    /// Minimum seconds between polls.
    public let interval: Int?

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationUri = "verification_uri"
        case verificationUriComplete = "verification_uri_complete"
        case expiresIn = "expires_in"
        case interval
    }

    public init(
        deviceCode: String, userCode: String, verificationUri: String,
        verificationUriComplete: String? = nil, expiresIn: Int, interval: Int? = 5
    ) {
        self.deviceCode = deviceCode
        self.userCode = userCode
        self.verificationUri = verificationUri
        self.verificationUriComplete = verificationUriComplete
        self.expiresIn = expiresIn
        self.interval = interval
    }
}

/// Body of `POST /v1/tokens`: mint a Data Plane token for a project.
public struct DataPlaneTokenRequest: Encodable, Sendable, Hashable {
    /// Project slug or id.
    public var project: String
    /// 1...720. Ignored when `includeRefreshToken` is true (the server uses its access-token lifetime).
    public var expiresHours: Int?
    /// 1...60. Ignored when `includeRefreshToken` is true.
    public var expiresMinutes: Int?
    /// Also create a CP session and return its refresh token (needs a member identity).
    public var includeRefreshToken: Bool?
    /// Environment lane (`development`, `staging`, `production`); omitted means `production`.
    public var environment: String?

    enum CodingKeys: String, CodingKey {
        case project
        case expiresHours = "expires_hours"
        case expiresMinutes = "expires_minutes"
        case includeRefreshToken = "include_refresh_token"
        case environment
    }

    public init(
        project: String,
        expiresHours: Int? = nil,
        expiresMinutes: Int? = nil,
        includeRefreshToken: Bool? = nil,
        environment: String? = nil
    ) {
        self.project = project
        self.expiresHours = expiresHours
        self.expiresMinutes = expiresMinutes
        self.includeRefreshToken = includeRefreshToken
        self.environment = environment
    }
}

/// Response of `POST /v1/tokens`.
public struct DataPlaneToken: Codable, Sendable, Hashable {
    public let accessToken: String
    public let tokenType: String?
    public let expiresAt: Date?
    public let projectId: String?
    public let orgId: String?
    /// Present only with `includeRefreshToken`. Refresh with `AuthAPI.refresh` and `client_id=dataplane`.
    public let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresAt = "expires_at"
        case projectId = "project_id"
        case orgId = "org_id"
        case refreshToken = "refresh_token"
    }

    public init(
        accessToken: String, tokenType: String? = "bearer", expiresAt: Date? = nil,
        projectId: String? = nil, orgId: String? = nil, refreshToken: String? = nil
    ) {
        self.accessToken = accessToken
        self.tokenType = tokenType
        self.expiresAt = expiresAt
        self.projectId = projectId
        self.orgId = orgId
        self.refreshToken = refreshToken
    }

    /// The session id needed to refresh or revoke: the access token's `jti`.
    public var sessionId: String? { (try? JWTClaims(token: accessToken))?.jti }

    /// The Data Plane base URL the token is minted for, read from its `aud`
    /// claim (`https://api.{endpoint}` on cloud deployments). Nil for local
    /// deployments, whose audience is a fixed sentinel.
    public var dataPlaneURL: URL? {
        guard let audience = (try? JWTClaims(token: accessToken))?.audience.first,
              audience.hasPrefix("https://") || audience.hasPrefix("http://")
        else { return nil }
        return URL(string: audience)
    }
}

private struct RevokeResponse: Decodable {
    let status: String?
}

// MARK: AuthAPI

/// Control Plane authentication: `POST /v1/oauth/token` for every grant, the
/// device flow, `POST /v1/tokens` and `POST /v1/oauth/revoke`.
///
/// Token-endpoint calls never send the client's own credentials, so an
/// `AuthAPI` works before any login: `AuthAPI(controlPlaneURL:)`.
public struct AuthAPI: Sendable {
    public static let defaultControlPlaneURL = URL(string: "https://api.introspection.dev")!

    let http: HTTPClient

    public init(http: HTTPClient) {
        self.http = http
    }

    /// An unauthenticated `AuthAPI` for a Control Plane host.
    public init(
        controlPlaneURL: URL = AuthAPI.defaultControlPlaneURL,
        transport: any HTTPTransport = URLSessionTransport(),
        options: HTTPClient.Options = HTTPClient.Options()
    ) {
        http = HTTPClient(baseURL: controlPlaneURL, credentials: nil, transport: transport, options: options)
    }

    /// Any grant: `POST /v1/oauth/token` with these form fields (nil values are omitted).
    public func token(grantType: String, clientId: String, parameters: [(String, String?)] = []) async throws -> OAuthToken {
        var fields: [(String, String)] = [("grant_type", grantType), ("client_id", clientId)]
        for (name, value) in parameters {
            if let value { fields.append((name, value)) }
        }
        return try await http.json("POST", "/v1/oauth/token", body: .form(fields), authenticated: false, as: OAuthToken.self)
    }

    /// `client_credentials` for a confidential service-account Application. No refresh token is issued.
    public func clientCredentials(
        clientId: String,
        clientSecret: String,
        project: String,
        scope: String? = nil
    ) async throws -> OAuthToken {
        try await token(grantType: OAuthGrantType.clientCredentials, clientId: clientId, parameters: [
            ("client_secret", clientSecret), ("project", project), ("scope", scope),
        ])
    }

    /// RFC 8693 token exchange. With a federated Application's `clientId`, trades an end user's
    /// `id_token` for a project-scoped DP token for a `customer` member. With `clientId: "cli"` and
    /// `subjectTokenType: OAuthTokenType.accessToken`, trades a business CLI login for a development bearer.
    public func tokenExchange(
        subjectToken: String,
        clientId: String,
        project: String? = nil,
        subjectTokenType: String = OAuthTokenType.idToken,
        scope: String? = nil
    ) async throws -> OAuthToken {
        try await token(grantType: OAuthGrantType.tokenExchange, clientId: clientId, parameters: [
            ("subject_token", subjectToken), ("subject_token_type", subjectTokenType),
            ("project", project), ("scope", scope),
        ])
    }

    /// RFC 7523 `jwt-bearer`: exchange an enterprise IdP's ID-JAG assertion (only on servers with an MCP resource id).
    public func jwtBearer(
        assertion: String,
        clientId: String,
        project: String? = nil,
        resource: String? = nil
    ) async throws -> OAuthToken {
        try await token(grantType: OAuthGrantType.jwtBearer, clientId: clientId, parameters: [
            ("assertion", assertion), ("project", project), ("resource", resource),
        ])
    }

    /// `authorization_code` for a code issued by the CP's own `/v1/oauth/authorize` (PKCE verifier when one was used).
    public func authorizationCode(
        code: String,
        clientId: String,
        redirectURI: String,
        codeVerifier: String? = nil
    ) async throws -> OAuthToken {
        try await token(grantType: OAuthGrantType.authorizationCode, clientId: clientId, parameters: [
            ("code", code), ("redirect_uri", redirectURI), ("code_verifier", codeVerifier),
        ])
    }

    /// `refresh_token`. The server keys refresh on (refresh_token, session_id, org_id) and rotates the
    /// refresh token on every call. Use `OAuthClientID.dataPlane` for a session from `POST /v1/tokens`.
    public func refresh(
        refreshToken: String,
        clientId: String,
        sessionId: String,
        orgId: String
    ) async throws -> OAuthToken {
        try await token(grantType: OAuthGrantType.refreshToken, clientId: clientId, parameters: [
            ("refresh_token", refreshToken), ("session_id", sessionId), ("org_id", orgId),
        ])
    }

    /// Start the RFC 8628 device flow: `POST /v1/oauth/device/code`. Only the `cli` client may.
    public func deviceAuthorization(
        clientId: String = OAuthClientID.cli,
        project: String? = nil,
        capabilities: [String]? = nil
    ) async throws -> DeviceAuthorization {
        var fields: [(String, String)] = [("client_id", clientId)]
        if let project { fields.append(("project", project)) }
        if let capabilities, !capabilities.isEmpty { fields.append(("capabilities", capabilities.joined(separator: ","))) }
        return try await http.json(
            "POST", "/v1/oauth/device/code", body: .form(fields), authenticated: false, as: DeviceAuthorization.self
        )
    }

    /// One device-code poll. Throws with `oauthError` set to `authorization_pending`, `slow_down`,
    /// `expired_token` or `access_denied` while not approved.
    public func deviceToken(deviceCode: String, clientId: String = OAuthClientID.cli) async throws -> OAuthToken {
        try await token(grantType: OAuthGrantType.deviceCode, clientId: clientId, parameters: [("device_code", deviceCode)])
    }

    /// Poll until the user approves, honouring `interval` and adding 5 seconds on each `slow_down`.
    /// Throws `.authentication` on denial or expiry.
    public func pollDeviceToken(
        _ authorization: DeviceAuthorization,
        clientId: String = OAuthClientID.cli,
        now: @Sendable () -> Date = { Date() },
        sleep: @Sendable (TimeInterval) async throws -> Void = { try await Backoff.sleep($0) }
    ) async throws -> OAuthToken {
        var interval = TimeInterval(max(1, authorization.interval ?? 5))
        let deadline = now().addingTimeInterval(TimeInterval(authorization.expiresIn))
        while true {
            try await sleep(interval)
            do {
                return try await deviceToken(deviceCode: authorization.deviceCode, clientId: clientId)
            } catch let error as IntrospectionError {
                switch error.oauthError {
                case "authorization_pending": break
                case "slow_down": interval += 5
                case "access_denied", "expired_token":
                    throw IntrospectionError(
                        kind: .authentication,
                        message: error.oauthErrorDescription ?? error.message,
                        status: error.status, code: error.oauthError,
                        requestId: error.requestId, body: error.body, underlying: error
                    )
                default: throw error
                }
            }
            if now().addingTimeInterval(interval) > deadline {
                throw IntrospectionError(kind: .authentication, message: "The device code expired before it was approved", code: "expired_token")
            }
        }
    }

    // MARK: Hosted login (primary)

    /// The CP authorize URL for a customer `spa` Application's hosted login:
    /// `GET /v1/oauth/authorize`. A browser without a CP session is sent through
    /// the platform's OIDC login (Zitadel) and comes back to `redirectURI` with a code.
    public func authorizeURL(
        clientID: String,
        redirectURI: String,
        project: String?,
        scope: String = "*",
        state: String,
        codeChallenge: String,
        codeChallengeMethod: String = "S256"
    ) -> URL {
        var query = Query()
        query.add("client_id", clientID)
        query.add("redirect_uri", redirectURI)
        query.add("response_type", "code")
        query.add("state", state)
        query.add("scope", scope)
        query.add("project", project)
        query.add("code_challenge", codeChallenge)
        query.add("code_challenge_method", codeChallengeMethod)
        return http.url("/v1/oauth/authorize", query: query)
    }

    /// Start a hosted login: fresh PKCE and `state`, and the URL to open in a browser.
    /// Keep the returned value until the callback arrives.
    public func hostedLogin(
        clientID: String,
        redirectURI: String,
        project: String?,
        scope: String = "*",
        pkce: PKCE = PKCE(),
        state: String = PKCE.randomURLSafeString()
    ) -> HostedLoginRequest {
        HostedLoginRequest(
            url: authorizeURL(
                clientID: clientID, redirectURI: redirectURI, project: project, scope: scope,
                state: state, codeChallenge: pkce.challenge, codeChallengeMethod: pkce.method
            ),
            state: state, pkce: pkce, clientID: clientID, redirectURI: redirectURI, project: project
        )
    }

    /// Exchange a hosted-login code at `POST /v1/oauth/token` (`authorization_code` + PKCE).
    /// The response carries `refresh_token`, `session_id`, `org_id` and `dp_url`.
    public func exchangeCode(
        code: String,
        clientID: String,
        redirectURI: String,
        codeVerifier: String
    ) async throws -> OAuthToken {
        try await authorizationCode(code: code, clientId: clientID, redirectURI: redirectURI, codeVerifier: codeVerifier)
    }

    /// Finish a hosted login: check the callback's `state` and `error`, then exchange its code.
    public func completeHostedLogin(_ request: HostedLoginRequest, callbackURL: URL) async throws -> OAuthToken {
        let code = try Self.parseCallback(callbackURL).authorizationCode(expectedState: request.state)
        return try await exchangeCode(
            code: code, clientID: request.clientID, redirectURI: request.redirectURI, codeVerifier: request.pkce.verifier
        )
    }

    /// Read `code`, `state` and `error` from the redirect the authorize endpoint sent back.
    public static func parseCallback(_ url: URL) -> OIDCCallback {
        OIDC.parseCallback(url)
    }

    /// Mint a Data Plane token for a project: `POST /v1/tokens`.
    ///
    /// Pass `bearer` to authenticate with a token other than the client's own credentials,
    /// for example a Zitadel access token straight from an OIDC login.
    public func mintDataPlaneToken(_ request: DataPlaneTokenRequest, bearer: String? = nil) async throws -> DataPlaneToken {
        var headers: [String: String] = [:]
        if let bearer { headers["Authorization"] = "Bearer \(bearer)" }
        return try await http.json(
            "POST", "/v1/tokens", body: try .encode(request), headers: headers,
            authenticated: bearer == nil, as: DataPlaneToken.self
        )
    }

    /// Turn an OIDC (Zitadel) access token into a refreshable Data Plane session for `project`.
    public func dataPlaneSession(
        oidcAccessToken: String,
        project: String,
        environment: String? = nil
    ) async throws -> SessionToken {
        let minted = try await mintDataPlaneToken(
            DataPlaneTokenRequest(project: project, includeRefreshToken: true, environment: environment),
            bearer: oidcAccessToken
        )
        return SessionToken(dataPlaneToken: minted)
    }

    /// Revoke a session: `POST /v1/oauth/revoke`. Succeeds even if it was already gone.
    public func revoke(sessionId: String, orgId: String, clientId: String = OAuthClientID.dataPlane) async throws {
        _ = try await http.json(
            "POST", "/v1/oauth/revoke",
            body: .form([("client_id", clientId), ("session_id", sessionId), ("org_id", orgId)]),
            authenticated: false, as: RevokeResponse.self
        )
    }
}

extension IntrospectionClient {
    /// Control Plane authentication endpoints.
    public var auth: AuthAPI { AuthAPI(http: controlPlane) }

    /// Mint a service-account token with `client_credentials` and build a client from it.
    ///
    /// The Data Plane URL defaults to the `dp_url` the token endpoint returns. The token is
    /// re-minted automatically shortly before it expires and after a 401.
    public static func fromServiceAccount(
        clientId: String,
        clientSecret: String,
        project: String,
        scope: String? = nil,
        controlPlaneURL: URL = AuthAPI.defaultControlPlaneURL,
        dataPlaneURL: URL? = nil,
        transport: any HTTPTransport = URLSessionTransport(),
        options: HTTPClient.Options = HTTPClient.Options()
    ) async throws -> IntrospectionClient {
        let auth = AuthAPI(controlPlaneURL: controlPlaneURL, transport: transport, options: options)
        let first = try await auth.clientCredentials(clientId: clientId, clientSecret: clientSecret, project: project, scope: scope)
        let credentials = SessionCredentials(token: SessionToken(oauth: first)) { _ in
            let next = try await auth.clientCredentials(clientId: clientId, clientSecret: clientSecret, project: project, scope: scope)
            return SessionToken(oauth: next)
        }
        return IntrospectionClient(configuration: .init(
            controlPlaneURL: controlPlaneURL,
            dataPlaneURL: dataPlaneURL ?? first.dpUrl.flatMap(URL.init(string:)),
            controlPlaneCredentials: credentials,
            transport: transport,
            options: options
        ))
    }
}

/// A pending hosted login: the URL to open plus what the callback step needs.
/// Persist it (it is `Codable`) if the app can be suspended mid-login.
public struct HostedLoginRequest: Codable, Sendable, Hashable {
    public let url: URL
    public let state: String
    public let codeVerifier: String
    public let clientID: String
    public let redirectURI: String
    public let project: String?

    public init(url: URL, state: String, pkce: PKCE, clientID: String, redirectURI: String, project: String?) {
        self.url = url
        self.state = state
        codeVerifier = pkce.verifier
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.project = project
    }

    /// The PKCE pair, rebuilt from the stored verifier.
    public var pkce: PKCE {
        (try? PKCE(verifier: codeVerifier)) ?? PKCE(uncheckedVerifier: codeVerifier)
    }
}

// MARK: Generic OIDC (external IdP)

/// OpenID Provider metadata from `/.well-known/openid-configuration`.
public struct OIDCProviderMetadata: Codable, Sendable, Hashable {
    public let issuer: String?
    public let authorizationEndpoint: String?
    public let tokenEndpoint: String?
    public let userinfoEndpoint: String?
    public let jwksUri: String?
    public let revocationEndpoint: String?
    public let endSessionEndpoint: String?
    public let deviceAuthorizationEndpoint: String?
    public let scopesSupported: [String]?
    public let codeChallengeMethodsSupported: [String]?

    enum CodingKeys: String, CodingKey {
        case issuer
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case userinfoEndpoint = "userinfo_endpoint"
        case jwksUri = "jwks_uri"
        case revocationEndpoint = "revocation_endpoint"
        case endSessionEndpoint = "end_session_endpoint"
        case deviceAuthorizationEndpoint = "device_authorization_endpoint"
        case scopesSupported = "scopes_supported"
        case codeChallengeMethodsSupported = "code_challenge_methods_supported"
    }
}

/// A prepared authorization request: open `url`, keep the rest to finish the login.
public struct OIDCAuthorizationRequest: Sendable, Hashable {
    public let url: URL
    public let state: String
    public let nonce: String
    public let pkce: PKCE
    public let redirectURI: String
    public let clientId: String
}

/// The parameters an IdP redirected back with (query or fragment).
public struct OIDCCallback: Sendable, Hashable {
    public let code: String?
    public let state: String?
    public let error: String?
    public let errorDescription: String?
    /// RFC 9207 issuer identifier, when the IdP sends one.
    public let issuer: String?

    /// The authorization code, after checking `state` and the absence of an `error`.
    public func authorizationCode(expectedState: String) throws -> String {
        if let error {
            throw IntrospectionError(kind: .authentication, message: errorDescription ?? error, code: error)
        }
        guard state == expectedState else {
            throw IntrospectionError(kind: .authentication, message: "OAuth callback state does not match the request", code: "invalid_state")
        }
        guard let code, !code.isEmpty else {
            throw IntrospectionError(kind: .authentication, message: "OAuth callback carries no code", code: "invalid_request")
        }
        return code
    }
}

/// Authorization Code + PKCE helpers for an external OpenID provider such as Zitadel.
public enum OIDC {
    /// Fetch `{issuer}/.well-known/openid-configuration`.
    public static func discover(issuer: URL, transport: any HTTPTransport = URLSessionTransport()) async throws -> OIDCProviderMetadata {
        var base = issuer.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + "/.well-known/openid-configuration") else {
            throw IntrospectionError(kind: .invalidRequest, message: "Invalid issuer URL")
        }
        let response = try await send(HTTPRequest(method: "GET", url: url, headers: ["Accept": "application/json"]), transport)
        return try HTTPClient.decode(OIDCProviderMetadata.self, from: response)
    }

    /// Build an authorization URL with fresh PKCE (S256), `state` and `nonce`.
    public static func authorizationRequest(
        authorizationEndpoint: URL,
        clientId: String,
        redirectURI: String,
        scopes: [String] = ["openid", "profile", "email", "offline_access"],
        additionalParameters: [(String, String)] = [],
        pkce: PKCE = PKCE(),
        state: String = PKCE.randomURLSafeString(),
        nonce: String = PKCE.randomURLSafeString()
    ) -> OIDCAuthorizationRequest {
        var components = URLComponents(url: authorizationEndpoint, resolvingAgainstBaseURL: false)
            ?? URLComponents()
        var items = components.queryItems ?? []
        items += [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: pkce.method),
        ]
        items += additionalParameters.map { URLQueryItem(name: $0.0, value: $0.1) }
        components.percentEncodedQuery = items
            .map { "\(formEncode($0.name))=\(formEncode($0.value ?? "").replacingOccurrences(of: "+", with: "%20"))" }
            .joined(separator: "&")
        return OIDCAuthorizationRequest(
            url: components.url ?? authorizationEndpoint,
            state: state, nonce: nonce, pkce: pkce, redirectURI: redirectURI, clientId: clientId
        )
    }

    /// Read `code`, `state`, `error`, `error_description` and `iss` from a redirect URL.
    public static func parseCallback(_ url: URL) -> OIDCCallback {
        var values: [String: String] = [:]
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let fragment = components?.percentEncodedFragment {
            var parsed = URLComponents()
            parsed.percentEncodedQuery = fragment
            for item in parsed.queryItems ?? [] { values[item.name] = item.value }
        }
        for item in components?.queryItems ?? [] { values[item.name] = item.value }
        return OIDCCallback(
            code: values["code"], state: values["state"], error: values["error"],
            errorDescription: values["error_description"], issuer: values["iss"]
        )
    }

    /// Exchange an authorization code at an arbitrary token endpoint (form-encoded).
    public static func exchangeCode(
        tokenEndpoint: URL,
        code: String,
        redirectURI: String,
        clientId: String,
        codeVerifier: String,
        clientSecret: String? = nil,
        transport: any HTTPTransport = URLSessionTransport()
    ) async throws -> OAuthToken {
        var fields: [(String, String)] = [
            ("grant_type", OAuthGrantType.authorizationCode), ("code", code), ("redirect_uri", redirectURI),
            ("client_id", clientId), ("code_verifier", codeVerifier),
        ]
        if let clientSecret { fields.append(("client_secret", clientSecret)) }
        return try await postToken(tokenEndpoint, fields, transport)
    }

    /// Finish a login started with `authorizationRequest`: check the callback and exchange its code.
    public static func completeAuthorization(
        _ request: OIDCAuthorizationRequest,
        callbackURL: URL,
        tokenEndpoint: URL,
        clientSecret: String? = nil,
        transport: any HTTPTransport = URLSessionTransport()
    ) async throws -> OAuthToken {
        let code = try parseCallback(callbackURL).authorizationCode(expectedState: request.state)
        return try await exchangeCode(
            tokenEndpoint: tokenEndpoint, code: code, redirectURI: request.redirectURI,
            clientId: request.clientId, codeVerifier: request.pkce.verifier,
            clientSecret: clientSecret, transport: transport
        )
    }

    /// Refresh at an arbitrary token endpoint.
    public static func refresh(
        tokenEndpoint: URL,
        refreshToken: String,
        clientId: String,
        scope: String? = nil,
        clientSecret: String? = nil,
        transport: any HTTPTransport = URLSessionTransport()
    ) async throws -> OAuthToken {
        var fields: [(String, String)] = [
            ("grant_type", OAuthGrantType.refreshToken), ("refresh_token", refreshToken), ("client_id", clientId),
        ]
        if let scope { fields.append(("scope", scope)) }
        if let clientSecret { fields.append(("client_secret", clientSecret)) }
        return try await postToken(tokenEndpoint, fields, transport)
    }

    static func postToken(_ url: URL, _ fields: [(String, String)], _ transport: any HTTPTransport) async throws -> OAuthToken {
        let (body, contentType) = RequestBody.form(fields).encoded()
        var headers = ["Accept": "application/json"]
        if let contentType { headers["Content-Type"] = contentType }
        let response = try await send(HTTPRequest(method: "POST", url: url, headers: headers, body: body), transport)
        return try HTTPClient.decode(OAuthToken.self, from: response)
    }

    private static func send(_ request: HTTPRequest, _ transport: any HTTPTransport) async throws -> HTTPResponse {
        let response: HTTPResponse
        do {
            response = try await transport.send(request)
        } catch let error as IntrospectionError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw IntrospectionError(kind: .network, message: error.localizedDescription, underlying: error)
        }
        guard response.isSuccess else {
            throw IntrospectionError.fromResponse(status: response.status, headers: response.headers, body: response.body)
        }
        return response
    }
}
