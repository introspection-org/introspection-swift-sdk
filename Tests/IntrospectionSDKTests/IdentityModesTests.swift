import Foundation
import Testing

@testable import IntrospectionSDK

/// One test per way a caller can authenticate, each driven through the same fake
/// platform: obtain the credential, open a runner or bind a runtime, create a task
/// and send a follow-up turn. Interactive flows (hosted login, device code) are
/// covered in `AuthClientTests` and `AuthTests`; `LiveIdentityTests` runs these
/// modes against a real deployment.
@Suite struct IdentityModesTests {
    private static let runtimeId = "0195c0de-0000-7000-8000-000000000001"

    /// A minimal platform: token endpoint, runtimes, runners and task routes,
    /// with every request recorded.
    private final class FakePlatform: @unchecked Sendable {
        let lock = NSLock()
        var exchanges = 0
        var rejectNextDataPlaneCall = false
        lazy var transport = MockTransport { [unowned self] request, _ in self.answer(request) }

        func answer(_ request: HTTPRequest) -> MockTransport.Reply {
            let path = request.url.path
            let body = request.body.map { String(decoding: $0, as: UTF8.self) } ?? ""
            switch (request.method, path) {
            case ("POST", "/v1/oauth/token") where body.contains("client_credentials"):
                return .response(.json(#"{"access_token":"service-token","expires_in":3600,"dp_url":"https://dp.test"}"#))
            case ("POST", "/v1/oauth/token") where body.contains("token-exchange"):
                lock.lock()
                exchanges += 1
                let n = exchanges
                lock.unlock()
                return .response(.json(#"{"access_token":"customer-\#(n)","expires_in":3600,"dp_url":"https://dp.test"}"#))
            case ("POST", "/v1/runtimes/ark/run"):
                return .response(
                    .json(
                        #"{"session_id":"sess-1","session_token":"runner-token","expires_at":"2099-01-01T00:00:00Z","deployment":{"endpoint":"https://dp.test"}}"#
                    ))
            case ("POST", "/v1/tasks"):
                if takeRejection() { return .response(.json(#"{"detail":"expired"}"#, status: 401)) }
                return .response(.json(#"{"task":\#(TasksTests.taskJSON),"run":\#(TasksTests.runJSON)}"#, status: 201))
            case ("POST", _) where path.hasSuffix("/runs"):
                return .response(.json(#"{"run":\#(TasksTests.runJSON)}"#, status: 201))
            case ("GET", "/v1/organizations/current"):
                return .response(.json(#"{"detail":"Customer principals cannot use this route"}"#, status: 403))
            default:
                return .response(.json(#"{"records":[],"count":0}"#))
            }
        }

        func takeRejection() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            let reject = rejectNextDataPlaneCall
            rejectNextDataPlaneCall = false
            return reject
        }
    }

    private let controlPlane = URL(string: "https://cp.test")!

    @Test func apiKeyIsSentAsIsAndNeverRefreshed() async throws {
        let transport = MockTransport { _, _ in .response(.json(#"{"detail":"bad key"}"#, status: 401)) }
        let client = IntrospectionClient(controlPlaneURL: controlPlane, credentials: BearerToken("intro_key"), transport: transport)
        let error = try await #require(throws: IntrospectionError.self) { try await client.tasks.list().firstPage() }
        #expect(error.kind == .authentication)
        #expect(transport.requests.count == 1)
        #expect(transport.last?.request.headers["Authorization"] == "Bearer intro_key")
    }

    @Test func serviceAccountRunnerCarriesTheEndUserIdentity() async throws {
        let platform = FakePlatform()
        let client = try await IntrospectionClient.fromServiceAccount(
            clientId: "intro_app_sa", clientSecret: "secret", project: "ark",
            controlPlaneURL: controlPlane, transport: platform.transport
        )
        let runner = try await client.runtimes("ark").run(
            identity: RunnerIdentity(userId: "u_42", anonymousId: "anon-1", conversationId: "conv-1", tags: ["tier:gold"]),
            ttlSeconds: 600
        )
        let run = try await runner.tasks.start(prompt: "Hello")
        _ = try await runner.tasks.runs.create(run.run.taskId, text: "And then?")
        let turnPath = "/v1/tasks/\(run.run.taskId)/runs"

        let requests = platform.transport.requests
        let open = try #require(requests.first { $0.path.hasSuffix("/run") })
        #expect(open.request.headers["Authorization"] == "Bearer service-token")
        #expect(
            open.json?["identity"] == ["user_id": "u_42", "anonymous_id": "anon-1", "conversation_id": "conv-1", "tags": ["tier:gold"]])
        #expect(open.json?["ttl_seconds"] == 600)

        // The runner's own token drives the Data Plane, and no runtime id is sent:
        // the server takes it from the runner token.
        let create = try #require(requests.first { $0.request.method == "POST" && $0.path == "/v1/tasks" })
        #expect(create.request.headers["Authorization"] == "Bearer runner-token")
        #expect(create.json?["runtime_id"] == nil)
        #expect(
            Set(requests.map(\.path)) == [
                "/v1/oauth/token", "/v1/runtimes/ark/run", "/v1/tasks", turnPath,
            ])
    }

    @Test func closedRunnerFailsBeforeTheNetwork() async throws {
        let platform = FakePlatform()
        let client = IntrospectionClient(controlPlaneURL: controlPlane, credentials: BearerToken("k"), transport: platform.transport)
        let runner = try await client.runtimes("ark").run()
        runner.close()
        let sent = platform.transport.requests.count
        let error = try await #require(throws: IntrospectionError.self) { try await runner.tasks.start(prompt: "Hello") }
        #expect(error.kind == .runnerExpired)
        #expect(platform.transport.requests.count == sent)
    }

    @Test func federatedMemberBindsTheRuntimeAndReexchangesAfterA401() async throws {
        let platform = FakePlatform()
        let subjects = Counter()
        let client = try await IntrospectionClient.federated(
            subjectToken: { "supabase-\(await subjects.next())" },
            clientID: "intro_app_fed", project: "ark",
            controlPlaneURL: controlPlane, transport: platform.transport
        )
        let run = try await client.tasks.start(prompt: "Hello", TaskCreate(runtimeId: Self.runtimeId))
        _ = try await client.tasks.runs.create(run.run.taskId, TaskRunCreate(text: "And then?", runtimeId: Self.runtimeId))
        let turnPath = "/v1/tasks/\(run.run.taskId)/runs"

        var requests = platform.transport.requests
        let exchange = try #require(requests.first { $0.path == "/v1/oauth/token" })
        #expect(exchange.bodyString.contains("subject_token=supabase-1"))
        #expect(exchange.bodyString.contains("client_id=intro_app_fed"))
        #expect(exchange.bodyString.contains("project=ark"))

        // Not a runner token, so the caller names the runtime version on the create
        // and on the follow-up turn, and the SDK looks nothing up on its own.
        #expect(Set(requests.map(\.path)) == ["/v1/oauth/token", "/v1/tasks", turnPath])
        let create = try #require(requests.first { $0.request.method == "POST" && $0.path == "/v1/tasks" })
        #expect(create.json?["runtime_id"] == .string(Self.runtimeId))
        #expect(create.request.headers["Authorization"] == "Bearer customer-1")
        let turn = try #require(requests.first { $0.path == turnPath })
        #expect(turn.json?["runtime_id"] == .string(Self.runtimeId))

        // A rejected platform token is exchanged again with a fresh provider token.
        platform.rejectNextDataPlaneCall = true
        _ = try await client.tasks.start(prompt: "Again")
        requests = platform.transport.requests
        #expect(requests.filter { $0.path == "/v1/oauth/token" }.count == 2)
        #expect(requests.last { $0.path == "/v1/oauth/token" }?.bodyString.contains("subject_token=supabase-2") == true)
        #expect(requests.last?.request.headers["Authorization"] == "Bearer customer-2")
    }

    @Test func federatedMemberIsRefusedOnControlPlaneRoutes() async throws {
        let platform = FakePlatform()
        let client = try await IntrospectionClient.federated(
            subjectToken: { "supabase" }, clientID: "intro_app_fed", project: "ark",
            controlPlaneURL: controlPlane, transport: platform.transport
        )
        let error = try await #require(throws: IntrospectionError.self) { try await client.organizations.current() }
        #expect(error.kind == .forbidden)
    }

    @Test func federatedCreateWithoutARuntimeIdSendsNone() async throws {
        let platform = FakePlatform()
        let client = try await IntrospectionClient.federated(
            subjectToken: { "supabase" }, clientID: "c", project: "ark",
            controlPlaneURL: controlPlane, transport: platform.transport
        )
        _ = try await client.tasks.start(prompt: "Hi")
        let create = try #require(platform.transport.requests.first { $0.path == "/v1/tasks" })
        #expect(create.json?.objectValue?.keys.contains("runtime_id") == false)
    }

    private actor Counter {
        var value = 0
        func next() -> Int {
            value += 1
            return value
        }
    }
}
