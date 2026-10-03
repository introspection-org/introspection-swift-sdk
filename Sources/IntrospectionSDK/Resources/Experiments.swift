import Foundation

// MARK: Models

/// Experiment lifecycle status.
public struct ExperimentStatus: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let draft: ExperimentStatus = "draft"
    public static let running: ExperimentStatus = "running"
    public static let ended: ExperimentStatus = "ended"
    public static let cancelled: ExperimentStatus = "cancelled"
}

/// Whether an experiment goal is maximized or minimized.
public struct ExperimentGoalDirection: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let maximize: ExperimentGoalDirection = "maximize"
    public static let minimize: ExperimentGoalDirection = "minimize"
}

/// Bounds (0 to 1) a goal component must stay within.
public struct ExperimentGoalGuard: Codable, Sendable, Hashable {
    public var min: Double?
    public var max: Double?

    public init(min: Double? = nil, max: Double? = nil) {
        self.min = min
        self.max = max
    }
}

/// One weighted component of an experiment goal: a judge (`source: "judge"`) or a telemetry column.
public struct ExperimentGoalComponent: Codable, Sendable, Hashable {
    /// `judge` or `telemetry`.
    public var source: String
    public var judgeId: String?
    public var judgeDefinitionHash: String?
    public var column: String?
    public var aggregation: String?
    public var weight: Double?
    public var `guard`: ExperimentGoalGuard?

    public init(
        source: String,
        judgeId: String? = nil,
        judgeDefinitionHash: String? = nil,
        column: String? = nil,
        aggregation: String? = nil,
        weight: Double? = nil,
        guard: ExperimentGoalGuard? = nil
    ) {
        self.source = source
        self.judgeId = judgeId
        self.judgeDefinitionHash = judgeDefinitionHash
        self.column = column
        self.aggregation = aggregation
        self.weight = weight
        self.guard = `guard`
    }

    /// A judge-scored component.
    public static func judge(_ judgeId: String, weight: Double = 1, guard: ExperimentGoalGuard? = nil) -> ExperimentGoalComponent {
        ExperimentGoalComponent(source: "judge", judgeId: judgeId, weight: weight, guard: `guard`)
    }

    /// A telemetry-column component.
    public static func telemetry(
        column: String, aggregation: String? = nil, weight: Double = 1, guard: ExperimentGoalGuard? = nil
    ) -> ExperimentGoalComponent {
        ExperimentGoalComponent(source: "telemetry", column: column, aggregation: aggregation, weight: weight, guard: `guard`)
    }

    private enum CodingKeys: String, CodingKey {
        case source, column, aggregation, weight
        case judgeId = "judge_id"
        case judgeDefinitionHash = "judge_definition_hash"
        case `guard`
    }
}

/// The composite objective the experiment's bandit optimizes.
public struct ExperimentGoal: Codable, Sendable, Hashable {
    public var kind: String?
    public var direction: ExperimentGoalDirection?
    public var components: [ExperimentGoalComponent]

    public init(kind: String? = "composite", direction: ExperimentGoalDirection? = nil, components: [ExperimentGoalComponent] = []) {
        self.kind = kind
        self.direction = direction
        self.components = components
    }

    private enum CodingKeys: String, CodingKey { case kind, direction, components }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        direction = try container.decodeIfPresent(ExperimentGoalDirection.self, forKey: .direction)
        components = try container.decodeIfPresent([ExperimentGoalComponent].self, forKey: .components) ?? []
    }
}

/// One arm of an experiment: a runtime version, optionally with agent overrides.
public struct ExperimentArm: Codable, Sendable, Hashable {
    public var id: String?
    public var runtimeId: String
    public var armLabel: String?
    /// `{called: target}` agent name substitutions.
    public var agentOverrides: [String: String]?
    public var initialWeight: Int?

    public init(
        id: String? = nil, runtimeId: String, armLabel: String? = nil, agentOverrides: [String: String]? = nil, initialWeight: Int? = nil
    ) {
        self.id = id
        self.runtimeId = runtimeId
        self.armLabel = armLabel
        self.agentOverrides = agentOverrides
        self.initialWeight = initialWeight
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case runtimeId = "runtime_id"
        case armLabel = "arm_label"
        case agentOverrides = "agent_overrides"
        case initialWeight = "initial_weight"
    }
}

/// An adaptive (Thompson-sampling) experiment across runtime versions of one group.
public struct Experiment: Codable, Sendable, Hashable {
    public var id: String
    public var orgId: String?
    public var projectId: String?
    public var name: String?
    public var description: String?
    public var runtimeGroupId: String?
    public var environment: RuntimeEnvironment?
    public var status: ExperimentStatus?
    public var routingStrategy: String?
    public var goalJson: ExperimentGoal?
    public var scoringIntervalSeconds: Int?
    public var hashKeyFields: [String]?
    public var sampleRate: Double?
    public var arms: [ExperimentArm]?
    public var posteriorJson: JSONObject?
    public var weightsJson: [String: Double]?
    public var startedAt: Date?
    public var endedAt: Date?
    public var haltedAt: Date?
    public var haltedReason: String?
    public var archivedAt: Date?
    public var createdByMemberId: String?
    public var createdAt: Date?
    public var updatedAt: Date?

    public init(
        id: String, orgId: String? = nil, projectId: String? = nil, name: String? = nil, description: String? = nil,
        runtimeGroupId: String? = nil, environment: RuntimeEnvironment? = nil, status: ExperimentStatus? = nil,
        routingStrategy: String? = nil, goalJson: ExperimentGoal? = nil, scoringIntervalSeconds: Int? = nil,
        hashKeyFields: [String]? = nil, sampleRate: Double? = nil, arms: [ExperimentArm]? = nil,
        posteriorJson: JSONObject? = nil, weightsJson: [String: Double]? = nil, startedAt: Date? = nil,
        endedAt: Date? = nil, haltedAt: Date? = nil, haltedReason: String? = nil, archivedAt: Date? = nil,
        createdByMemberId: String? = nil, createdAt: Date? = nil, updatedAt: Date? = nil
    ) {
        self.id = id
        self.orgId = orgId
        self.projectId = projectId
        self.name = name
        self.description = description
        self.runtimeGroupId = runtimeGroupId
        self.environment = environment
        self.status = status
        self.routingStrategy = routingStrategy
        self.goalJson = goalJson
        self.scoringIntervalSeconds = scoringIntervalSeconds
        self.hashKeyFields = hashKeyFields
        self.sampleRate = sampleRate
        self.arms = arms
        self.posteriorJson = posteriorJson
        self.weightsJson = weightsJson
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.haltedAt = haltedAt
        self.haltedReason = haltedReason
        self.archivedAt = archivedAt
        self.createdByMemberId = createdByMemberId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, description, environment, status, arms
        case orgId = "org_id"
        case projectId = "project_id"
        case runtimeGroupId = "runtime_group_id"
        case routingStrategy = "routing_strategy"
        case goalJson = "goal_json"
        case scoringIntervalSeconds = "scoring_interval_seconds"
        case hashKeyFields = "hash_key_fields"
        case sampleRate = "sample_rate"
        case posteriorJson = "posterior_json"
        case weightsJson = "weights_json"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case haltedAt = "halted_at"
        case haltedReason = "halted_reason"
        case archivedAt = "archived_at"
        case createdByMemberId = "created_by_member_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// One arm in an experiment create request.
public struct ExperimentArmCreate: Encodable, Sendable, Hashable {
    public var runtimeId: String
    public var armLabel: String
    public var agentOverrides: [String: String]?

    public init(runtimeId: String, armLabel: String, agentOverrides: [String: String]? = nil) {
        self.runtimeId = runtimeId
        self.armLabel = armLabel
        self.agentOverrides = agentOverrides
    }

    private enum CodingKeys: String, CodingKey {
        case runtimeId = "runtime_id"
        case armLabel = "arm_label"
        case agentOverrides = "agent_overrides"
    }
}

/// Body of `POST /v1/experiments`. Creates a draft that routes nothing until started.
public struct ExperimentCreate: Encodable, Sendable, Hashable {
    /// Project slug or id.
    public var project: String
    /// Runtime group slug or id under test; every arm must be a version in it.
    public var runtime: String
    public var name: String
    /// Needs at least one positive-weight judge component.
    public var goalJson: ExperimentGoal
    /// 2 to 20 arms.
    public var arms: [ExperimentArmCreate]
    public var description: String?
    public var environment: RuntimeEnvironment?
    public var scoringIntervalSeconds: Int?
    public var hashKeyFields: [String]?
    /// Below 1.0 only on the production lane.
    public var sampleRate: Double?

    public init(
        project: String,
        runtime: String,
        name: String,
        goalJson: ExperimentGoal,
        arms: [ExperimentArmCreate],
        description: String? = nil,
        environment: RuntimeEnvironment? = nil,
        scoringIntervalSeconds: Int? = nil,
        hashKeyFields: [String]? = nil,
        sampleRate: Double? = nil
    ) {
        self.project = project
        self.runtime = runtime
        self.name = name
        self.goalJson = goalJson
        self.arms = arms
        self.description = description
        self.environment = environment
        self.scoringIntervalSeconds = scoringIntervalSeconds
        self.hashKeyFields = hashKeyFields
        self.sampleRate = sampleRate
    }

    private enum CodingKeys: String, CodingKey {
        case project, runtime, name, arms, description, environment
        case goalJson = "goal_json"
        case scoringIntervalSeconds = "scoring_interval_seconds"
        case hashKeyFields = "hash_key_fields"
        case sampleRate = "sample_rate"
    }
}

/// Body of `PATCH /v1/experiments/{id}`. While running only `description` stays editable.
public struct ExperimentUpdate: Encodable, Sendable, Hashable {
    public var name: String?
    public var description: String?
    public var goalJson: ExperimentGoal?
    public var scoringIntervalSeconds: Int?
    public var hashKeyFields: [String]?
    public var sampleRate: Double?

    public init(
        name: String? = nil,
        description: String? = nil,
        goalJson: ExperimentGoal? = nil,
        scoringIntervalSeconds: Int? = nil,
        hashKeyFields: [String]? = nil,
        sampleRate: Double? = nil
    ) {
        self.name = name
        self.description = description
        self.goalJson = goalJson
        self.scoringIntervalSeconds = scoringIntervalSeconds
        self.hashKeyFields = hashKeyFields
        self.sampleRate = sampleRate
    }

    private enum CodingKeys: String, CodingKey {
        case name, description
        case goalJson = "goal_json"
        case scoringIntervalSeconds = "scoring_interval_seconds"
        case hashKeyFields = "hash_key_fields"
        case sampleRate = "sample_rate"
    }
}

/// Filters for `GET /v1/experiments`.
public struct ExperimentListParams: Sendable, Hashable {
    public var project: String?
    /// Runtime group slug or id.
    public var runtime: String?
    public var environment: RuntimeEnvironment?
    public var status: ExperimentStatus?
    public var limit: Int?
    public var next: String?

    public init(
        project: String? = nil,
        runtime: String? = nil,
        environment: RuntimeEnvironment? = nil,
        status: ExperimentStatus? = nil,
        limit: Int? = nil,
        next: String? = nil
    ) {
        self.project = project
        self.runtime = runtime
        self.environment = environment
        self.status = status
        self.limit = limit
        self.next = next
    }
}

// MARK: API

/// CRUD, lifecycle and runs for `/v1/experiments`. Call it as `client.experiments(id)` for a handle.
public struct ExperimentsAPI: Sendable {
    let client: IntrospectionClient

    public init(client: IntrospectionClient) { self.client = client }

    private var http: HTTPClient { client.controlPlane }

    private func path(_ id: String, _ suffix: String = "") -> String {
        "/v1/experiments/\(pathSegment(id))\(suffix)"
    }

    private func projectQuery(_ project: String?) -> Query {
        var query = Query()
        query.add("project", project)
        return query
    }

    /// List experiments matching `params`.
    public func list(_ params: ExperimentListParams = ExperimentListParams()) -> Paginator<Experiment> {
        var query = Query()
        query.add("project", params.project)
        query.add("runtime", params.runtime)
        query.add("environment", params.environment)
        query.add("status", params.status)
        query.add("limit", params.limit)
        return http.paginate("/v1/experiments", query: query, start: params.next)
    }

    /// Fetch one experiment.
    public func get(_ id: String, project: String? = nil) async throws -> Experiment {
        try await http.json("GET", path(id), query: projectQuery(project))
    }

    /// Create a draft experiment.
    public func create(_ body: ExperimentCreate) async throws -> Experiment {
        try await http.json("POST", "/v1/experiments", body: .encode(body))
    }

    /// Create a draft experiment from a raw Control Plane request document.
    public func create(document: JSONObject) async throws -> Experiment {
        try await http.json("POST", "/v1/experiments", body: .encode(document))
    }

    /// Update an experiment.
    public func update(_ id: String, _ body: ExperimentUpdate, project: String? = nil) async throws -> Experiment {
        try await http.json("PATCH", path(id), query: projectQuery(project), body: .encode(body))
    }

    /// Update an experiment from a raw request document.
    public func update(_ id: String, document: JSONObject, project: String? = nil) async throws -> Experiment {
        try await http.json("PATCH", path(id), query: projectQuery(project), body: .encode(document))
    }

    /// Soft-delete an experiment. A running experiment must be ended or cancelled first (409).
    public func delete(_ id: String, project: String? = nil) async throws {
        try await http.empty("DELETE", path(id), query: projectQuery(project))
    }

    /// Start routing traffic (draft to running).
    public func start(_ id: String, project: String? = nil) async throws -> Experiment {
        try await http.json("POST", path(id, "/start"), query: projectQuery(project))
    }

    /// End a running experiment.
    public func end(_ id: String, project: String? = nil) async throws -> Experiment {
        try await http.json("POST", path(id, "/end"), query: projectQuery(project))
    }

    /// Cancel an experiment.
    public func cancel(_ id: String, project: String? = nil) async throws -> Experiment {
        try await http.json("POST", path(id, "/cancel"), query: projectQuery(project))
    }

    /// `POST /v1/experiments/{id}/run`: mint a runner session spec. Requires a stable identity.
    public func openRunner(_ id: String, _ request: RunRequest = RunRequest(), project: String? = nil) async throws -> RunnerSpec {
        try await http.json("POST", path(id, "/run"), query: projectQuery(project), body: .encode(request))
    }

    /// Open a runner on the arm this identity is routed to.
    public func run(_ id: String, _ request: RunRequest = RunRequest(), project: String? = nil) async throws -> Runner {
        let spec = try await openRunner(id, request, project: project)
        return try Runner(
            spec: spec,
            template: client.dataPlane,
            controlPlane: http,
            source: .experiment(id: id, request: request, project: project)
        )
    }

    /// A handle on one experiment.
    public func callAsFunction(_ id: String, project: String? = nil) -> ExperimentHandle {
        ExperimentHandle(api: self, id: id, project: project)
    }
}

/// One experiment's lifecycle and runs.
public struct ExperimentHandle: Sendable {
    let api: ExperimentsAPI
    public let id: String
    public let project: String?

    public init(api: ExperimentsAPI, id: String, project: String? = nil) {
        self.api = api
        self.id = id
        self.project = project
    }

    /// Fetch the experiment.
    public func get() async throws -> Experiment { try await api.get(id, project: project) }

    /// Open a runner on the arm this identity is routed to.
    public func run(_ request: RunRequest = RunRequest()) async throws -> Runner {
        try await api.run(id, request, project: project)
    }

    /// Start the experiment.
    public func start() async throws -> Experiment { try await api.start(id, project: project) }

    /// End the experiment.
    public func end() async throws -> Experiment { try await api.end(id, project: project) }

    /// Cancel the experiment.
    public func cancel() async throws -> Experiment { try await api.cancel(id, project: project) }
}

extension IntrospectionClient {
    /// Experiments: CRUD, lifecycle and runs. Call it as `client.experiments(id)` for a handle.
    public var experiments: ExperimentsAPI { ExperimentsAPI(client: self) }
}
