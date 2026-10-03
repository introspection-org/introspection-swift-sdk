import Foundation
import Testing

@testable import IntrospectionSDK

@Suite struct AuthSessionRaceTests {
    private let key = "introspection.auth.session"

    private func client(_ transport: any HTTPTransport, _ storage: any SessionStorage) -> AuthClient {
        AuthClient(
            configuration: .init(
                controlPlaneURL: URL(string: "https://cp.test")!, clientID: "app", project: "p",
                method: .hostedLogin, storage: storage, transport: transport))
    }

    private func token(_ value: String) -> OAuthToken {
        OAuthToken(accessToken: value, refreshToken: "refresh", sessionId: "session", orgId: "org")
    }

    @Test(arguments: [false, true]) func oldRefreshCannotReplaceNewSignIn(rejected: Bool) async throws {
        let transport = SuspendedRefreshTransport()
        let storage = InMemorySessionStorage()
        let auth = client(transport, storage)
        try await auth.setSession(token("old"))
        let refresh = Task { try await auth.refreshSession() }
        await transport.gate.waitUntilEntered()
        try await auth.setSession(token("new"))
        await transport.finish(rejected: rejected)
        await #expect(throws: CancellationError.self) { try await refresh.value }
        #expect(try await auth.session?.accessToken == "new")
        let data = try #require(await storage.load(key: key))
        #expect(try JSONCoding.decoder.decode(AuthSession.self, from: data).accessToken == "new")
    }

    @Test func oldRefreshCannotUndoSignOut() async throws {
        let transport = SuspendedRefreshTransport()
        let storage = InMemorySessionStorage()
        let auth = client(transport, storage)
        try await auth.setSession(token("old"))
        let refresh = Task { try await auth.refreshSession() }
        await transport.gate.waitUntilEntered()
        try await auth.signOut()
        await transport.finish()
        await #expect(throws: CancellationError.self) { try await refresh.value }
        #expect(try await auth.session == nil)
        #expect(await storage.load(key: key) == nil)
    }

    @Test(arguments: [false, true]) func pendingStorageWriteCannotUndoTransition(signIn: Bool) async throws {
        let transport = SuspendedRefreshTransport()
        let storage = SuspendedSessionStorage()
        let auth = client(transport, storage)
        try await auth.setSession(token("old"))
        await storage.pauseNextSave()
        let refresh = Task { try await auth.refreshSession() }
        await transport.gate.waitUntilEntered()
        await transport.finish()
        await storage.gate.waitUntilEntered()
        let transition = Task {
            if signIn { try await auth.setSession(token("new")) } else { try await auth.signOut() }
        }
        // Both transitions invalidate the old session before awaiting persistence.
        while try await auth.session != nil { await Task.yield() }
        await storage.gate.release()
        try await transition.value
        await #expect(throws: CancellationError.self) { try await refresh.value }
        #expect(try await auth.session?.accessToken == (signIn ? "new" : nil))
        let saved = await storage.load(key: key)
        if signIn {
            #expect(try JSONCoding.decoder.decode(AuthSession.self, from: #require(saved)).accessToken == "new")
        } else {
            #expect(saved == nil)
        }
    }
}

private actor SuspensionGate {
    private var entered = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var suspended: CheckedContinuation<Void, Never>?

    func pause() async {
        entered = true
        waiter?.resume()
        waiter = nil
        await withCheckedContinuation { suspended = $0 }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func release() {
        suspended?.resume()
        suspended = nil
    }
}

private actor SuspendedRefreshTransport: HTTPTransport {
    let gate = SuspensionGate()
    private var rejected = false

    func send(_ request: HTTPRequest) async -> HTTPResponse {
        guard request.url.path == "/v1/oauth/token" else { return .json("{}") }
        await gate.pause()
        if rejected { return .json(#"{"error":"invalid_grant"}"#, status: 400) }
        return .json(#"{"access_token":"refreshed","refresh_token":"next","expires_in":3600,"session_id":"session","org_id":"org"}"#)
    }

    func finish(rejected: Bool = false) async {
        self.rejected = rejected
        await gate.release()
    }

    func stream(_ request: HTTPRequest) throws -> HTTPStreamResponse {
        throw IntrospectionError(kind: .invalidRequest, message: "Unexpected stream")
    }
}

private actor SuspendedSessionStorage: SessionStorage {
    let gate = SuspensionGate()
    private var data: Data?
    private var pauseSave = false

    func pauseNextSave() { pauseSave = true }
    func load(key: String) -> Data? { data }
    func remove(key: String) { data = nil }
    func save(_ value: Data, key: String) async {
        if pauseSave {
            pauseSave = false
            await gate.pause()
        }
        data = value
    }
}
