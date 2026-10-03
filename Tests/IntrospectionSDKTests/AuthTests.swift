import Foundation
import Testing

@testable import IntrospectionSDK

private func makeJWT(_ claims: JSONObject) -> String {
    let header = OAuthBase64URL.encode(Data(#"{"alg":"RS256","typ":"JWT"}"#.utf8))
    let payload = OAuthBase64URL.encode((try? JSONCoding.encoder.encode(claims)) ?? Data())
    return "\(header).\(payload).c2lnbmF0dXJl"
}

private func form(_ recorded: MockTransport.Recorded?) -> [String: String] {
    var result: [String: String] = [:]
    for pair in (recorded?.bodyString ?? "").split(separator: "&") {
        let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
        let decode = { (text: String) in text.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? text }
        result[decode(parts[0])] = parts.count > 1 ? decode(parts[1]) : ""
    }
    return result
}

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
    func advance(_ seconds: TimeInterval) {
        lock.lock()
        value = value.addingTimeInterval(seconds)
        lock.unlock()
    }
}

private actor Counter {
    private(set) var value = 0
    private(set) var tokens: [SessionToken] = []
    func increment() -> Int {
        value += 1
        return value
    }
    func record(_ token: SessionToken) { tokens.append(token) }
}

private let tokenJSON = #"{"access_token":"AT","token_type":"Bearer","expires_in":900,"scope":"*"}"#

@Suite struct AuthTests {
    // MARK: Crypto

    @Test func pkceMatchesRFC7636AppendixB() throws {
        let pkce = try PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        #expect(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(pkce.method == "S256")
    }

    @Test func generatedPKCEIsValidAndRandom() throws {
        let first = PKCE()
        let second = PKCE()
        #expect(first.verifier.count == 64)
        #expect(first.verifier != second.verifier)
        #expect(throws: Never.self) { try PKCE(verifier: first.verifier) }
        #expect(PKCE(length: 10).verifier.count == 43)
        #expect(PKCE(length: 500).verifier.count == 128)
        #expect(!first.challenge.contains("="))
        #expect(throws: (any Error).self) { try PKCE(verifier: "short") }
        #expect(throws: (any Error).self) { try PKCE(verifier: String(repeating: "a", count: 42) + "!") }
        #expect(!PKCE.randomURLSafeString().contains(where: { "+/=".contains($0) }))
    }

    // MARK: JWT

    @Test func jwtClaimsDecodeWithoutVerification() throws {
        let token = makeJWT([
            "exp": 1_900_000_000, "iat": 1_899_999_100, "jti": "sess-1", "org_id": "org-1",
            "project_id": "proj-1", "member_id": "mem-1", "member_type": "business", "org_role": "admin",
            "aud": "https://api.gcp01.example.dev", "scope": "*", "type": "access_token",
        ])
        let claims = try JWTClaims(token: token)
        #expect(claims.jti == "sess-1")
        #expect(claims.orgId == "org-1")
        #expect(claims.projectId == "proj-1")
        #expect(claims.memberType == "business")
        #expect(claims.orgRole == "admin")
        #expect(claims.audience == ["https://api.gcp01.example.dev"])
        #expect(claims.expiresAt == Date(timeIntervalSince1970: 1_900_000_000))
        #expect(claims.tokenType == "access_token")
        #expect(throws: (any Error).self) { try JWTClaims(token: "not-a-jwt") }
        #expect(try JWTClaims(token: makeJWT(["aud": ["a", "b"]])).audience == ["a", "b"])
    }

    // MARK: Token models

    @Test func oauthTokenDecodesKnownAndExtraFields() throws {
        let json = #"""
            {"access_token":"AT","token_type":"Bearer","expires_in":900,"refresh_token":"RT","scope":"*",
             "session_id":"sess","org_id":"org","project_id":"proj","dp_url":"https://api.dp.test",
             "cp_url":"https://cp.test","platform_url":"https://app.test","member_id":"m","member_name":"Ada",
             "act":{"sub":"agent","type":"agent"},"git_url":null,"novel":{"x":1}}
            """#
        let token = try JSONCoding.decoder.decode(OAuthToken.self, from: Data(json.utf8))
        #expect(token.accessToken == "AT")
        #expect(token.expiresIn == 900)
        #expect(token.refreshToken == "RT")
        #expect(token.sessionId == "sess")
        #expect(token.dpUrl == "https://api.dp.test")
        #expect(token.memberName == "Ada")
        #expect(token.act?["type"] == "agent")
        #expect(token.gitUrl == nil)
        #expect(token.extra == ["novel": ["x": 1]])
        let roundTrip = try JSONCoding.decoder.decode(OAuthToken.self, from: JSONCoding.encoder.encode(token))
        #expect(roundTrip == token)
        #expect(token.expiresAt(receivedAt: Date(timeIntervalSince1970: 0)) == Date(timeIntervalSince1970: 900))
    }

    // MARK: Grants

    @Test func clientCredentialsFormBody() async throws {
        let transport = MockTransport(json: #"{"access_token":"AT","token_type":"Bearer","expires_in":900,"dp_url":"https://api.dp"}"#)
        let token = try await makeClient(transport).auth.clientCredentials(
            clientId: "intro_app_1", clientSecret: "intro_sk_ x", project: "my-proj", scope: "tasks:read tasks:write"
        )
        #expect(token.dpUrl == "https://api.dp")
        let request = try #require(transport.last)
        #expect(request.request.method == "POST")
        #expect(request.path == "/v1/oauth/token")
        #expect(request.request.headers["Content-Type"] == "application/x-www-form-urlencoded")
        #expect(request.request.headers["Authorization"] == nil)
        #expect(
            form(request) == [
                "grant_type": "client_credentials", "client_id": "intro_app_1", "client_secret": "intro_sk_ x",
                "project": "my-proj", "scope": "tasks:read tasks:write",
            ])
    }

    @Test func tokenExchangeAndJWTBearerFormBodies() async throws {
        let transport = MockTransport(json: tokenJSON)
        let auth = makeClient(transport).auth
        _ = try await auth.tokenExchange(subjectToken: "IDT", clientId: "intro_app_f", project: "p")
        #expect(
            form(transport.last) == [
                "grant_type": "urn:ietf:params:oauth:grant-type:token-exchange", "client_id": "intro_app_f",
                "subject_token": "IDT", "subject_token_type": "urn:ietf:params:oauth:token-type:id_token", "project": "p",
            ])
        _ = try await auth.tokenExchange(subjectToken: "LOGIN", clientId: "cli", subjectTokenType: OAuthTokenType.accessToken)
        #expect(form(transport.last)["subject_token_type"] == "urn:ietf:params:oauth:token-type:access_token")
        #expect(form(transport.last)["project"] == nil)
        _ = try await auth.jwtBearer(assertion: "IDJAG", clientId: "c", project: "p", resource: "https://mcp")
        #expect(
            form(transport.last) == [
                "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer", "client_id": "c",
                "assertion": "IDJAG", "project": "p", "resource": "https://mcp",
            ])
    }

    @Test func authorizationCodeRefreshAndRevokeFormBodies() async throws {
        let transport = MockTransport { request, _ in
            request.url.path == "/v1/oauth/revoke" ? .response(.json(#"{"status":"revoked"}"#)) : .response(.json(tokenJSON))
        }
        let auth = makeClient(transport).auth
        _ = try await auth.exchangeCode(code: "C", clientID: "spa_1", redirectURI: "app://cb", codeVerifier: "V")
        #expect(
            form(transport.last) == [
                "grant_type": "authorization_code", "client_id": "spa_1", "code": "C",
                "redirect_uri": "app://cb", "code_verifier": "V",
            ])
        _ = try await auth.refresh(refreshToken: "RT", clientId: "dataplane", sessionId: "S", orgId: "O")
        #expect(
            form(transport.last) == [
                "grant_type": "refresh_token", "client_id": "dataplane", "refresh_token": "RT",
                "session_id": "S", "org_id": "O",
            ])
        try await auth.revoke(sessionId: "S", orgId: "O")
        #expect(transport.last?.path == "/v1/oauth/revoke")
        #expect(form(transport.last) == ["client_id": "dataplane", "session_id": "S", "org_id": "O"])
    }

    @Test func tokenEndpointErrorExposesOAuthCode() async throws {
        let transport = MockTransport(status: 400, json: #"{"error":"invalid_grant","error_description":"please re-authorize"}"#)
        let error = try await #require(throws: IntrospectionError.self) {
            try await makeClient(transport).auth.refresh(refreshToken: "RT", clientId: "x", sessionId: "S", orgId: "O")
        }
        #expect(error.kind == .validation)
        #expect(error.oauthError == "invalid_grant")
        #expect(error.oauthErrorDescription == "please re-authorize")
    }

    @Test func mintDataPlaneTokenWithExplicitBearer() async throws {
        let jwt = makeJWT(["jti": "sess-9", "org_id": "org-9", "aud": "https://api.gcp01.example.dev"])
        let transport = MockTransport(
            json: """
                {"access_token":"\(jwt)","token_type":"bearer","expires_at":"2026-10-03T12:00:00Z",
                 "project_id":"proj","org_id":"org-9","refresh_token":"RT"}
                """)
        let auth = makeClient(transport).auth
        let session = try await auth.dataPlaneSession(oidcAccessToken: "ZITADEL", project: "proj", environment: "staging")
        let request = try #require(transport.last)
        #expect(request.path == "/v1/tokens")
        #expect(request.request.headers["Authorization"] == "Bearer ZITADEL")
        #expect(request.json == ["project": "proj", "include_refresh_token": true, "environment": "staging"])
        #expect(session.sessionId == "sess-9")
        #expect(session.orgId == "org-9")
        #expect(session.refreshToken == "RT")
        #expect(session.dataPlaneURL == "https://api.gcp01.example.dev")
        #expect(session.expiresAt == ISO8601.parse("2026-10-03T12:00:00Z"))

        _ = try await auth.mintDataPlaneToken(DataPlaneTokenRequest(project: "proj", expiresMinutes: 30))
        #expect(transport.last?.request.headers["Authorization"] == "Bearer cp-token")
        #expect(transport.last?.json == ["project": "proj", "expires_minutes": 30])
    }

    // MARK: Device flow

    @Test func deviceAuthorizationRequest() async throws {
        let transport = MockTransport(
            json: #"""
                {"device_code":"DC","user_code":"ABCD-EFGH","verification_uri":"https://app/activate",
                 "verification_uri_complete":"https://app/activate?user_code=ABCD-EFGH","expires_in":600,"interval":5}
                """#)
        let device = try await makeClient(transport).auth.deviceAuthorization(project: "p", capabilities: ["runtimes", "reviews"])
        #expect(device.userCode == "ABCD-EFGH")
        #expect(device.interval == 5)
        #expect(transport.last?.path == "/v1/oauth/device/code")
        #expect(form(transport.last) == ["client_id": "cli", "project": "p", "capabilities": "runtimes,reviews"])
    }

    @Test func devicePollingHandlesPendingAndSlowDown() async throws {
        let replies = [
            #"{"error":"authorization_pending","error_description":"pending"}"#,
            #"{"error":"slow_down","error_description":"slow"}"#,
            #"{"error":"authorization_pending"}"#,
        ]
        let transport = MockTransport { _, index in
            index < replies.count ? .response(.json(replies[index], status: 400)) : .response(.json(tokenJSON))
        }
        let sleeps = Counter()
        let slept = LockedArray()
        let device = DeviceAuthorization(deviceCode: "DC", userCode: "U", verificationUri: "v", expiresIn: 600, interval: 5)
        let token = try await makeClient(transport).auth.pollDeviceToken(
            device,
            sleep: { seconds in
                slept.append(seconds)
                _ = await sleeps.increment()
            })
        #expect(token.accessToken == "AT")
        #expect(slept.values == [5, 5, 10, 10])
        #expect(transport.requests.count == 4)
        #expect(
            form(transport.last) == [
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code", "client_id": "cli", "device_code": "DC",
            ])
    }

    @Test func devicePollingDeniedIsAuthenticationError() async throws {
        let transport = MockTransport(status: 400, json: #"{"error":"access_denied","error_description":"denied"}"#)
        let device = DeviceAuthorization(deviceCode: "DC", userCode: "U", verificationUri: "v", expiresIn: 600, interval: 1)
        let error = try await #require(throws: IntrospectionError.self) {
            try await makeClient(transport).auth.pollDeviceToken(device, sleep: { _ in })
        }
        #expect(error.kind == .authentication)
        #expect(error.code == "access_denied")
    }

    @Test func devicePollingStopsAtExpiry() async throws {
        let transport = MockTransport(status: 400, json: #"{"error":"authorization_pending"}"#)
        let clock = Clock(Date(timeIntervalSince1970: 0))
        let device = DeviceAuthorization(deviceCode: "DC", userCode: "U", verificationUri: "v", expiresIn: 12, interval: 5)
        let error = try await #require(throws: IntrospectionError.self) {
            try await makeClient(transport).auth.pollDeviceToken(device, now: { clock.now }, sleep: { clock.advance($0) })
        }
        #expect(error.kind == .authentication)
        #expect(error.code == "expired_token")
        #expect(transport.requests.count == 2)
    }

    // MARK: Hosted login and OIDC

    @Test func hostedLoginAuthorizeURL() throws {
        let auth = AuthAPI(controlPlaneURL: URL(string: "https://cp.test")!, transport: MockTransport(json: "{}"))
        let pkce = try PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        let login = auth.hostedLogin(clientID: "spa_1", redirectURI: "myapp://callback", project: "proj", pkce: pkce, state: "st")
        let components = try #require(URLComponents(url: login.url, resolvingAgainstBaseURL: false))
        #expect(components.host == "cp.test")
        #expect(components.path == "/v1/oauth/authorize")
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(
            items == [
                "client_id": "spa_1", "redirect_uri": "myapp://callback", "response_type": "code", "state": "st",
                "scope": "*", "project": "proj", "code_challenge": "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
                "code_challenge_method": "S256",
            ])
        #expect(login.pkce == pkce)
        let decoded = try JSONCoding.decoder.decode(HostedLoginRequest.self, from: JSONCoding.encoder.encode(login))
        #expect(decoded == login)
    }

    @Test func completeHostedLoginChecksStateAndExchanges() async throws {
        let transport = MockTransport(
            json: #"""
                {"access_token":"AT","token_type":"Bearer","expires_in":900,"refresh_token":"RT","session_id":"S","org_id":"O","dp_url":"https://api.dp"}
                """#)
        let auth = makeClient(transport).auth
        let login = auth.hostedLogin(clientID: "spa_1", redirectURI: "myapp://callback", project: "proj", state: "good")

        let mismatch = try await #require(throws: IntrospectionError.self) {
            try await auth.completeHostedLogin(login, callbackURL: URL(string: "myapp://callback?code=C&state=evil")!)
        }
        #expect(mismatch.code == "invalid_state")
        let denied = try await #require(throws: IntrospectionError.self) {
            try await auth.completeHostedLogin(login, callbackURL: URL(string: "myapp://callback?error=access_denied&state=good")!)
        }
        #expect(denied.kind == .authentication)
        #expect(denied.code == "access_denied")
        #expect(transport.requests.isEmpty)

        let token = try await auth.completeHostedLogin(login, callbackURL: URL(string: "myapp://callback?code=C%2B1&state=good")!)
        #expect(token.sessionId == "S")
        #expect(
            form(transport.last) == [
                "grant_type": "authorization_code", "client_id": "spa_1", "code": "C+1",
                "redirect_uri": "myapp://callback", "code_verifier": login.codeVerifier,
            ])
    }

    @Test func oidcAuthorizationRequestAndCallbackParsing() throws {
        let request = OIDC.authorizationRequest(
            authorizationEndpoint: URL(string: "https://idp.test/oauth/v2/authorize")!,
            clientId: "zitadel-app", redirectURI: "myapp://cb", additionalParameters: [("prompt", "login")]
        )
        let items = Dictionary(
            uniqueKeysWithValues: (URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
                .map { ($0.name, $0.value ?? "") })
        #expect(items["scope"] == "openid profile email offline_access")
        #expect(items["code_challenge"] == request.pkce.challenge)
        #expect(items["state"] == request.state)
        #expect(items["nonce"] == request.nonce)
        #expect(items["prompt"] == "login")
        #expect(!request.url.absoluteString.contains("+"))

        let fragment = OIDC.parseCallback(URL(string: "myapp://cb#code=abc&state=xyz&iss=https%3A%2F%2Fidp.test")!)
        #expect(fragment.code == "abc")
        #expect(fragment.issuer == "https://idp.test")
        #expect(try fragment.authorizationCode(expectedState: "xyz") == "abc")
    }

    @Test func oidcExchangeAndDiscoveryUseArbitraryEndpoints() async throws {
        let transport = MockTransport { request, _ in
            if request.url.path.hasSuffix("openid-configuration") {
                return .response(
                    .json(
                        #"{"issuer":"https://idp.test","authorization_endpoint":"https://idp.test/oauth/v2/authorize","token_endpoint":"https://idp.test/oauth/v2/token","code_challenge_methods_supported":["S256"]}"#
                    ))
            }
            return .response(
                .json(#"{"access_token":"ZAT","token_type":"Bearer","expires_in":43199,"id_token":"IDT","refresh_token":"ZRT"}"#))
        }
        let metadata = try await OIDC.discover(issuer: URL(string: "https://idp.test/")!, transport: transport)
        #expect(transport.last?.request.url.absoluteString == "https://idp.test/.well-known/openid-configuration")
        #expect(metadata.tokenEndpoint == "https://idp.test/oauth/v2/token")
        let token = try await OIDC.exchangeCode(
            tokenEndpoint: URL(string: "https://idp.test/oauth/v2/token")!, code: "C", redirectURI: "myapp://cb",
            clientId: "zitadel-app", codeVerifier: "V", transport: transport
        )
        #expect(token.idToken == "IDT")
        #expect(transport.last?.request.url.absoluteString == "https://idp.test/oauth/v2/token")
        #expect(
            form(transport.last) == [
                "grant_type": "authorization_code", "code": "C", "redirect_uri": "myapp://cb",
                "client_id": "zitadel-app", "code_verifier": "V",
            ])
    }

    // MARK: SessionCredentials

    @Test func concurrentCallersShareOneRefresh() async throws {
        let counter = Counter()
        let credentials = SessionCredentials(token: SessionToken(accessToken: "old", expiresAt: .distantPast)) { _ in
            let count = await counter.increment()
            try await Task.sleep(nanoseconds: 50_000_000)
            return SessionToken(accessToken: "new-\(count)", expiresAt: Date().addingTimeInterval(3600))
        }
        let headers = try await withThrowingTaskGroup(of: String?.self) { group in
            for _ in 0..<25 { group.addTask { try await credentials.authorization() } }
            var all: [String?] = []
            for try await header in group { all.append(header) }
            return all
        }
        let refreshes = await counter.value
        #expect(refreshes == 1)
        #expect(Set(headers) == ["Bearer new-1"])
    }

    @Test func proactiveRefreshHonoursLeeway() async throws {
        let clock = Clock(Date(timeIntervalSince1970: 1000))
        let counter = Counter()
        let credentials = SessionCredentials(
            token: SessionToken(accessToken: "A", expiresAt: Date(timeIntervalSince1970: 1200)),
            leeway: 60, now: { clock.now },
            onTokenUpdate: { await counter.record($0) }
        ) { _ in
            SessionToken(accessToken: "B", expiresAt: Date(timeIntervalSince1970: 5000))
        }
        let early = try await credentials.authorization()
        #expect(early == "Bearer A")
        clock.advance(150)
        let late = try await credentials.authorization()
        #expect(late == "Bearer B")
        let recorded = await counter.tokens
        #expect(recorded.map(\.accessToken) == ["B"])
    }

    @Test func unauthorizedTriggersRefreshAndRetry() async throws {
        let credentials = SessionCredentials(token: SessionToken(accessToken: "stale", expiresAt: .distantFuture)) { _ in
            SessionToken(accessToken: "fresh", expiresAt: .distantFuture)
        }
        let transport = MockTransport { request, _ in
            request.headers["Authorization"] == "Bearer fresh"
                ? .response(.json(#"{"id":"a1","name":"n","enabled":true,"trigger_type":"manual","can_manage":true,"tags":[]}"#))
                : .response(.json(#"{"detail":"expired"}"#, status: 401))
        }
        let client = IntrospectionClient(
            configuration: .init(
                controlPlaneURL: URL(string: "https://cp.test")!, dataPlaneURL: URL(string: "https://dp.test")!,
                dataPlaneCredentials: credentials, transport: transport
            ))
        let automation = try await client.automations.get("a1")
        #expect(automation.id == "a1")
        #expect(transport.requests.map { $0.request.headers["Authorization"] } == ["Bearer stale", "Bearer fresh"])
    }

    @Test func refreshFailureIsAuthentication() async throws {
        let credentials = SessionCredentials(token: SessionToken(accessToken: "A", expiresAt: .distantPast)) { _ in
            throw IntrospectionError(kind: .network, message: "offline")
        }
        let error = try await #require(throws: IntrospectionError.self) { try await credentials.authorization() }
        #expect(error.kind == .authentication)
    }

    @Test func platformSessionRefreshesThroughCPGrant() async throws {
        let rotated = makeJWT(["jti": "S", "org_id": "O", "exp": 4_000_000_000])
        let transport = MockTransport(
            json: """
                {"access_token":"\(rotated)","token_type":"Bearer","expires_in":900,"refresh_token":"RT2","session_id":"S","org_id":"O"}
                """)
        let login = OAuthToken(
            accessToken: makeJWT(["jti": "S", "org_id": "O"]), expiresIn: 900, refreshToken: "RT1", sessionId: "S", dpUrl: "https://api.dp")
        let updates = Counter()
        let credentials = SessionCredentials.platformSession(
            token: login, clientID: "spa_1", controlPlane: makeClient(transport).auth,
            onTokenUpdate: { await updates.record($0) }
        )
        try await credentials.refresh()
        #expect(
            form(transport.last) == [
                "grant_type": "refresh_token", "client_id": "spa_1", "refresh_token": "RT1", "session_id": "S", "org_id": "O",
            ])
        let stored = await updates.tokens
        #expect(stored.first?.refreshToken == "RT2")
        #expect(stored.first?.dataPlaneURL == "https://api.dp")
        let header = try await credentials.authorization()
        #expect(header == "Bearer \(rotated)")
    }

    @Test func dataPlaneSessionWithoutRefreshTokenFails() async throws {
        let credentials = SessionCredentials.dataPlaneSession(
            token: SessionToken(accessToken: "A", expiresAt: .distantPast),
            controlPlane: makeClient(MockTransport(json: tokenJSON)).auth
        )
        let error = try await #require(throws: IntrospectionError.self) { try await credentials.authorization() }
        #expect(error.kind == .authentication)
    }

    @Test func tokenExchangeCredentialsReExchangeAndCoalesce() async throws {
        let transport = MockTransport { _, index in
            .response(
                .json(#"{"access_token":"DP\#(index)","token_type":"Bearer","expires_in":900,"scope":"*","dp_url":"https://api.dp"}"#))
        }
        let subjects = Counter()
        let credentials = SessionCredentials.tokenExchange(
            subjectToken: { "supabase-\(await subjects.increment())" },
            clientID: "intro_app_jwks", project: "proj", controlPlane: makeClient(transport).auth
        )
        let headers = try await withThrowingTaskGroup(of: String?.self) { group in
            for _ in 0..<10 { group.addTask { try await credentials.authorization() } }
            var all: [String?] = []
            for try await header in group { all.append(header) }
            return all
        }
        #expect(Set(headers) == ["Bearer DP0"])
        #expect(transport.requests.count == 1)
        #expect(
            form(transport.last) == [
                "grant_type": "urn:ietf:params:oauth:grant-type:token-exchange", "client_id": "intro_app_jwks",
                "subject_token": "supabase-1", "subject_token_type": "urn:ietf:params:oauth:token-type:id_token",
                "project": "proj",
            ])
        let token = await credentials.token
        #expect(token.dataPlaneURL == "https://api.dp")

        try await credentials.refresh()
        #expect(form(transport.last)["subject_token"] == "supabase-2")
        let header = try await credentials.authorization()
        #expect(header == "Bearer DP1")
    }

    @Test func fromServiceAccountUsesReturnedDataPlaneURL() async throws {
        let transport = MockTransport { request, _ in
            request.url.path == "/v1/oauth/token"
                ? .response(.json(#"{"access_token":"SA","token_type":"Bearer","expires_in":900,"dp_url":"https://api.dp.test"}"#))
                : .response(.json(#"{"records":[],"count":0,"next":null}"#))
        }
        let client = try await IntrospectionClient.fromServiceAccount(
            clientId: "intro_app_1", clientSecret: "intro_sk_1", project: "p",
            controlPlaneURL: URL(string: "https://cp.test")!, transport: transport
        )
        #expect(client.dataPlane.baseURL.absoluteString == "https://api.dp.test")
        _ = try await client.automations.list().firstPage()
        #expect(transport.last?.request.url.host == "api.dp.test")
        #expect(transport.last?.request.headers["Authorization"] == "Bearer SA")
    }
}

private final class LockedArray: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [TimeInterval] = []
    func append(_ value: TimeInterval) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
    var values: [TimeInterval] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
