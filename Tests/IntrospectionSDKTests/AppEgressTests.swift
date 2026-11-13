import Foundation
import Testing

@testable import IntrospectionSDK

@Suite struct AppEgressTests {
    private func tokenJSON(_ access: String) -> String {
        let body: JSONObject = [
            "access_token": .string(access), "token_type": "Bearer", "expires_in": 3600,
            "refresh_token": "r2", "session_id": "s1", "org_id": "o1", "dp_url": "https://api.dp.test",
        ]
        return String(decoding: try! JSONCoding.encoder.encode(body), as: UTF8.self)
    }

    private func signedIn(_ transport: MockTransport, access: String = "member-1") async throws -> AuthClient {
        let storage = InMemorySessionStorage()
        let session = AuthSession(
            token: SessionToken(
                accessToken: access, expiresAt: Date(timeIntervalSinceNow: 3600), refreshToken: "r1",
                sessionId: "s1", orgId: "o1", dataPlaneURL: "https://api.dp.test"))
        try await storage.save(JSONCoding.encoder.encode(session), key: "introspection.auth.session")
        return AuthClient(
            configuration: .init(
                controlPlaneURL: URL(string: "https://cp.test")!, clientID: "ark", project: "ark", method: .hostedLogin,
                storage: storage, transport: transport))
    }

    @Test func aRequestCarriesTheMemberTokenAndRuntimeToTheRoute() async throws {
        let transport = MockTransport { _, _ in .response(.json("{\"ok\":true}")) }
        let auth = try await signedIn(transport)
        let egress = try await auth.appEgress(runtime: "ark")

        let response = try await egress.send(
            "supabase", path: "/functions/v1/logins?x=1",
            headers: ["Authorization": "Bearer spoofed", "content-type": "application/json"],
            body: Data("{}".utf8))

        #expect(response.status == 200)
        let request = try #require(transport.last?.request)
        #expect(request.url.absoluteString == "https://egress.dp.test/supabase/functions/v1/logins?x=1")
        #expect(request.method == "POST")
        #expect(request.headers["Authorization"] == "Bearer member-1")
        #expect(request.headers[AppEgress.runtimeHeader] == "ark")
        #expect(request.headers["content-type"] == "application/json")
        #expect(request.headers.keys.filter { $0.lowercased() == "authorization" }.count == 1)
    }

    @Test func a401RenewsTheTokenOnceAndRetries() async throws {
        let transport = MockTransport { request, _ in
            if request.url.path == "/v1/oauth/token" { return .response(.json(self.tokenJSON("member-2"))) }
            let fresh = request.headers["Authorization"] == "Bearer member-2"
            return .response(.json(fresh ? "{}" : "{\"error\":\"expired\"}", status: fresh ? 200 : 401))
        }
        let auth = try await signedIn(transport)
        let egress = AppEgress(auth: auth, egressURL: URL(string: "https://egress.dp.test")!, runtime: "ark")

        let response = try await egress.send("deepgram", path: "/v1/listen")

        #expect(response.status == 200)
        let calls = transport.requests.map(\.path)
        #expect(calls == ["/deepgram/v1/listen", "/v1/oauth/token", "/deepgram/v1/listen"])
    }

    @Test func a401AfterRenewalIsAnAuthenticationError() async throws {
        let transport = MockTransport { request, _ in
            request.url.path == "/v1/oauth/token"
                ? .response(.json(self.tokenJSON("member-2"))) : .response(.json("{}", status: 401))
        }
        let auth = try await signedIn(transport)
        let egress = AppEgress(auth: auth, egressURL: URL(string: "https://egress.dp.test")!, runtime: "ark")

        await #expect(throws: IntrospectionError.self) { try await egress.send("supabase") }
        #expect(transport.requests.filter { $0.request.url.absoluteString == "https://egress.dp.test/supabase/" }.count == 2)
    }

    @Test func anEndpointErrorOtherThan401IsReturned() async throws {
        let transport = MockTransport { _, _ in .response(.json("{}", status: 404)) }
        let egress = AppEgress(
            auth: try await signedIn(transport), egressURL: URL(string: "https://egress.dp.test")!, runtime: "ark")
        #expect(try await egress.send("unknown").status == 404)
        #expect(transport.requests.count == 1)
    }

    @Test func routesAreAppRouteSlugs() {
        for route in ["supabase", "deepgram", "a", "a-b", "x1"] { #expect(AppEgress.isRoute(route)) }
        for route in ["", "-a", "a-", "A", "a_b", "a/b", "a.b", String(repeating: "a", count: 64)] {
            #expect(!AppEgress.isRoute(route), "\(route)")
        }
    }

    @Test func theEgressHostIsTheDataPlaneApiHostsSibling() {
        #expect(
            AppEgress.egressURL(forDataPlane: URL(string: "https://api.gcp01.us-east1.dp.test/v1")!)?.absoluteString
                == "https://egress.gcp01.us-east1.dp.test")
        #expect(AppEgress.egressURL(forDataPlane: URL(string: "https://dp.test")!) == nil)
    }

    @Test func pathsJoinUnderTheRoute() {
        let base = URL(string: "https://egress.dp.test/")!
        #expect(AppEgress.url(base, route: "r", path: "")?.absoluteString == "https://egress.dp.test/r/")
        #expect(AppEgress.url(base, route: "r", path: "x/y")?.absoluteString == "https://egress.dp.test/r/x/y")
        #expect(AppEgress.url(base, route: "r", path: "?q=1")?.absoluteString == "https://egress.dp.test/r/?q=1")
    }
}
