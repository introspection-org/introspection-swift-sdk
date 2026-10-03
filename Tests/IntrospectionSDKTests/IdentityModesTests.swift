import Foundation
import XCTest

@testable import IntrospectionSDK

/// One test per way a caller can authenticate, each driven through the same fake
/// platform: obtain the credential, open a runner or bind a runtime, create a task
/// and send a follow-up turn. Interactive flows (hosted login, device code) are
/// covered in `AuthClientTests` and `AuthTests`; `LiveIdentityTests` runs these
/// modes against a real deployment.
final class IdentityModesTests: XCTestCase {
    private static let runtimeId = "0195c0de-0000-7000-8000-000000000001"

    /// A minimal platform: token endpoint, runtimes, runners, the Data Plane
    /// `list_runtimes` tool and task routes, with every request recorded.
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
            case ("GET", "/v1/runtimes"):
                return .response(.json(#"{"records":[{"id":"\#(IdentityModesTests.runtimeId)","name":"ark"}],"count":1}"#))
            case ("POST", "/v1/runtimes/\(IdentityModesTests.runtimeId)/run"):
                return .response(
                    .json(
                        #"{"session_id":"sess-1","session_token":"runner-token","expires_at":"2099-01-01T00:00:00Z","deployment":{"endpoint":"https://dp.test"}}"#
                    ))
            case ("POST", "/v1/mcp"):
                return .response(
                    .json(
                        #"{"jsonrpc":"2.0","id":1,"result":{"structuredContent":{"runtimes":[{"runtime_id":"rt-current","image_build_status":"ready"}]}}}"#
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

    func testAPIKeyIsSentAsIsAndNeverRefreshed() async throws {
        let transport = MockTransport { _, _ in .response(.json(#"{"detail":"bad key"}"#, status: 401)) }
        let client = IntrospectionClient(controlPlaneURL: controlPlane, credentials: BearerToken("intro_key"), transport: transport)
        do {
            _ = try await client.tasks.list().firstPage()
            XCTFail("expected failure")
        } catch let error as IntrospectionError {
            XCTAssertEqual(error.kind, .authentication)
        }
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.last?.request.headers["Authorization"], "Bearer intro_key")
    }

    func testServiceAccountRunnerCarriesTheEndUserIdentity() async throws {
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

        let requests = platform.transport.requests
        let open = try XCTUnwrap(requests.first { $0.path.hasSuffix("/run") })
        XCTAssertEqual(open.request.headers["Authorization"], "Bearer service-token")
        XCTAssertEqual(
            open.json?["identity"],
            ["user_id": "u_42", "anonymous_id": "anon-1", "conversation_id": "conv-1", "tags": ["tier:gold"]])
        XCTAssertEqual(open.json?["ttl_seconds"], 600)

        // The runner's own token drives the Data Plane, and no runtime id is sent:
        // the server takes it from the runner token.
        let create = try XCTUnwrap(requests.first { $0.request.method == "POST" && $0.path == "/v1/tasks" })
        XCTAssertEqual(create.request.headers["Authorization"], "Bearer runner-token")
        XCTAssertNil(create.json?["runtime_id"])
        XCTAssertFalse(requests.contains { $0.path == "/v1/mcp" })
    }

    func testClosedRunnerFailsBeforeTheNetwork() async throws {
        let platform = FakePlatform()
        let client = IntrospectionClient(controlPlaneURL: controlPlane, credentials: BearerToken("k"), transport: platform.transport)
        let runner = try await client.runtimes("ark").run()
        runner.close()
        let sent = platform.transport.requests.count
        do {
            _ = try await runner.tasks.start(prompt: "Hello")
            XCTFail("expected failure")
        } catch let error as IntrospectionError {
            XCTAssertEqual(error.kind, .runnerExpired)
        }
        XCTAssertEqual(platform.transport.requests.count, sent)
    }

    func testFederatedMemberBindsTheRuntimeAndReexchangesAfterA401() async throws {
        let platform = FakePlatform()
        let subjects = Counter()
        let client = try await IntrospectionClient.federated(
            subjectToken: { "supabase-\(await subjects.next())" },
            clientID: "intro_app_fed", project: "ark", runtime: "ark",
            controlPlaneURL: controlPlane, transport: platform.transport
        )
        let run = try await client.tasks.start(prompt: "Hello")
        _ = try await client.tasks.runs.create(run.run.taskId, text: "And then?")

        var requests = platform.transport.requests
        let exchange = try XCTUnwrap(requests.first { $0.path == "/v1/oauth/token" })
        XCTAssertTrue(exchange.bodyString.contains("subject_token=supabase-1"))
        XCTAssertTrue(exchange.bodyString.contains("client_id=intro_app_fed"))
        XCTAssertTrue(exchange.bodyString.contains("project=ark"))

        // Not a runner token, so the runtime version is resolved on the Data Plane
        // once and named on the create and on the follow-up turn.
        XCTAssertEqual(requests.filter { $0.path == "/v1/mcp" }.count, 1)
        let create = try XCTUnwrap(requests.first { $0.request.method == "POST" && $0.path == "/v1/tasks" })
        XCTAssertEqual(create.json?["runtime_id"], "rt-current")
        XCTAssertEqual(create.request.headers["Authorization"], "Bearer customer-1")
        let turn = try XCTUnwrap(requests.first { $0.path.hasSuffix("/runs") })
        XCTAssertEqual(turn.json?["runtime_id"], "rt-current")

        // A rejected platform token is exchanged again with a fresh provider token.
        platform.rejectNextDataPlaneCall = true
        _ = try await client.tasks.start(prompt: "Again")
        requests = platform.transport.requests
        XCTAssertEqual(requests.filter { $0.path == "/v1/oauth/token" }.count, 2)
        XCTAssertTrue(requests.last { $0.path == "/v1/oauth/token" }?.bodyString.contains("subject_token=supabase-2") == true)
        XCTAssertEqual(requests.last?.request.headers["Authorization"], "Bearer customer-2")
    }

    func testFederatedMemberIsRefusedOnControlPlaneRoutes() async throws {
        let platform = FakePlatform()
        let client = try await IntrospectionClient.federated(
            subjectToken: { "supabase" }, clientID: "intro_app_fed", project: "ark",
            controlPlaneURL: controlPlane, transport: platform.transport
        )
        do {
            _ = try await client.organizations.current()
            XCTFail("expected failure")
        } catch let error as IntrospectionError {
            XCTAssertEqual(error.kind, .forbidden)
        }
    }

    func testExplicitRuntimeIdIsNeverOverridden() async throws {
        let platform = FakePlatform()
        let client = try await IntrospectionClient.federated(
            subjectToken: { "supabase" }, clientID: "c", project: "ark", runtime: "ark",
            controlPlaneURL: controlPlane, transport: platform.transport
        )
        _ = try await client.tasks.start(prompt: "Hi", TaskCreate(runtimeId: "pinned"))
        let create = try XCTUnwrap(platform.transport.requests.first { $0.path == "/v1/tasks" })
        XCTAssertEqual(create.json?["runtime_id"], "pinned")
        XCTAssertFalse(platform.transport.requests.contains { $0.path == "/v1/mcp" })
    }

    func testRuntimeSelectorCachesUntilItsTTL() async throws {
        let calls = Counter()
        let clock = Clock()
        let selector = RuntimeSelector(runtime: "ark", ttl: 60, now: { clock.now }) { _ in
            "rt-\(await calls.next())"
        }
        let first = try await selector.runtimeId()
        let cached = try await selector.runtimeId()
        clock.advance(61)
        let refreshed = try await selector.runtimeId()
        XCTAssertEqual([first, cached, refreshed], ["rt-1", "rt-1", "rt-2"])
    }

    private actor Counter {
        var value = 0
        func next() -> Int {
            value += 1
            return value
        }
    }

    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var current = Date(timeIntervalSince1970: 1_000_000)
        var now: Date {
            lock.lock()
            defer { lock.unlock() }
            return current
        }
        func advance(_ seconds: TimeInterval) {
            lock.lock()
            current = current.addingTimeInterval(seconds)
            lock.unlock()
        }
    }
}
