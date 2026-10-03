import Foundation

// MARK: Run request

/// A runtime lane: `development`, `staging` or `production`.
public struct RuntimeEnvironment: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let development: RuntimeEnvironment = "development"
    public static let staging: RuntimeEnvironment = "staging"
    public static let production: RuntimeEnvironment = "production"
}

/// The end-user identity a runner (or a connector grant) is opened for.
public struct RunnerIdentity: Codable, Sendable, Hashable {
    public var userId: String?
    public var anonymousId: String?
    public var conversationId: String?
    /// Tags stamped on the `customer` member this identity mints, only when that member is new.
    public var tags: [String]?

    public init(userId: String? = nil, anonymousId: String? = nil, conversationId: String? = nil, tags: [String]? = nil) {
        self.userId = userId
        self.anonymousId = anonymousId
        self.conversationId = conversationId
        self.tags = tags
    }

    private enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case anonymousId = "anonymous_id"
        case conversationId = "conversation_id"
        case tags
    }
}

/// The SDK or library a caller reports in `RunCaller.library`.
public struct RunCallerLibrary: Codable, Sendable, Hashable {
    public var name: String?
    public var version: String?

    public init(name: String? = nil, version: String? = nil) {
        self.name = name
        self.version = version
    }
}

/// The page a caller reports in `RunCaller.page`.
public struct RunCallerPage: Codable, Sendable, Hashable {
    public var path: String?
    public var referrer: String?
    public var search: String?
    public var title: String?
    public var url: String?

    public init(path: String? = nil, referrer: String? = nil, search: String? = nil, title: String? = nil, url: String? = nil) {
        self.path = path
        self.referrer = referrer
        self.search = search
        self.title = title
        self.url = url
    }
}

/// Segment-style observability payload on a run. Stamped onto every task the
/// runner spawns as `metadata.caller`; routing never reads it.
public struct RunCaller: Codable, Sendable, Hashable {
    public var ip: String?
    public var userAgent: String?
    public var locale: String?
    public var library: RunCallerLibrary?
    public var page: RunCallerPage?
    /// Any other keys (`app`, `device`, `os`, `campaign`, ...), sent verbatim.
    public var extra: JSONObject

    public init(
        ip: String? = nil,
        userAgent: String? = nil,
        locale: String? = nil,
        library: RunCallerLibrary? = nil,
        page: RunCallerPage? = nil,
        extra: JSONObject = [:]
    ) {
        self.ip = ip
        self.userAgent = userAgent
        self.locale = locale
        self.library = library
        self.page = page
        self.extra = extra
    }

    private enum CodingKeys: String, CodingKey {
        case ip
        case userAgent = "user_agent"
        case locale, library, page
    }

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ip = try container.decodeIfPresent(String.self, forKey: .ip)
        userAgent = try container.decodeIfPresent(String.self, forKey: .userAgent)
        locale = try container.decodeIfPresent(String.self, forKey: .locale)
        library = try? container.decodeIfPresent(RunCallerLibrary.self, forKey: .library)
        page = try? container.decodeIfPresent(RunCallerPage.self, forKey: .page)
        let all = try decoder.container(keyedBy: AnyKey.self)
        var extra: JSONObject = [:]
        for key in all.allKeys where CodingKeys(rawValue: key.stringValue) == nil {
            extra[key.stringValue] = try all.decode(JSONValue.self, forKey: key)
        }
        self.extra = extra
    }

    public func encode(to encoder: Encoder) throws {
        var all = encoder.container(keyedBy: AnyKey.self)
        for (key, value) in extra where CodingKeys(rawValue: key) == nil {
            try all.encode(value, forKey: AnyKey(stringValue: key))
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(ip, forKey: .ip)
        try container.encodeIfPresent(userAgent, forKey: .userAgent)
        try container.encodeIfPresent(locale, forKey: .locale)
        try container.encodeIfPresent(library, forKey: .library)
        try container.encodeIfPresent(page, forKey: .page)
    }
}

/// Body of `POST /v1/runtimes/{id}/run` and `POST /v1/experiments/{id}/run`.
public struct RunRequest: Codable, Sendable, Hashable {
    /// A stable identity makes runtime traffic eligible for experiment sampling; required for an experiment run.
    public var identity: RunnerIdentity?
    public var caller: RunCaller?
    /// Entrypoint agent; omit for the runtime's default.
    public var agentName: String?
    /// Runner token lifetime, 60 to 86400 seconds (server default 3600).
    public var ttlSeconds: Int?
    /// Space-separated runner scopes, capped to the runner-grantable set. Use a narrow scope for a browser or app.
    public var scope: String?
    /// Environment whose bindings apply; only human member sessions may override their credential's.
    public var environment: RuntimeEnvironment?
    /// Pin one runtime version (by recipe) in the URL runtime's group for the initial task.
    public var recipeId: String?
    /// Set false to let identity-dependent bindings report unavailable instead of failing.
    public var bindingsRequired: Bool?

    public init(
        identity: RunnerIdentity? = nil,
        caller: RunCaller? = nil,
        agentName: String? = nil,
        ttlSeconds: Int? = nil,
        scope: String? = nil,
        environment: RuntimeEnvironment? = nil,
        recipeId: String? = nil,
        bindingsRequired: Bool? = nil
    ) {
        self.identity = identity
        self.caller = caller
        self.agentName = agentName
        self.ttlSeconds = ttlSeconds
        self.scope = scope
        self.environment = environment
        self.recipeId = recipeId
        self.bindingsRequired = bindingsRequired
    }

    private enum CodingKeys: String, CodingKey {
        case identity, caller, scope, environment
        case agentName = "agent_name"
        case ttlSeconds = "ttl_seconds"
        case recipeId = "recipe_id"
        case bindingsRequired = "bindings_required"
    }
}

// MARK: Runner spec

/// The Data Plane a runner is bound to.
public struct RunnerDeployment: Codable, Sendable, Hashable {
    /// Data Plane base URL every runner request goes to.
    public var endpoint: String
    public var slug: String?
    public var region: String?

    public init(endpoint: String, slug: String? = nil, region: String? = nil) {
        self.endpoint = endpoint
        self.slug = slug
        self.region = region
    }
}

/// The resolved runtime, experiment arm, recipe, identity and caller of a runner session.
public struct RunnerContext: Codable, Sendable, Hashable {
    public var runtimeId: String?
    public var runtimeGroupId: String?
    /// Set when the run was routed through an experiment.
    public var experimentId: String?
    public var recipeId: String?
    public var recipeRepositoryId: String?
    public var recipeGitRef: String?
    public var recipeGitCommitSha: String?
    public var armLabel: String?
    public var agentName: String?
    public var identity: RunnerIdentity?
    public var caller: RunCaller?

    public init(
        runtimeId: String? = nil,
        runtimeGroupId: String? = nil,
        experimentId: String? = nil,
        recipeId: String? = nil,
        recipeRepositoryId: String? = nil,
        recipeGitRef: String? = nil,
        recipeGitCommitSha: String? = nil,
        armLabel: String? = nil,
        agentName: String? = nil,
        identity: RunnerIdentity? = nil,
        caller: RunCaller? = nil
    ) {
        self.runtimeId = runtimeId
        self.runtimeGroupId = runtimeGroupId
        self.experimentId = experimentId
        self.recipeId = recipeId
        self.recipeRepositoryId = recipeRepositoryId
        self.recipeGitRef = recipeGitRef
        self.recipeGitCommitSha = recipeGitCommitSha
        self.armLabel = armLabel
        self.agentName = agentName
        self.identity = identity
        self.caller = caller
    }

    private enum CodingKeys: String, CodingKey {
        case runtimeId = "runtime_id"
        case runtimeGroupId = "runtime_group_id"
        case experimentId = "experiment_id"
        case recipeId = "recipe_id"
        case recipeRepositoryId = "recipe_repository_id"
        case recipeGitRef = "recipe_git_ref"
        case recipeGitCommitSha = "recipe_git_commit_sha"
        case armLabel = "arm_label"
        case agentName = "agent_name"
        case identity, caller
    }
}

/// The Control Plane `/run` response: a Data Plane endpoint plus the session
/// token that authenticates every runner request. Codable, so a backend can
/// mint it and hand it to an app that builds a `Runner` from it.
public struct RunnerSpec: Codable, Sendable, Hashable {
    public var sessionId: String
    public var deployment: RunnerDeployment
    /// The session locator JWT, sent as the Data Plane bearer token.
    public var sessionToken: String
    public var expiresAt: Date?
    public var runtimeContext: RunnerContext?

    public init(
        sessionId: String,
        deployment: RunnerDeployment,
        sessionToken: String,
        expiresAt: Date? = nil,
        runtimeContext: RunnerContext? = nil
    ) {
        self.sessionId = sessionId
        self.deployment = deployment
        self.sessionToken = sessionToken
        self.expiresAt = expiresAt
        self.runtimeContext = runtimeContext
    }

    private enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case deployment
        case sessionToken = "session_token"
        case expiresAt = "expires_at"
        case runtimeContext = "runtime_context"
    }
}

// MARK: Runner

/// Where a runner came from, so `refresh()` can ask the Control Plane again.
public enum RunnerSource: Sendable, Hashable {
    case runtime(id: String, request: RunRequest, project: String?)
    case experiment(id: String, request: RunRequest, project: String?)

    var path: String {
        switch self {
        case let .runtime(id, _, _): return "/v1/runtimes/\(pathSegment(id))/run"
        case let .experiment(id, _, _): return "/v1/experiments/\(pathSegment(id))/run"
        }
    }

    var request: RunRequest {
        switch self {
        case let .runtime(_, request, _), let .experiment(_, request, _): return request
        }
    }

    var project: String? {
        switch self {
        case let .runtime(_, _, project), let .experiment(_, _, project): return project
        }
    }
}

/// A live handle to a Data Plane sandbox session. Its `dataPlane` points at the
/// session's deployment with the session token as bearer, so every Data Plane
/// resource (`runner.tasks`, `runner.files`, ...) is available on it.
///
/// The Data Plane refreshes the session's access tokens itself; the SDK never
/// refreshes automatically. `refresh()` mints a brand-new session on demand.
public final class Runner: DataPlaneConnection, @unchecked Sendable {
    private let lock = NSLock()
    private var currentSpec: RunnerSpec
    private var currentHTTP: HTTPClient
    private let gate: RunnerGate
    private let template: HTTPClient
    private let controlPlane: HTTPClient?
    /// The run this runner was opened from; nil when built from a bare spec.
    public let source: RunnerSource?

    /// Build a runner from a spec, reusing `template`'s transport and options for Data Plane calls.
    /// Pass `controlPlane` and `source` to make `refresh()` available.
    public init(spec: RunnerSpec, template: HTTPClient, controlPlane: HTTPClient? = nil, source: RunnerSource? = nil) throws {
        let gate = RunnerGate()
        self.gate = gate
        self.template = template
        self.controlPlane = controlPlane
        self.source = source
        currentSpec = spec
        currentHTTP = try Self.makeHTTP(spec: spec, template: template, gate: gate)
    }

    /// Build a runner from a spec using the client's transport and options; `refresh()` is unavailable.
    public convenience init(spec: RunnerSpec, client: IntrospectionClient) throws {
        try self.init(spec: spec, template: client.dataPlane)
    }

    /// Build a runner from a spec minted elsewhere (for example by your backend).
    public convenience init(
        spec: RunnerSpec,
        transport: any HTTPTransport = URLSessionTransport(),
        options: HTTPClient.Options = HTTPClient.Options()
    ) throws {
        let template = HTTPClient(baseURL: URL(fileURLWithPath: "/"), transport: transport, options: options)
        try self.init(spec: spec, template: template)
    }

    private static func makeHTTP(spec: RunnerSpec, template: HTTPClient, gate: RunnerGate) throws -> HTTPClient {
        guard let url = URL(string: spec.deployment.endpoint), url.scheme != nil, url.host != nil else {
            throw IntrospectionError(
                kind: .invalidRequest,
                message: "Runner deployment endpoint is not a valid URL: '\(spec.deployment.endpoint)'"
            )
        }
        return template.with(baseURL: url, credentials: RunnerCredentials(token: spec.sessionToken, gate: gate))
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    /// The Data Plane client bound to this runner's deployment and session token.
    public var dataPlane: HTTPClient { withLock { currentHTTP } }

    /// The current spec (replaced by `refresh()`).
    public var spec: RunnerSpec { withLock { currentSpec } }

    /// Session id assigned by the Control Plane.
    public var sessionId: String { spec.sessionId }

    /// The session token sent as the Data Plane bearer.
    public var sessionToken: String { spec.sessionToken }

    /// When the session expires.
    public var expiresAt: Date? { spec.expiresAt }

    /// The Data Plane deployment (endpoint, slug, region).
    public var deployment: RunnerDeployment { spec.deployment }

    /// The Data Plane base URL.
    public var dataPlaneEndpoint: URL { dataPlane.baseURL }

    /// Resolved runtime, experiment arm, recipe and identity.
    public var context: RunnerContext { spec.runtimeContext ?? RunnerContext() }

    /// The resolved runtime id.
    public var runtimeId: String? { spec.runtimeContext?.runtimeId }

    /// The resolved runtime group id.
    public var runtimeGroupId: String? { spec.runtimeContext?.runtimeGroupId }

    /// The experiment that routed this run, if any.
    public var experimentId: String? { spec.runtimeContext?.experimentId }

    /// True once `close()` has been called.
    public var isClosed: Bool { gate.isClosed }

    /// Mint a fresh session from the original run and repoint this runner at it.
    public func refresh() async throws {
        guard !gate.isClosed else { throw RunnerGate.closedError }
        guard let source, let controlPlane else {
            throw IntrospectionError(
                kind: .invalidRequest,
                message: "This runner was built from a bare spec and cannot refresh; open a new one from its runtime"
            )
        }
        var query = Query()
        query.add("project", source.project)
        let fresh = try await controlPlane.json(
            "POST", source.path, query: query, body: .encode(source.request), as: RunnerSpec.self
        )
        let http = try Self.makeHTTP(spec: fresh, template: template, gate: gate)
        withLock {
            currentSpec = fresh
            currentHTTP = http
        }
    }

    /// Mark the runner closed locally: later requests fail with `runnerExpired`
    /// before reaching the network. No server-side revoke is performed.
    public func close() {
        gate.close()
    }
}

/// Shared closed flag between a runner and its credentials.
final class RunnerGate: @unchecked Sendable {
    private let lock = NSLock()
    private var closed = false

    static let closedError = IntrospectionError(
        kind: .runnerExpired, message: "Runner has been closed", status: 401, code: "runner_expired"
    )

    var isClosed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return closed
    }

    func close() {
        lock.lock()
        closed = true
        lock.unlock()
    }
}

/// The session token as a bearer, refusing every request once the runner is closed.
struct RunnerCredentials: CredentialProvider {
    let token: String
    let gate: RunnerGate

    func authorization() async throws -> String? {
        if gate.isClosed { throw RunnerGate.closedError }
        return "Bearer \(token)"
    }
}
