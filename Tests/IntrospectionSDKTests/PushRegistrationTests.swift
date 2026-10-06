import Foundation
import Testing

@testable import IntrospectionSDK

@Suite struct PushRegistrationTests {
    static let hexToken = "00ff10abcdef"
    static let registration = PushRegistration(token: hexToken, environment: .sandbox)

    private func tokenJSON(_ access: String, refresh: String = "r2", memberName: String? = nil) -> String {
        var body: JSONObject = [
            "access_token": .string(access), "token_type": "Bearer", "expires_in": .number(3600),
            "refresh_token": .string(refresh), "session_id": "s1", "org_id": "o1", "dp_url": "https://dp.test",
        ]
        if let memberName { body["member_name"] = .string(memberName) }
        return String(decoding: try! JSONCoding.encoder.encode(body), as: UTF8.self)
    }

    private func form(_ request: MockTransport.Recorded) -> [String: String] {
        var result: [String: String] = [:]
        for pair in request.bodyString.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map {
                String($0).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String($0)
            }
            result[parts[0]] = parts.count > 1 ? parts[1] : ""
        }
        return result
    }

    private func auth(_ transport: MockTransport, method: AuthMethod = .hostedLogin) -> AuthClient {
        AuthClient(
            configuration: .init(
                controlPlaneURL: URL(string: "https://cp.test")!, clientID: OAuthClientID.ark, project: "ark",
                method: method, transport: transport))
    }

    private func signedIn(_ auth: AuthClient) async throws {
        try await auth.setSession(OAuthToken(accessToken: "a", expiresIn: 3600, refreshToken: "r1", sessionId: "s1", orgId: "o1"))
    }

    private func hostedCallback(_ request: HostedLoginRequest) -> URL {
        URL(string: "\(request.redirectURI)?code=c1&state=\(request.state)")!
    }

    // MARK: The value

    @Test func deviceTokenBytesBecomeLowercaseHex() {
        let push = PushRegistration(deviceToken: Data([0x00, 0xFF, 0x10, 0xAB, 0xCD, 0xEF]), environment: .production)
        #expect(push.token == Self.hexToken)
        #expect(push.platform == .applePush)
        #expect(push.environment == .production)
    }

    @Test func platformsAreTheServersWireNames() {
        #expect(PushRegistration.Platform.applePush.rawValue == "apple_push")
        #expect(PushRegistration.Platform.firebasePush.rawValue == "firebase_push")
        #expect(PushRegistration.Platform.webPush.rawValue == "web_push")
        let web = PushRegistration(token: "abc", environment: .production, platform: .webPush)
        #expect(web.parameters.map(\.1) == ["abc", "web_push", "production"])
        #expect(PushRegistration.Platform(rawValue: "future_push") == "future_push")
    }

    @Test func descriptionAndMirrorNeverShowTheToken() {
        let push = PushRegistration(token: "deadbeefcafe", environment: .sandbox)
        var dumped = ""
        dump(push, to: &dumped)
        for text in [push.description, push.debugDescription, String(describing: push), String(reflecting: push), dumped] {
            #expect(!text.contains("deadbeefcafe"))
        }
        #expect(push.description.contains("sandbox"))
    }

    @Test func formFields() {
        #expect(Self.registration.parameters.map(\.0) == ["push_token", "push_platform", "push_environment"])
        #expect(Self.registration.parameters.map(\.1) == [Self.hexToken, "apple_push", "sandbox"])
        #expect(PushRegistration.cleared.isCleared)
        #expect(PushRegistration.cleared.parameters.map(\.0) == ["push_token"])
        #expect(PushRegistration.cleared.parameters.map(\.1) == [""])
        #expect(PushRegistration.parameters(nil).isEmpty)
    }

    // MARK: AuthAPI grants

    @Test func refreshGrantCarriesPushFields() async throws {
        let transport = MockTransport(json: tokenJSON("x"))
        let api = AuthAPI(controlPlaneURL: URL(string: "https://cp.test")!, transport: transport)
        _ = try await api.refresh(refreshToken: "r1", clientId: "ark", sessionId: "s1", orgId: "o1", push: Self.registration)
        let fields = form(try #require(transport.last))
        #expect(fields["grant_type"] == OAuthGrantType.refreshToken)
        #expect(fields["push_token"] == Self.hexToken)
        #expect(fields["push_platform"] == "apple_push")
        #expect(fields["push_environment"] == "sandbox")
    }

    @Test func authorizationCodeGrantCarriesPushFields() async throws {
        let transport = MockTransport(json: tokenJSON("x"))
        let api = AuthAPI(controlPlaneURL: URL(string: "https://cp.test")!, transport: transport)
        _ = try await api.authorizationCode(
            code: "c1", clientId: "ark", redirectURI: "ark://cb", codeVerifier: "v", push: Self.registration)
        let fields = form(try #require(transport.last))
        #expect(fields["grant_type"] == OAuthGrantType.authorizationCode)
        #expect(fields["push_token"] == Self.hexToken)
        #expect(fields["push_environment"] == "sandbox")
    }

    @Test func grantsWithoutPushSendNoPushFields() async throws {
        let transport = MockTransport(json: tokenJSON("x"))
        let api = AuthAPI(controlPlaneURL: URL(string: "https://cp.test")!, transport: transport)
        _ = try await api.refresh(refreshToken: "r1", clientId: "ark", sessionId: "s1", orgId: "o1")
        let fields = form(try #require(transport.last))
        #expect(fields.keys.filter { $0.hasPrefix("push_") }.isEmpty)
    }

    @Test func clearedRegistrationSendsAnEmptyTokenOnly() async throws {
        let transport = MockTransport(json: tokenJSON("x"))
        let api = AuthAPI(controlPlaneURL: URL(string: "https://cp.test")!, transport: transport)
        _ = try await api.refresh(refreshToken: "r1", clientId: "ark", sessionId: "s1", orgId: "o1", push: .cleared)
        let last = try #require(transport.last)
        #expect(last.bodyString.contains("push_token=&") || last.bodyString.hasSuffix("push_token="))
        let fields = form(last)
        #expect(fields["push_token"] == "")
        #expect(fields["push_platform"] == nil)
        #expect(fields["push_environment"] == nil)
    }

    // MARK: AuthClient

    @Test func registrationRidesOnEveryRefresh() async throws {
        let transport = MockTransport(json: tokenJSON("x"))
        let auth = auth(transport)
        try await signedIn(auth)
        await auth.setPushRegistration(Self.registration)
        #expect(await auth.pushRegistration == Self.registration)
        try await auth.refreshSession()
        try await auth.refreshSession()
        #expect(transport.requests.count == 2)
        for request in transport.requests {
            #expect(form(request)["push_token"] == Self.hexToken)
        }
    }

    @Test func registerPushRefreshesImmediately() async throws {
        let transport = MockTransport(json: tokenJSON("fresh"))
        let auth = auth(transport)
        try await signedIn(auth)
        let session = try await auth.registerPush(Self.registration)
        #expect(session.accessToken == "fresh")
        let fields = form(try #require(transport.last))
        #expect(fields["grant_type"] == OAuthGrantType.refreshToken)
        #expect(fields["push_token"] == Self.hexToken)
        #expect(fields["push_environment"] == "sandbox")
    }

    @Test func clearingThroughTheClient() async throws {
        let transport = MockTransport(json: tokenJSON("x"))
        let auth = auth(transport)
        try await signedIn(auth)
        try await auth.registerPush(.cleared)
        let fields = form(try #require(transport.last))
        #expect(fields["push_token"] == "")
        #expect(fields["push_platform"] == nil)

        await auth.setPushRegistration(nil)
        try await auth.refreshSession()
        #expect(form(try #require(transport.last))["push_token"] == nil)
    }

    @Test func registerPushWhenSignedOutKeepsItForSignIn() async throws {
        let transport = MockTransport(json: tokenJSON("x"))
        let auth = auth(transport, method: .emailCode)
        let error = try await #require(throws: IntrospectionError.self) { try await auth.registerPush(Self.registration) }
        #expect(error.kind == .authentication)
        #expect(transport.requests.isEmpty)
        try await auth.verifyOTP(email: "a@b.co", token: "123456")
        let fields = form(try #require(transport.last))
        #expect(fields["grant_type"] == OAuthGrantType.emailCode)
        #expect(fields["push_token"] == Self.hexToken)
    }

    @Test func completeHostedLoginSendsAndKeepsPush() async throws {
        let transport = MockTransport(json: tokenJSON("x", memberName: "Ada"))
        let auth = auth(transport)
        let request = auth.hostedLoginRequest(redirectURI: "dev.introspection.ark://oauth/callback")
        try await auth.completeHostedLogin(request, callbackURL: hostedCallback(request), push: Self.registration)
        let fields = form(try #require(transport.last))
        #expect(fields["grant_type"] == OAuthGrantType.authorizationCode)
        #expect(fields["client_id"] == "ark")
        #expect(fields["push_token"] == Self.hexToken)
        #expect(await auth.pushRegistration == Self.registration)
    }

    // MARK: Member name

    @Test func hostedLoginPutsTheMemberNameOnTheSession() async throws {
        let transport = MockTransport(json: tokenJSON("x", memberName: "Ada"))
        let auth = auth(transport)
        let request = auth.hostedLoginRequest(redirectURI: "dev.introspection.ark://oauth/callback")
        let session = try await auth.completeHostedLogin(request, callbackURL: hostedCallback(request))
        #expect(session.user.name == "Ada")
        #expect(session.accessToken == "x")
        #expect(session.dataPlaneURL == URL(string: "https://dp.test"))
        #expect(form(try #require(transport.last))["push_token"] == nil)
    }

    @Test func theMemberNameSurvivesARestart() async throws {
        let storage = InMemorySessionStorage()
        let configuration = AuthClient.Configuration(
            controlPlaneURL: URL(string: "https://cp.test")!, clientID: OAuthClientID.ark, project: "ark", method: .hostedLogin,
            storage: storage, transport: MockTransport(json: tokenJSON("x", memberName: "Ada")))
        let first = AuthClient(configuration: configuration)
        let request = first.hostedLoginRequest(redirectURI: "dev.introspection.ark://oauth/callback")
        try await first.completeHostedLogin(request, callbackURL: hostedCallback(request))

        let restarted = AuthClient(configuration: configuration)
        #expect(try await restarted.session?.user.name == "Ada")
    }

    @Test func aRefreshKeepsTheNameUnlessTheResponseNamesAnother() async throws {
        let transport = MockTransport { _, index in
            .response(
                .json(
                    index == 0
                        ? self.tokenJSON("a", memberName: "Ada")
                        : index == 1 ? self.tokenJSON("b") : self.tokenJSON("c", memberName: "Ada L.")))
        }
        let auth = auth(transport)
        let request = auth.hostedLoginRequest(redirectURI: "dev.introspection.ark://oauth/callback")
        try await auth.completeHostedLogin(request, callbackURL: hostedCallback(request))
        #expect(try await auth.refreshSession().user.name == "Ada")
        #expect(try await auth.refreshSession().user.name == "Ada L.")
    }

    @Test func aSessionStoredBeforeTheNameDecodes() throws {
        let stored = #"{"member_id": "m", "org_id": "o", "email": "a@b.co"}"#
        let user = try JSONCoding.decoder.decode(AuthUser.self, from: Data(stored.utf8))
        #expect(user.name == nil)
        #expect(user.email == "a@b.co")
    }

    // MARK: setSession generation guard

    @Test func setSessionRefusesAfterSignOut() async throws {
        let auth = auth(MockTransport(json: #"{"success":true}"#))
        try await signedIn(auth)
        let generation = await auth.sessionGeneration
        try await auth.signOut()
        await #expect(throws: CancellationError.self) {
            try await auth.setSession(OAuthToken(accessToken: "late", refreshToken: "r"), ifUnchangedSince: generation)
        }
        #expect(try await auth.session == nil)
    }

    @Test func setSessionAcceptsWhenUnchanged() async throws {
        let auth = auth(MockTransport(json: "{}"))
        let generation = await auth.sessionGeneration
        let session = try await auth.setSession(OAuthToken(accessToken: "new", refreshToken: "r"), ifUnchangedSince: generation)
        #expect(session.accessToken == "new")
        #expect(await auth.sessionGeneration != generation)
    }

    // MARK: Hosted-login scope

    @Test(arguments: ["*", "tasks:write events:read connections:read"])
    func hostedLoginRequestCarriesScope(scope: String) throws {
        let auth = auth(MockTransport(json: "{}"))
        let request = auth.hostedLoginRequest(redirectURI: "dev.introspection.ark://oauth/callback", scope: scope)
        let items = try #require(URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.first { $0.name == "scope" }?.value == scope)
        #expect(items.first { $0.name == "client_id" }?.value == "ark")
    }

    #if canImport(AuthenticationServices) && !os(watchOS)
    @Test func presenterSendsItsScope() throws {
        let auth = auth(MockTransport(json: "{}"))
        let request = HostedLoginPresenter.request(
            with: auth, redirectURI: "dev.introspection.ark://oauth/callback", scope: "tasks:write events:read")
        let items = try #require(URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.first { $0.name == "scope" }?.value == "tasks:write events:read")
    }
    #endif
}
