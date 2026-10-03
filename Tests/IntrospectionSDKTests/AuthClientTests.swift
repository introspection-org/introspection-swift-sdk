import Foundation
import XCTest
@testable import IntrospectionSDK

final class AuthClientTests: XCTestCase {
    private func jwt(_ claims: JSONObject) -> String {
        let payload = try! JSONCoding.encoder.encode(claims)
        let segment = payload.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "e30.\(segment).sig"
    }

    private func tokenJSON(_ access: String, refresh: String? = "r1", expiresIn: Int = 3600) -> String {
        var body: JSONObject = ["access_token": .string(access), "token_type": "Bearer", "expires_in": .number(Double(expiresIn)),
                                "session_id": "s1", "org_id": "o1", "dp_url": "https://dp.test"]
        if let refresh { body["refresh_token"] = .string(refresh) }
        return String(decoding: try! JSONCoding.encoder.encode(body), as: UTF8.self)
    }

    private func form(_ request: MockTransport.Recorded) -> [String: String] {
        var result: [String: String] = [:]
        for pair in request.bodyString.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map {
                String($0).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String($0)
            }
            result[parts[0]] = parts.count > 1 ? parts[1] : ""
        }
        return result
    }

    private func config(_ transport: MockTransport, method: AuthMethod, storage: any SessionStorage = InMemorySessionStorage()) -> AuthClient.Configuration {
        .init(controlPlaneURL: URL(string: "https://cp.test")!, clientID: "ark-ios", project: "ark",
              method: method, storage: storage, transport: transport)
    }

    func testEmailCodeSignInStoresSessionAndEmitsEvents() async throws {
        let access = jwt(["member_id": "m1", "org_id": "o1", "member_type": "business", "jti": "s1", "exp": 4_102_444_800])
        let transport = MockTransport { request, _ in
            request.url.path == "/v1/oauth/email-code" ? .response(.json("", status: 202)) : .response(.json(self.tokenJSON(access)))
        }
        let storage = InMemorySessionStorage()
        let auth = AuthClient(configuration: config(transport, method: .emailCode, storage: storage))
        let events = await auth.authStateChanges()
        var iterator = events.makeAsyncIterator()
        let initial = await iterator.next()
        XCTAssertEqual(initial?.0, .initialSession)
        XCTAssertNil(initial?.1)

        try await auth.signInWithOTP(email: "a@b.co")
        XCTAssertEqual(transport.requests[0].json, ["client_id": "ark-ios", "email": "a@b.co", "project": "ark"])

        let session = try await auth.verifyOTP(email: "a@b.co", token: "123456")
        let fields = form(transport.requests[1])
        XCTAssertEqual(fields["grant_type"], OAuthGrantType.emailCode)
        XCTAssertEqual(fields["code"], "123456")
        XCTAssertEqual(fields["email"], "a@b.co")
        XCTAssertEqual(session.user.memberId, "m1")
        XCTAssertEqual(session.dataPlaneURL, URL(string: "https://dp.test"))
        let signedIn = await iterator.next()
        XCTAssertEqual(signedIn?.0, .signedIn)

        // A second client with the same storage restores the session.
        let restoredClient = AuthClient(configuration: config(transport, method: .emailCode, storage: storage))
        let restored = try await restoredClient.session
        XCTAssertEqual(restored?.accessToken, access)
    }

    func testExpiredSessionRefreshesOnceForConcurrentCallers() async throws {
        let transport = MockTransport { _, _ in .response(.json(self.tokenJSON("fresh", refresh: "r2"))) }
        let storage = InMemorySessionStorage()
        let stale = AuthSession(token: SessionToken(accessToken: "old", expiresAt: Date(timeIntervalSinceNow: -10),
                                                    refreshToken: "r1", sessionId: "s1", orgId: "o1"))
        try await storage.save(JSONCoding.encoder.encode(stale), key: "introspection.auth.session")
        let auth = AuthClient(configuration: config(transport, method: .hostedLogin, storage: storage))
        let tokens = try await withThrowingTaskGroup(of: String?.self) { group in
            for _ in 0..<8 { group.addTask { try await auth.session?.accessToken } }
            return try await group.reduce(into: [String?]()) { $0.append($1) }
        }
        XCTAssertEqual(Set(tokens), ["fresh"])
        XCTAssertEqual(transport.requests.count, 1)
        let fields = form(transport.requests[0])
        XCTAssertEqual(fields["grant_type"], "refresh_token")
        XCTAssertEqual(fields["refresh_token"], "r1")
        XCTAssertEqual(fields["session_id"], "s1")
        XCTAssertEqual(fields["client_id"], "ark-ios")
        let saved = await storage.load(key: "introspection.auth.session")
        XCTAssertEqual(try JSONCoding.decoder.decode(AuthSession.self, from: saved!).token.refreshToken, "r2")
    }

    func testRejectedRefreshSignsOut() async throws {
        let transport = MockTransport { _, _ in
            .response(.json(#"{"error":"invalid_grant","error_description":"revoked"}"#, status: 400))
        }
        let auth = AuthClient(configuration: config(transport, method: .hostedLogin))
        try await auth.setSession(OAuthToken(accessToken: "a", refreshToken: "r", sessionId: "s", orgId: "o"))
        do {
            try await auth.refreshSession()
            XCTFail("expected failure")
        } catch let error as IntrospectionError {
            XCTAssertEqual(error.kind, .authentication)
        }
        let session = try await auth.session
        XCTAssertNil(session)
    }

    func testNetworkFailureKeepsSession() async throws {
        let transport = MockTransport { _, _ in .failure(IntrospectionError(kind: .network, message: "offline")) }
        let auth = AuthClient(configuration: config(transport, method: .hostedLogin))
        try await auth.setSession(OAuthToken(accessToken: "a", refreshToken: "r", sessionId: "s", orgId: "o"))
        do { try await auth.refreshSession() } catch {}
        let session = try await auth.session
        XCTAssertEqual(session?.accessToken, "a")
    }

    func testSignOutRevokesAndClears() async throws {
        let transport = MockTransport { _, _ in .response(.json(#"{"success":true}"#)) }
        let auth = AuthClient(configuration: config(transport, method: .hostedLogin))
        try await auth.setSession(OAuthToken(accessToken: "a", refreshToken: "r", sessionId: "s", orgId: "o"))
        try await auth.signOut()
        XCTAssertEqual(transport.last?.path, "/v1/oauth/revoke")
        XCTAssertEqual(form(transport.last!)["session_id"], "s")
        let session = try await auth.session
        XCTAssertNil(session)
    }

    func testMethodMismatchIsRejectedBeforeSending() async {
        let transport = MockTransport { _, _ in .response(.json("{}")) }
        let auth = AuthClient(configuration: config(transport, method: .hostedLogin))
        do {
            try await auth.signInWithOTP(email: "a@b.co")
            XCTFail("expected failure")
        } catch let error as IntrospectionError {
            XCTAssertEqual(error.kind, .invalidRequest)
        } catch { XCTFail("\(error)") }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testCredentialsDriveTheDataPlane() async throws {
        let transport = MockTransport { request, _ in
            request.url.host == "dp.test" ? .response(.json(#"{"ok":true}"#)) : .response(.json(self.tokenJSON("x")))
        }
        let auth = AuthClient(configuration: config(transport, method: .hostedLogin))
        try await auth.setSession(OAuthToken(accessToken: "tok", refreshToken: "r", sessionId: "s", orgId: "o", dpUrl: "https://dp.test"))
        let client = try await auth.client()
        _ = try await client.dataPlane.json("GET", "/v1/ping", as: JSONValue.self)
        XCTAssertEqual(transport.last?.request.headers["Authorization"], "Bearer tok")
        XCTAssertEqual(transport.last?.request.url.host, "dp.test")
    }
}
