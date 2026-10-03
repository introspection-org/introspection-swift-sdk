import Foundation
import XCTest

@testable import IntrospectionSDK

/// Every identity mode against a real deployment: obtain the credential, run a
/// task and read it back. Skipped unless `INTROSPECTION_LIVE=1`; each test also
/// skips when its own settings are absent. CI runs it from `live-tests.yml` in the
/// `build` environment.
///
/// Settings: `INTROSPECTION_BASE_API_URL` (or `INTROSPECTION_BASE_URL`), the Control
/// Plane; `INTROSPECTION_RUNTIME`, the runtime group to run on (the project's
/// newest runtime when unset, for the runner modes); `INTROSPECTION_TOKEN`,
/// an API key; `INTROSPECTION_CLIENT_ID` / `INTROSPECTION_CLIENT_SECRET`, a service
/// account; `INTROSPECTION_PROJECT`; and for federation
/// `INTROSPECTION_FEDERATED_CLIENT_ID`, `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`,
/// `FEDERATED_TEST_USER_EMAIL` / `_PASSWORD` and `FEDERATED_TEST_USER_2_EMAIL` /
/// `_PASSWORD`.
final class LiveIdentityTests: XCTestCase {
    private let env = ProcessInfo.processInfo.environment
    private let prompt = "Reply with the single word: ok"
    private let runOptions = RunStreamOptions(timeout: 600)

    override func setUpWithError() throws {
        guard env["INTROSPECTION_LIVE"] == "1" else {
            throw XCTSkip("Live tests run only with INTROSPECTION_LIVE=1")
        }
    }

    private func setting(_ name: String) throws -> String {
        guard let value = env[name], !value.isEmpty else { throw XCTSkip("\(name) is not set") }
        return value
    }

    private func controlPlaneURL() throws -> URL {
        let raw: String
        if let value = env["INTROSPECTION_BASE_API_URL"], !value.isEmpty {
            raw = value
        } else {
            raw = try setting("INTROSPECTION_BASE_URL")
        }
        guard let url = URL(string: raw) else { throw XCTSkip("Invalid Control Plane URL: \(raw)") }
        return url
    }

    private var project: String? { env["INTROSPECTION_PROJECT"].flatMap { $0.isEmpty ? nil : $0 } }

    // MARK: API key

    func testAPIKeyRunnerCarriesAnEndUserIdentity() async throws {
        let client = IntrospectionClient(
            controlPlaneURL: try controlPlaneURL(), credentials: BearerToken(try setting("INTROSPECTION_TOKEN")))
        let runner = try await client.runtime(try await runtime(client), project: project).run(
            identity: RunnerIdentity(userId: "swift-sdk-live-\(UUID().uuidString.lowercased())"),
            ttlSeconds: 900
        )
        defer { runner.close() }
        try await exerciseDataPlane(runner)
    }

    /// `INTROSPECTION_RUNTIME`, or the project's newest runtime when it is unset.
    private func runtime(_ client: IntrospectionClient) async throws -> String {
        if let runtime = env["INTROSPECTION_RUNTIME"], !runtime.isEmpty { return runtime }
        let page = try await client.runtimes.list(RuntimeListParams(project: project, limit: 1)).firstPage()
        guard let first = page.records.first else { throw XCTSkip("The project has no runtimes and INTROSPECTION_RUNTIME is not set") }
        return first.id
    }

    // MARK: Service account

    func testServiceAccountRunner() async throws {
        let client = try await IntrospectionClient.fromServiceAccount(
            clientId: try setting("INTROSPECTION_CLIENT_ID"),
            clientSecret: try setting("INTROSPECTION_CLIENT_SECRET"),
            project: try setting("INTROSPECTION_PROJECT"),
            controlPlaneURL: try controlPlaneURL()
        )
        let runner = try await client.runtime(try await runtime(client), project: project).run(ttlSeconds: 900)
        defer { runner.close() }
        try await exerciseDataPlane(runner)
    }

    // MARK: Federated (Supabase through a Direct JWKS Application)

    func testFederatedMemberRunsOnTheRuntimeAndIsIsolated() async throws {
        let first = try await federatedClient(user: "FEDERATED_TEST_USER")
        let task = try await exerciseDataPlane(first)

        let second = try await federatedClient(user: "FEDERATED_TEST_USER_2")
        do {
            _ = try await second.tasks.get(task.id)
            XCTFail("another federated member could read the task")
        } catch let error as IntrospectionError {
            XCTAssertEqual(error.kind, .notFound)
        }
        let visible = try await second.tasks.list(TaskListParams(limit: 100)).collect(limit: 500)
        XCTAssertFalse(visible.contains { $0.id == task.id })
    }

    func testFederatedMemberIsRefusedOnTheControlPlane() async throws {
        let client = try await federatedClient(user: "FEDERATED_TEST_USER")
        do {
            _ = try await client.organizations.current()
            XCTFail("a customer token reached a Control Plane route")
        } catch let error as IntrospectionError {
            XCTAssertTrue([.forbidden, .authentication].contains(error.kind), "\(error)")
        }
    }

    private func federatedClient(user prefix: String) async throws -> IntrospectionClient {
        let supabase = try SupabaseTestUser(
            url: try setting("SUPABASE_URL"),
            key: try setting("SUPABASE_PUBLISHABLE_KEY"),
            email: try setting("\(prefix)_EMAIL"),
            password: try setting("\(prefix)_PASSWORD")
        )
        return try await IntrospectionClient.federated(
            subjectToken: { try await supabase.accessToken() },
            clientID: try setting("INTROSPECTION_FEDERATED_CLIENT_ID"),
            project: try setting("INTROSPECTION_PROJECT"),
            runtime: try setting("INTROSPECTION_RUNTIME"),
            controlPlaneURL: try controlPlaneURL()
        )
    }

    // MARK: Shared Data Plane walk

    /// Start a task, wait for its answer, send a follow-up, read the task back,
    /// round-trip a file, and clean up.
    @discardableResult
    private func exerciseDataPlane(_ connection: some DataPlaneConnection) async throws -> IntrospectionTask {
        let marker = "swift-sdk-live:\(UUID().uuidString.lowercased())"
        let run = try await connection.tasks.start(prompt: prompt, TaskCreate(title: marker, tags: ["swift-sdk-live"]))
        let answer = try await run.text(options: runOptions)
        XCTAssertFalse(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "no assistant text")

        let followUp = try await connection.tasks.runs.create(run.run.taskId, text: prompt)
        _ = try await followUp.text(options: runOptions)

        let task = try await connection.tasks.get(run.run.taskId)
        XCTAssertEqual(task.title, marker)

        let file = try await connection.files.createText(
            FileCreateText(content: "# \(marker)\n", name: "swift-sdk-live/\(UUID().uuidString.lowercased()).md", mimeType: "text/markdown")
        )
        let content = try await connection.files.download(file.id)
        XCTAssertEqual(String(decoding: content, as: UTF8.self), "# \(marker)\n")
        try await connection.files.delete(file.id)

        try await connection.tasks.archive(task.id)
        return task
    }
}

/// Signs a confirmed Supabase test user in with a password and hands out a fresh
/// access token for every exchange.
private struct SupabaseTestUser: Sendable {
    let http: HTTPClient
    let key: String
    let email: String
    let password: String

    init(url: String, key: String, email: String, password: String) throws {
        guard let base = URL(string: url) else { throw XCTSkip("Invalid SUPABASE_URL") }
        http = HTTPClient(baseURL: base)
        self.key = key
        self.email = email
        self.password = password
    }

    func accessToken() async throws -> String {
        var query = Query()
        query.add("grant_type", "password")
        let response = try await http.json(
            "POST", "/auth/v1/token", query: query,
            body: .encode(["email": email, "password": password]),
            headers: ["apikey": key], authenticated: false, as: JSONValue.self
        )
        guard let token = response["access_token"]?.stringValue else {
            throw IntrospectionError(kind: .authentication, message: "Supabase sign-in returned no access token")
        }
        return token
    }
}
