import Foundation
import XCTest

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

private func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined()
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

final class AuthTests: XCTestCase {
    // MARK: Crypto

    func testPureSHA256MatchesNISTVectors() {
        let vectors: [(String, String)] = [
            ("", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
            ("abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
            (
                "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
                "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
            ),
            (
                "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu",
                "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1"
            ),
        ]
        for (input, expected) in vectors {
            XCTAssertEqual(hex(PureSHA256.hash(Data(input.utf8))), expected, input)
            XCTAssertEqual(hex(SHA256Digest.hash(Data(input.utf8))), expected, input)
        }
        let million = Data(repeating: UInt8(ascii: "a"), count: 1_000_000)
        XCTAssertEqual(hex(PureSHA256.hash(million)), "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
    }

    func testPKCEMatchesRFC7636AppendixB() throws {
        let pkce = try PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        XCTAssertEqual(pkce.challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        XCTAssertEqual(pkce.method, "S256")
    }

    func testGeneratedPKCEIsValidAndRandom() throws {
        let first = PKCE()
        let second = PKCE()
        XCTAssertEqual(first.verifier.count, 64)
        XCTAssertNotEqual(first.verifier, second.verifier)
        XCTAssertNoThrow(try PKCE(verifier: first.verifier))
        XCTAssertEqual(PKCE(length: 10).verifier.count, 43)
        XCTAssertEqual(PKCE(length: 500).verifier.count, 128)
        XCTAssertFalse(first.challenge.contains("="))
        XCTAssertThrowsError(try PKCE(verifier: "short"))
        XCTAssertThrowsError(try PKCE(verifier: String(repeating: "a", count: 42) + "!"))
        XCTAssertFalse(PKCE.randomURLSafeString().contains(where: { "+/=".contains($0) }))
    }

    // MARK: JWT

    func testJWTClaimsDecodeWithoutVerification() throws {
        let token = makeJWT([
            "exp": 1_900_000_000, "iat": 1_899_999_100, "jti": "sess-1", "org_id": "org-1",
            "project_id": "proj-1", "member_id": "mem-1", "member_type": "business", "org_role": "admin",
            "aud": "https://api.gcp01.example.dev", "scope": "*", "type": "access_token",
        ])
        let claims = try JWTClaims(token: token)
        XCTAssertEqual(claims.jti, "sess-1")
        XCTAssertEqual(claims.orgId, "org-1")
        XCTAssertEqual(claims.projectId, "proj-1")
        XCTAssertEqual(claims.memberType, "business")
        XCTAssertEqual(claims.orgRole, "admin")
        XCTAssertEqual(claims.audience, ["https://api.gcp01.example.dev"])
        XCTAssertEqual(claims.expiresAt, Date(timeIntervalSince1970: 1_900_000_000))
        XCTAssertEqual(claims.tokenType, "access_token")
        XCTAssertThrowsError(try JWTClaims(token: "not-a-jwt"))
        XCTAssertEqual(try JWTClaims(token: makeJWT(["aud": ["a", "b"]])).audience, ["a", "b"])
    }

    // MARK: Token models

    func testOAuthTokenDecodesKnownAndExtraFields() throws {
        let json = #"""
            {"access_token":"AT","token_type":"Bearer","expires_in":900,"refresh_token":"RT","scope":"*",
             "session_id":"sess","org_id":"org","project_id":"proj","dp_url":"https://api.dp.test",
             "cp_url":"https://cp.test","platform_url":"https://app.test","member_id":"m","member_name":"Ada",
             "act":{"sub":"agent","type":"agent"},"git_url":null,"novel":{"x":1}}
            """#
        let token = try JSONCoding.decoder.decode(OAuthToken.self, from: Data(json.utf8))
        XCTAssertEqual(token.accessToken, "AT")
        XCTAssertEqual(token.expiresIn, 900)
        XCTAssertEqual(token.refreshToken, "RT")
        XCTAssertEqual(token.sessionId, "sess")
        XCTAssertEqual(token.dpUrl, "https://api.dp.test")
        XCTAssertEqual(token.memberName, "Ada")
        XCTAssertEqual(token.act?["type"], "agent")
        XCTAssertNil(token.gitUrl)
        XCTAssertEqual(token.extra, ["novel": ["x": 1]])
        let roundTrip = try JSONCoding.decoder.decode(OAuthToken.self, from: JSONCoding.encoder.encode(token))
        XCTAssertEqual(roundTrip, token)
        XCTAssertEqual(token.expiresAt(receivedAt: Date(timeIntervalSince1970: 0)), Date(timeIntervalSince1970: 900))
    }

    // MARK: Grants

    func testClientCredentialsFormBody() async throws {
        let transport = MockTransport(json: #"{"access_token":"AT","token_type":"Bearer","expires_in":900,"dp_url":"https://api.dp"}"#)
        let token = try await makeClient(transport).auth.clientCredentials(
            clientId: "intro_app_1", clientSecret: "intro_sk_ x", project: "my-proj", scope: "tasks:read tasks:write"
        )
        XCTAssertEqual(token.dpUrl, "https://api.dp")
        let request = try XCTUnwrap(transport.last)
        XCTAssertEqual(request.request.method, "POST")
        XCTAssertEqual(request.path, "/v1/oauth/token")
        XCTAssertEqual(request.request.headers["Content-Type"], "application/x-www-form-urlencoded")
        XCTAssertNil(request.request.headers["Authorization"])
        XCTAssertEqual(
            form(request),
            [
                "grant_type": "client_credentials", "client_id": "intro_app_1", "client_secret": "intro_sk_ x",
                "project": "my-proj", "scope": "tasks:read tasks:write",
            ])
    }

    func testTokenExchangeAndJWTBearerFormBodies() async throws {
        let transport = MockTransport(json: tokenJSON)
        let auth = makeClient(transport).auth
        _ = try await auth.tokenExchange(subjectToken: "IDT", clientId: "intro_app_f", project: "p")
        XCTAssertEqual(
            form(transport.last),
            [
                "grant_type": "urn:ietf:params:oauth:grant-type:token-exchange", "client_id": "intro_app_f",
                "subject_token": "IDT", "subject_token_type": "urn:ietf:params:oauth:token-type:id_token", "project": "p",
            ])
        _ = try await auth.tokenExchange(subjectToken: "LOGIN", clientId: "cli", subjectTokenType: OAuthTokenType.accessToken)
        XCTAssertEqual(form(transport.last)["subject_token_type"], "urn:ietf:params:oauth:token-type:access_token")
        XCTAssertNil(form(transport.last)["project"])
        _ = try await auth.jwtBearer(assertion: "IDJAG", clientId: "c", project: "p", resource: "https://mcp")
        XCTAssertEqual(
            form(transport.last),
            [
                "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer", "client_id": "c",
                "assertion": "IDJAG", "project": "p", "resource": "https://mcp",
            ])
    }

    func testAuthorizationCodeRefreshAndRevokeFormBodies() async throws {
        let transport = MockTransport { request, _ in
            request.url.path == "/v1/oauth/revoke" ? .response(.json(#"{"status":"revoked"}"#)) : .response(.json(tokenJSON))
        }
        let auth = makeClient(transport).auth
        _ = try await auth.exchangeCode(code: "C", clientID: "spa_1", redirectURI: "app://cb", codeVerifier: "V")
        XCTAssertEqual(
            form(transport.last),
            [
                "grant_type": "authorization_code", "client_id": "spa_1", "code": "C",
                "redirect_uri": "app://cb", "code_verifier": "V",
            ])
        _ = try await auth.refresh(refreshToken: "RT", clientId: "dataplane", sessionId: "S", orgId: "O")
        XCTAssertEqual(
            form(transport.last),
            [
                "grant_type": "refresh_token", "client_id": "dataplane", "refresh_token": "RT",
                "session_id": "S", "org_id": "O",
            ])
        try await auth.revoke(sessionId: "S", orgId: "O")
        XCTAssertEqual(transport.last?.path, "/v1/oauth/revoke")
        XCTAssertEqual(form(transport.last), ["client_id": "dataplane", "session_id": "S", "org_id": "O"])
    }

    func testTokenEndpointErrorExposesOAuthCode() async throws {
        let transport = MockTransport(status: 400, json: #"{"error":"invalid_grant","error_description":"please re-authorize"}"#)
        do {
            _ = try await makeClient(transport).auth.refresh(refreshToken: "RT", clientId: "x", sessionId: "S", orgId: "O")
            XCTFail("expected an error")
        } catch let error as IntrospectionError {
            XCTAssertEqual(error.kind, .validation)
            XCTAssertEqual(error.oauthError, "invalid_grant")
            XCTAssertEqual(error.oauthErrorDescription, "please re-authorize")
        }
    }

    func testMintDataPlaneTokenWithExplicitBearer() async throws {
        let jwt = makeJWT(["jti": "sess-9", "org_id": "org-9", "aud": "https://api.gcp01.example.dev"])
        let transport = MockTransport(
            json: """
                {"access_token":"\(jwt)","token_type":"bearer","expires_at":"2026-10-03T12:00:00Z",
                 "project_id":"proj","org_id":"org-9","refresh_token":"RT"}
                """)
        let auth = makeClient(transport).auth
        let session = try await auth.dataPlaneSession(oidcAccessToken: "ZITADEL", project: "proj", environment: "staging")
        let request = try XCTUnwrap(transport.last)
        XCTAssertEqual(request.path, "/v1/tokens")
        XCTAssertEqual(request.request.headers["Authorization"], "Bearer ZITADEL")
        XCTAssertEqual(request.json, ["project": "proj", "include_refresh_token": true, "environment": "staging"])
        XCTAssertEqual(session.sessionId, "sess-9")
        XCTAssertEqual(session.orgId, "org-9")
        XCTAssertEqual(session.refreshToken, "RT")
        XCTAssertEqual(session.dataPlaneURL, "https://api.gcp01.example.dev")
        XCTAssertEqual(session.expiresAt, ISO8601.parse("2026-10-03T12:00:00Z"))

        _ = try await auth.mintDataPlaneToken(DataPlaneTokenRequest(project: "proj", expiresMinutes: 30))
        XCTAssertEqual(transport.last?.request.headers["Authorization"], "Bearer cp-token")
        XCTAssertEqual(transport.last?.json, ["project": "proj", "expires_minutes": 30])
    }

    // MARK: Device flow

    func testDeviceAuthorizationRequest() async throws {
        let transport = MockTransport(
            json: #"""
                {"device_code":"DC","user_code":"ABCD-EFGH","verification_uri":"https://app/activate",
                 "verification_uri_complete":"https://app/activate?user_code=ABCD-EFGH","expires_in":600,"interval":5}
                """#)
        let device = try await makeClient(transport).auth.deviceAuthorization(project: "p", capabilities: ["runtimes", "reviews"])
        XCTAssertEqual(device.userCode, "ABCD-EFGH")
        XCTAssertEqual(device.interval, 5)
        XCTAssertEqual(transport.last?.path, "/v1/oauth/device/code")
        XCTAssertEqual(form(transport.last), ["client_id": "cli", "project": "p", "capabilities": "runtimes,reviews"])
    }

    func testDevicePollingHandlesPendingAndSlowDown() async throws {
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
        XCTAssertEqual(token.accessToken, "AT")
        XCTAssertEqual(slept.values, [5, 5, 10, 10])
        XCTAssertEqual(transport.requests.count, 4)
        XCTAssertEqual(
            form(transport.last),
            [
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code", "client_id": "cli", "device_code": "DC",
            ])
    }

    func testDevicePollingDeniedIsAuthenticationError() async throws {
        let transport = MockTransport(status: 400, json: #"{"error":"access_denied","error_description":"denied"}"#)
        let device = DeviceAuthorization(deviceCode: "DC", userCode: "U", verificationUri: "v", expiresIn: 600, interval: 1)
        do {
            _ = try await makeClient(transport).auth.pollDeviceToken(device, sleep: { _ in })
            XCTFail("expected an error")
        } catch let error as IntrospectionError {
            XCTAssertEqual(error.kind, .authentication)
            XCTAssertEqual(error.code, "access_denied")
        }
    }

    func testDevicePollingStopsAtExpiry() async throws {
        let transport = MockTransport(status: 400, json: #"{"error":"authorization_pending"}"#)
        let clock = Clock(Date(timeIntervalSince1970: 0))
        let device = DeviceAuthorization(deviceCode: "DC", userCode: "U", verificationUri: "v", expiresIn: 12, interval: 5)
        do {
            _ = try await makeClient(transport).auth.pollDeviceToken(device, now: { clock.now }, sleep: { clock.advance($0) })
            XCTFail("expected an error")
        } catch let error as IntrospectionError {
            XCTAssertEqual(error.kind, .authentication)
            XCTAssertEqual(error.code, "expired_token")
        }
        XCTAssertEqual(transport.requests.count, 2)
    }

    // MARK: Hosted login and OIDC

    func testHostedLoginAuthorizeURL() throws {
        let auth = AuthAPI(controlPlaneURL: URL(string: "https://cp.test")!, transport: MockTransport(json: "{}"))
        let pkce = try PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        let login = auth.hostedLogin(clientID: "spa_1", redirectURI: "myapp://callback", project: "proj", pkce: pkce, state: "st")
        let components = try XCTUnwrap(URLComponents(url: login.url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "cp.test")
        XCTAssertEqual(components.path, "/v1/oauth/authorize")
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(
            items,
            [
                "client_id": "spa_1", "redirect_uri": "myapp://callback", "response_type": "code", "state": "st",
                "scope": "*", "project": "proj", "code_challenge": "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
                "code_challenge_method": "S256",
            ])
        XCTAssertEqual(login.pkce, pkce)
        let decoded = try JSONCoding.decoder.decode(HostedLoginRequest.self, from: JSONCoding.encoder.encode(login))
        XCTAssertEqual(decoded, login)
    }

    func testCompleteHostedLoginChecksStateAndExchanges() async throws {
        let transport = MockTransport(
            json: #"""
                {"access_token":"AT","token_type":"Bearer","expires_in":900,"refresh_token":"RT","session_id":"S","org_id":"O","dp_url":"https://api.dp"}
                """#)
        let auth = makeClient(transport).auth
        let login = auth.hostedLogin(clientID: "spa_1", redirectURI: "myapp://callback", project: "proj", state: "good")

        do {
            _ = try await auth.completeHostedLogin(login, callbackURL: URL(string: "myapp://callback?code=C&state=evil")!)
            XCTFail("expected a state mismatch")
        } catch let error as IntrospectionError {
            XCTAssertEqual(error.code, "invalid_state")
        }
        do {
            _ = try await auth.completeHostedLogin(login, callbackURL: URL(string: "myapp://callback?error=access_denied&state=good")!)
            XCTFail("expected an error")
        } catch let error as IntrospectionError {
            XCTAssertEqual(error.kind, .authentication)
            XCTAssertEqual(error.code, "access_denied")
        }
        XCTAssertTrue(transport.requests.isEmpty)

        let token = try await auth.completeHostedLogin(login, callbackURL: URL(string: "myapp://callback?code=C%2B1&state=good")!)
        XCTAssertEqual(token.sessionId, "S")
        XCTAssertEqual(
            form(transport.last),
            [
                "grant_type": "authorization_code", "client_id": "spa_1", "code": "C+1",
                "redirect_uri": "myapp://callback", "code_verifier": login.codeVerifier,
            ])
    }

    func testOIDCAuthorizationRequestAndCallbackParsing() throws {
        let request = OIDC.authorizationRequest(
            authorizationEndpoint: URL(string: "https://idp.test/oauth/v2/authorize")!,
            clientId: "zitadel-app", redirectURI: "myapp://cb", additionalParameters: [("prompt", "login")]
        )
        let items = Dictionary(
            uniqueKeysWithValues: (URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
                .map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["scope"], "openid profile email offline_access")
        XCTAssertEqual(items["code_challenge"], request.pkce.challenge)
        XCTAssertEqual(items["state"], request.state)
        XCTAssertEqual(items["nonce"], request.nonce)
        XCTAssertEqual(items["prompt"], "login")
        XCTAssertFalse(request.url.absoluteString.contains("+"))

        let fragment = OIDC.parseCallback(URL(string: "myapp://cb#code=abc&state=xyz&iss=https%3A%2F%2Fidp.test")!)
        XCTAssertEqual(fragment.code, "abc")
        XCTAssertEqual(fragment.issuer, "https://idp.test")
        XCTAssertEqual(try fragment.authorizationCode(expectedState: "xyz"), "abc")
    }

    func testOIDCExchangeAndDiscoveryUseArbitraryEndpoints() async throws {
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
        XCTAssertEqual(transport.last?.request.url.absoluteString, "https://idp.test/.well-known/openid-configuration")
        XCTAssertEqual(metadata.tokenEndpoint, "https://idp.test/oauth/v2/token")
        let token = try await OIDC.exchangeCode(
            tokenEndpoint: URL(string: "https://idp.test/oauth/v2/token")!, code: "C", redirectURI: "myapp://cb",
            clientId: "zitadel-app", codeVerifier: "V", transport: transport
        )
        XCTAssertEqual(token.idToken, "IDT")
        XCTAssertEqual(transport.last?.request.url.absoluteString, "https://idp.test/oauth/v2/token")
        XCTAssertEqual(
            form(transport.last),
            [
                "grant_type": "authorization_code", "code": "C", "redirect_uri": "myapp://cb",
                "client_id": "zitadel-app", "code_verifier": "V",
            ])
    }

    // MARK: SessionCredentials

    func testConcurrentCallersShareOneRefresh() async throws {
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
        XCTAssertEqual(refreshes, 1)
        XCTAssertEqual(Set(headers), ["Bearer new-1"])
    }

    func testProactiveRefreshHonoursLeeway() async throws {
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
        XCTAssertEqual(early, "Bearer A")
        clock.advance(150)
        let late = try await credentials.authorization()
        XCTAssertEqual(late, "Bearer B")
        let recorded = await counter.tokens
        XCTAssertEqual(recorded.map(\.accessToken), ["B"])
    }

    func testUnauthorizedTriggersRefreshAndRetry() async throws {
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
        XCTAssertEqual(automation.id, "a1")
        XCTAssertEqual(transport.requests.map { $0.request.headers["Authorization"] }, ["Bearer stale", "Bearer fresh"])
    }

    func testRefreshFailureIsAuthentication() async throws {
        let credentials = SessionCredentials(token: SessionToken(accessToken: "A", expiresAt: .distantPast)) { _ in
            throw IntrospectionError(kind: .network, message: "offline")
        }
        do {
            _ = try await credentials.authorization()
            XCTFail("expected an error")
        } catch let error as IntrospectionError {
            XCTAssertEqual(error.kind, .authentication)
        }
    }

    func testPlatformSessionRefreshesThroughCPGrant() async throws {
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
        XCTAssertEqual(
            form(transport.last),
            [
                "grant_type": "refresh_token", "client_id": "spa_1", "refresh_token": "RT1", "session_id": "S", "org_id": "O",
            ])
        let stored = await updates.tokens
        XCTAssertEqual(stored.first?.refreshToken, "RT2")
        XCTAssertEqual(stored.first?.dataPlaneURL, "https://api.dp")
        let header = try await credentials.authorization()
        XCTAssertEqual(header, "Bearer \(rotated)")
    }

    func testDataPlaneSessionWithoutRefreshTokenFails() async throws {
        let credentials = SessionCredentials.dataPlaneSession(
            token: SessionToken(accessToken: "A", expiresAt: .distantPast),
            controlPlane: makeClient(MockTransport(json: tokenJSON)).auth
        )
        do {
            _ = try await credentials.authorization()
            XCTFail("expected an error")
        } catch let error as IntrospectionError {
            XCTAssertEqual(error.kind, .authentication)
        }
    }

    func testTokenExchangeCredentialsReExchangeAndCoalesce() async throws {
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
        XCTAssertEqual(Set(headers), ["Bearer DP0"])
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(
            form(transport.last),
            [
                "grant_type": "urn:ietf:params:oauth:grant-type:token-exchange", "client_id": "intro_app_jwks",
                "subject_token": "supabase-1", "subject_token_type": "urn:ietf:params:oauth:token-type:id_token",
                "project": "proj",
            ])
        let token = await credentials.token
        XCTAssertEqual(token.dataPlaneURL, "https://api.dp")

        try await credentials.refresh()
        XCTAssertEqual(form(transport.last)["subject_token"], "supabase-2")
        let header = try await credentials.authorization()
        XCTAssertEqual(header, "Bearer DP1")
    }

    func testFromServiceAccountUsesReturnedDataPlaneURL() async throws {
        let transport = MockTransport { request, _ in
            request.url.path == "/v1/oauth/token"
                ? .response(.json(#"{"access_token":"SA","token_type":"Bearer","expires_in":900,"dp_url":"https://api.dp.test"}"#))
                : .response(.json(#"{"records":[],"count":0,"next":null}"#))
        }
        let client = try await IntrospectionClient.fromServiceAccount(
            clientId: "intro_app_1", clientSecret: "intro_sk_1", project: "p",
            controlPlaneURL: URL(string: "https://cp.test")!, transport: transport
        )
        XCTAssertEqual(client.dataPlane.baseURL.absoluteString, "https://api.dp.test")
        _ = try await client.automations.list().firstPage()
        XCTAssertEqual(transport.last?.request.url.host, "api.dp.test")
        XCTAssertEqual(transport.last?.request.headers["Authorization"], "Bearer SA")
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
