import Foundation
import Testing

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
/// `FEDERATED_TEST_USER_EMAIL` / `_PASSWORD`, plus `FEDERATED_TEST_USER_2_EMAIL` /
/// `_PASSWORD` for the isolation check. A federated test that runs a task also
/// needs the service account and `INTROSPECTION_RUNTIME`, to look the runtime
/// version up.
@Suite(.enabled(if: Live.isEnabled, "Live tests run only with INTROSPECTION_LIVE=1"))
struct LiveIdentityTests {
    private let prompt = "Reply with the single word: ok"
    private let runOptions = RunStreamOptions(timeout: 600)

    private func setting(_ name: String) throws -> String {
        guard let value = Live.value(name) else { try Test.cancel("\(name) is not set") }
        return value
    }

    private func controlPlaneURL() throws -> URL {
        let raw = try Live.value("INTROSPECTION_BASE_API_URL") ?? setting("INTROSPECTION_BASE_URL")
        guard let url = URL(string: raw) else { try Test.cancel("Invalid Control Plane URL: \(raw)") }
        return url
    }

    private var project: String? { Live.value("INTROSPECTION_PROJECT") }

    // MARK: API key

    @Test(Live.requires("INTROSPECTION_TOKEN"))
    func apiKeyRunnerCarriesAnEndUserIdentity() async throws {
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
        if let runtime = Live.value("INTROSPECTION_RUNTIME") { return runtime }
        let page = try await client.runtimes.list(RuntimeListParams(project: project, limit: 1)).firstPage()
        guard let first = page.records.first else { try Test.cancel("The project has no runtimes and INTROSPECTION_RUNTIME is not set") }
        return first.id
    }

    // MARK: Service account

    @Test(Live.requires("INTROSPECTION_CLIENT_ID", "INTROSPECTION_CLIENT_SECRET", "INTROSPECTION_PROJECT"))
    func serviceAccountRunner() async throws {
        let client = try await serviceAccountClient()
        let runner = try await client.runtime(try await runtime(client), project: project).run(ttlSeconds: 900)
        defer { runner.close() }
        try await exerciseDataPlane(runner)
    }

    private func serviceAccountClient() async throws -> IntrospectionClient {
        try await IntrospectionClient.fromServiceAccount(
            clientId: try setting("INTROSPECTION_CLIENT_ID"),
            clientSecret: try setting("INTROSPECTION_CLIENT_SECRET"),
            project: try setting("INTROSPECTION_PROJECT"),
            controlPlaneURL: try controlPlaneURL()
        )
    }

    // MARK: Federated (Supabase through a Direct JWKS Application)

    @Test(Live.requires(Live.federated("FEDERATED_TEST_USER") + Live.runtimeLookup))
    func federatedMemberRunsOnTheRuntime() async throws {
        let runtimeId = try await runtimeVersionId()
        try await exerciseDataPlane(try await federatedClient(user: "FEDERATED_TEST_USER"), runtimeId: runtimeId)
    }

    /// Skipped unless a second test user is configured.
    @Test(Live.requires(Live.federated("FEDERATED_TEST_USER") + Live.federated("FEDERATED_TEST_USER_2") + Live.runtimeLookup))
    func federatedMembersAreIsolated() async throws {
        let runtimeId = try await runtimeVersionId()
        let second = try await federatedClient(user: "FEDERATED_TEST_USER_2")
        let first = try await federatedClient(user: "FEDERATED_TEST_USER")
        let run = try await first.tasks.start(
            prompt: prompt, TaskCreate(title: "swift-sdk-live:isolation", runtimeId: runtimeId, tags: ["swift-sdk-live"]))
        let task = try await first.tasks.get(run.run.taskId)

        let error = try await #require(throws: IntrospectionError.self) { try await second.tasks.get(task.id) }
        #expect(error.kind == .notFound)
        let visible = try await second.tasks.list(TaskListParams(limit: 100)).collect(limit: 500)
        #expect(!visible.contains { $0.id == task.id })
        try await first.tasks.archive(task.id)
    }

    @Test(Live.requires(Live.federated("FEDERATED_TEST_USER")))
    func federatedMemberIsRefusedOnTheControlPlane() async throws {
        let client = try await federatedClient(user: "FEDERATED_TEST_USER")
        let error = try await #require(throws: IntrospectionError.self) { try await client.organizations.current() }
        #expect([.forbidden, .authentication].contains(error.kind), "\(error)")
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
            controlPlaneURL: try controlPlaneURL()
        )
    }

    /// The newest version of `INTROSPECTION_RUNTIME`, looked up with the service
    /// account as an app backend would: a customer token names the runtime itself.
    private func runtimeVersionId() async throws -> String {
        let params = RuntimeListParams(project: project, runtime: try setting("INTROSPECTION_RUNTIME"), limit: 1)
        let page = try await serviceAccountClient().runtimes.list(params).firstPage()
        return try #require(page.records.first?.id, "INTROSPECTION_RUNTIME has no runtime version in the project")
    }

    // MARK: Shared Data Plane walk

    /// Start a task, wait for its answer, send a follow-up, read the task back,
    /// round-trip a file, and archive the task. The file is left in place: runner
    /// and customer tokens cannot hold `files:delete`. `runtimeId` is nil for a
    /// runner, whose token already names the runtime.
    @discardableResult
    private func exerciseDataPlane(_ connection: some DataPlaneConnection, runtimeId: String? = nil) async throws -> IntrospectionTask {
        let marker = "swift-sdk-live:\(UUID().uuidString.lowercased())"
        let run = try await connection.tasks.start(
            prompt: prompt, TaskCreate(title: marker, runtimeId: runtimeId, tags: ["swift-sdk-live"]))
        let answer = try await run.text(options: runOptions)
        #expect(!answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "no assistant text")

        let followUp = try await connection.tasks.runs.create(run.run.taskId, TaskRunCreate(text: prompt, runtimeId: runtimeId))
        _ = try await followUp.text(options: runOptions)

        let task = try await connection.tasks.get(run.run.taskId)
        #expect(task.title == marker)

        let file = try await connection.files.createText(
            FileCreateText(content: "# \(marker)\n", name: "swift-sdk-live/\(UUID().uuidString.lowercased()).md", mimeType: "text/markdown")
        )
        let content = try await connection.files.download(file.id)
        #expect(String(decoding: content, as: UTF8.self) == "# \(marker)\n")

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
        guard let base = URL(string: url) else { try Test.cancel("Invalid SUPABASE_URL") }
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

/// The live settings, read once, so a test whose settings are missing is skipped before it runs.
private enum Live {
    static let environment = ProcessInfo.processInfo.environment
    static let isEnabled = environment["INTROSPECTION_LIVE"] == "1"

    static func value(_ name: String) -> String? {
        environment[name].flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The settings a federated client for the test user `prefix` reads.
    static func federated(_ prefix: String) -> [String] {
        [
            "SUPABASE_URL", "SUPABASE_PUBLISHABLE_KEY", "\(prefix)_EMAIL", "\(prefix)_PASSWORD",
            "INTROSPECTION_FEDERATED_CLIENT_ID", "INTROSPECTION_PROJECT",
        ]
    }

    /// The settings the service-account lookup of the runtime version reads.
    static let runtimeLookup = ["INTROSPECTION_CLIENT_ID", "INTROSPECTION_CLIENT_SECRET", "INTROSPECTION_RUNTIME"]

    static func requires(_ names: String...) -> ConditionTrait { requires(names) }

    /// Enabled when the Control Plane URL and every named setting are set.
    static func requires(_ names: [String]) -> ConditionTrait {
        let controlPlane = value("INTROSPECTION_BASE_API_URL") ?? value("INTROSPECTION_BASE_URL")
        let settings = (controlPlane == nil ? ["INTROSPECTION_BASE_URL"] : []) + names.filter { value($0) == nil }
        var seen: Set<String> = []
        let missing = settings.filter { seen.insert($0).inserted }
        return .enabled(
            if: missing.isEmpty, Comment(rawValue: "\(missing.joined(separator: ", ")) \(missing.count == 1 ? "is" : "are") not set"))
    }
}
