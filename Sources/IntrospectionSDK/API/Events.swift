import Foundation

/// The event families served by `/v1/events`. Unknown names are preserved.
public struct IntrospectionEventName: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }

    public static let annotation = IntrospectionEventName(rawValue: PlatformEventNames.annotation)
    public static let feedback = IntrospectionEventName(rawValue: PlatformEventNames.feedback)
    public static let observation = IntrospectionEventName(rawValue: PlatformEventNames.observation)
    public static let observationClusteringRun = IntrospectionEventName(rawValue: PlatformEventNames.observationClusteringRun)
    public static let judgement = IntrospectionEventName(rawValue: PlatformEventNames.judgement)
    public static let pattern = IntrospectionEventName(rawValue: PlatformEventNames.pattern)
    public static let patternAssignment = IntrospectionEventName(rawValue: PlatformEventNames.patternAssignment)
    /// The virtual projection of SDK `track()` events.
    public static let track = IntrospectionEventName(rawValue: PlatformEventNames.track)
    public static let issue = IntrospectionEventName(rawValue: PlatformEventNames.issue)
    public static let repositoryCreated = IntrospectionEventName(rawValue: PlatformEventNames.repositoryCreated)
    public static let repositoryPushed = IntrospectionEventName(rawValue: PlatformEventNames.repositoryPushed)
    public static let repositoryMerge = IntrospectionEventName(rawValue: PlatformEventNames.repositoryMerge)

    /// Every family the platform serves, in its registry order.
    public static let allCases: [IntrospectionEventName] = [
        .annotation, .feedback, .observation, .observationClusteringRun, .judgement, .pattern, .patternAssignment, .track,
        .issue, .repositoryCreated, .repositoryPushed, .repositoryMerge,
    ]
}

/// Event sort fields. Valid values depend on the family.
public struct EventSortField: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }

    public static let timestamp: EventSortField = "timestamp"
    /// Observations.
    public static let observedAt: EventSortField = "observed_at"
    /// Patterns.
    public static let createdAt: EventSortField = "created_at"
    /// Patterns (default).
    public static let updatedAt: EventSortField = "updated_at"
    /// Patterns.
    public static let lastDetectedAt: EventSortField = "last_detected_at"
}

/// One `/v1/events` row: the common envelope plus a family-specific `payload`.
public struct IntrospectionEvent: Codable, Sendable, Hashable {
    public var id: String
    /// Per-family semantics: `observed_at` for observations, `updated_at` for patterns, emit time otherwise.
    public var timestamp: Date?
    public var eventName: IntrospectionEventName
    public var traceId: String?
    public var spanId: String?
    public var conversationId: String?
    public var serviceName: String?
    public var environment: String?
    public var runtimeGroupId: String?
    public var runtimeId: String?
    public var experimentId: String?
    public var recipeGitCommitSha: String?
    public var payload: JSONValue?

    public init(
        id: String, eventName: IntrospectionEventName, timestamp: Date? = nil, traceId: String? = nil,
        spanId: String? = nil, conversationId: String? = nil, serviceName: String? = nil,
        environment: String? = nil, runtimeGroupId: String? = nil, runtimeId: String? = nil,
        experimentId: String? = nil, recipeGitCommitSha: String? = nil, payload: JSONValue? = nil
    ) {
        self.id = id
        self.eventName = eventName
        self.timestamp = timestamp
        self.traceId = traceId
        self.spanId = spanId
        self.conversationId = conversationId
        self.serviceName = serviceName
        self.environment = environment
        self.runtimeGroupId = runtimeGroupId
        self.runtimeId = runtimeId
        self.experimentId = experimentId
        self.recipeGitCommitSha = recipeGitCommitSha
        self.payload = payload
    }

    private enum CodingKeys: String, CodingKey {
        case id, timestamp, environment, payload
        case eventName = "event_name"
        case traceId = "trace_id"
        case spanId = "span_id"
        case conversationId = "conversation_id"
        case serviceName = "service_name"
        case runtimeGroupId = "runtime_group_id"
        case runtimeId = "runtime_id"
        case experimentId = "experiment_id"
        case recipeGitCommitSha = "recipe_git_commit_sha"
    }

    /// Decode the payload into a type of your choosing.
    public func decodePayload<T: Decodable>(_ type: T.Type = T.self) throws -> T {
        try (payload ?? .null).decode(T.self)
    }

    private func familyPayload<T: Decodable>(_ family: IntrospectionEventName) -> T? {
        guard eventName == family, let payload else { return nil }
        return try? payload.decode(T.self)
    }

    /// The payload when this is an `introspection.observation` row.
    public var observation: ObservationPayload? { familyPayload(.observation) }
    /// The payload when this is an `introspection.pattern` row.
    public var pattern: PatternPayload? { familyPayload(.pattern) }
    /// The payload when this is an `introspection.pattern.assignment` row.
    public var patternAssignment: PatternAssignmentPayload? { familyPayload(.patternAssignment) }
    /// The payload when this is an `introspection.observation_clustering.run` row.
    public var clusteringRun: ClusteringRunPayload? { familyPayload(.observationClusteringRun) }
    /// The payload when this is an `introspection.feedback` row.
    public var feedback: FeedbackPayload? { familyPayload(.feedback) }
    /// The payload when this is an `introspection.annotation` row.
    public var annotation: AnnotationPayload? { familyPayload(.annotation) }
    /// The payload when this is an `introspection.judgement` row.
    public var judgement: JudgementPayload? { familyPayload(.judgement) }
    /// The payload when this is an `introspection.track` row.
    public var track: TrackPayload? { familyPayload(.track) }
}

/// A resolved observation (supersession applied, current pattern assignment joined).
public struct ObservationPayload: Codable, Sendable, Hashable {
    public var observationId: String?
    public var lens: String?
    public var label: String?
    public var summary: String?
    public var confidence: Double?
    public var sentiment: String?
    public var resolution: String?
    public var evidenceRefs: [String]?
    public var sourceHash: String?
    public var replacesObservationId: String?
    /// Current pattern assignment; nil when unassigned.
    public var patternId: String?
    public var assignmentScore: Double?
    public var assignmentMethod: String?
    public var metadata: JSONObject?

    private enum CodingKeys: String, CodingKey {
        case lens, label, summary, confidence, sentiment, resolution, metadata
        case observationId = "observation_id"
        case evidenceRefs = "evidence_refs"
        case sourceHash = "source_hash"
        case replacesObservationId = "replaces_observation_id"
        case patternId = "pattern_id"
        case assignmentScore = "assignment_score"
        case assignmentMethod = "assignment_method"
    }
}

/// A folded pattern catalog row (the pattern as it currently is).
public struct PatternPayload: Codable, Sendable, Hashable {
    public var patternId: String?
    /// Latest lifecycle action: `created`, `updated` or `retired`.
    public var action: String?
    public var name: String?
    public var description: String?
    public var lens: String?
    /// `active` or `retired`.
    public var status: String?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var retiredAt: Date?
    public var lastDetectedAt: Date?
    public var reason: String?
    public var replacementPatternId: String?
    public var derivedFromPatternId: String?
    public var runId: String?

    private enum CodingKeys: String, CodingKey {
        case action, name, description, lens, status, reason
        case patternId = "pattern_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case retiredAt = "retired_at"
        case lastDetectedAt = "last_detected_at"
        case replacementPatternId = "replacement_pattern_id"
        case derivedFromPatternId = "derived_from_pattern_id"
        case runId = "run_id"
    }
}

/// An observation-to-pattern assignment.
public struct PatternAssignmentPayload: Codable, Sendable, Hashable {
    public var observationId: String?
    /// Nil means explicitly unassigned.
    public var patternId: String?
    public var method: String?
    public var runId: String?
    public var score: Double?

    private enum CodingKeys: String, CodingKey {
        case method, score
        case observationId = "observation_id"
        case patternId = "pattern_id"
        case runId = "run_id"
    }
}

/// One clustering run over observations.
public struct ClusteringRunPayload: Codable, Sendable, Hashable {
    public var runId: String?
    public var lens: String?
    public var status: String?
    public var trigger: String?
    public var observationCount: Int?
    public var patternCount: Int?
    public var noiseCount: Int?
    public var params: JSONObject?
    public var replacesRunId: String?
    public var error: String?

    private enum CodingKeys: String, CodingKey {
        case lens, status, trigger, params, error
        case runId = "run_id"
        case observationCount = "observation_count"
        case patternCount = "pattern_count"
        case noiseCount = "noise_count"
        case replacesRunId = "replaces_run_id"
    }
}

/// One feedback event.
public struct FeedbackPayload: Codable, Sendable, Hashable {
    /// The feedback label, such as `thumbs_up`.
    public var name: String?
    public var comments: String?
    public var value: Double?
    public var userId: String?
    public var anonymousId: String?
    public var authorMemberId: String?
    /// Emitted sentiment, never derived server-side.
    public var sentiment: String?
    public var previousResponseId: String?
    public var agentName: String?
    public var agentId: String?
    public var properties: JSONObject?

    private enum CodingKeys: String, CodingKey {
        case name, comments, value, sentiment, properties
        case userId = "user_id"
        case anonymousId = "anonymous_id"
        case authorMemberId = "author_member_id"
        case previousResponseId = "previous_response_id"
        case agentName = "agent_name"
        case agentId = "agent_id"
    }
}

/// One member-authored annotation mutation.
public struct AnnotationPayload: Codable, Sendable, Hashable {
    public var memberId: String?
    public var actorMemberId: String?
    public var actorMemberType: String?
    /// Complete label snapshot, when this event changed labels.
    public var labels: [String]?
    public var comment: String?
    /// Complete reviewer snapshot, when this event changed assignments.
    public var assigneeMemberIds: [String]?

    private enum CodingKeys: String, CodingKey {
        case labels, comment
        case memberId = "member_id"
        case actorMemberId = "actor_member_id"
        case actorMemberType = "actor_member_type"
        case assigneeMemberIds = "assignee_member_ids"
    }
}

/// One judgement.
public struct JudgementPayload: Codable, Sendable, Hashable {
    public var judgementId: String?
    public var judgeId: String?
    /// The verdict.
    public var result: String?
    /// Execution outcome (`ok` or `error`), distinct from the verdict.
    public var status: String?
    public var errorClass: String?
    public var errorMessage: String?
    public var sourceComponent: String?
    public var reasoning: String?
    public var definitionHash: String?
    public var engineVersion: String?
    public var judgeProvider: String?
    public var judgeModel: String?
    public var contractVersion: String?
    public var sequenceHash: String?
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var totalTokens: Int?
    public var experimentArmId: String?

    private enum CodingKeys: String, CodingKey {
        case result, status, reasoning
        case judgementId = "judgement_id"
        case judgeId = "judge_id"
        case errorClass = "error_class"
        case errorMessage = "error_message"
        case sourceComponent = "source_component"
        case definitionHash = "definition_hash"
        case engineVersion = "engine_version"
        case judgeProvider = "judge_provider"
        case judgeModel = "judge_model"
        case contractVersion = "contract_version"
        case sequenceHash = "sequence_hash"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
        case experimentArmId = "experiment_arm_id"
    }
}

/// One SDK `track()` event, projected.
public struct TrackPayload: Codable, Sendable, Hashable {
    /// The name passed to `track()`.
    public var name: String?
    public var properties: JSONObject?
}

/// Filters for `GET /v1/events`. `eventName` is required; family-scoped filters are validated
/// server-side (an out-of-family filter is a 422). `lookback` is mutually exclusive with `start`/`end`.
public struct EventListParams: Sendable, Hashable {
    public var eventName: IntrospectionEventName
    public var limit: Int?
    public var next: String?
    public var sort: EventSortField?
    /// Sent as `direction` (server default `desc`).
    public var order: ReadOrder?
    /// Sent as `start_date` (inclusive).
    public var start: Date?
    /// Sent as `end_date` (inclusive).
    public var end: Date?
    /// Computed into `start_date = now - lookback`.
    public var lookback: ReadLookback?
    public var conversationId: String?
    public var conversationIds: [String]?
    public var serviceName: String?
    public var environment: String?
    public var runtimeGroupId: String?
    public var traceId: String?
    public var spanId: String?
    public var ownerKey: String?
    /// Sent as repeated `event_id` (max 500).
    public var eventIds: [String]?
    /// Observations: only rows with no runtime group.
    public var runtimeGroupUnattributed: Bool?
    /// Observations and patterns.
    public var lens: String?
    /// Observations: current pattern assignment.
    public var patternId: String?
    /// Observations: include superseded versions.
    public var includeSuperseded: Bool?
    /// Patterns: `active` or `retired`; issue requests: `open`, `resolved` or `cancelled`.
    public var status: String?
    /// Judgements.
    public var judgeId: String?
    /// Issues.
    public var issueId: String?
    /// Issues: the latest event per human request (sent as `request=true`).
    public var latestRequests: Bool?
    public var requestId: String?
    public var assigneeId: String?

    public init(
        eventName: IntrospectionEventName, limit: Int? = nil, next: String? = nil, sort: EventSortField? = nil,
        order: ReadOrder? = nil, start: Date? = nil, end: Date? = nil, lookback: ReadLookback? = nil,
        conversationId: String? = nil, conversationIds: [String]? = nil, serviceName: String? = nil,
        environment: String? = nil, runtimeGroupId: String? = nil, traceId: String? = nil, spanId: String? = nil,
        ownerKey: String? = nil, eventIds: [String]? = nil, runtimeGroupUnattributed: Bool? = nil,
        lens: String? = nil, patternId: String? = nil, includeSuperseded: Bool? = nil, status: String? = nil,
        judgeId: String? = nil, issueId: String? = nil, latestRequests: Bool? = nil, requestId: String? = nil,
        assigneeId: String? = nil
    ) {
        self.eventName = eventName
        self.limit = limit
        self.next = next
        self.sort = sort
        self.order = order
        self.start = start
        self.end = end
        self.lookback = lookback
        self.conversationId = conversationId
        self.conversationIds = conversationIds
        self.serviceName = serviceName
        self.environment = environment
        self.runtimeGroupId = runtimeGroupId
        self.traceId = traceId
        self.spanId = spanId
        self.ownerKey = ownerKey
        self.eventIds = eventIds
        self.runtimeGroupUnattributed = runtimeGroupUnattributed
        self.lens = lens
        self.patternId = patternId
        self.includeSuperseded = includeSuperseded
        self.status = status
        self.judgeId = judgeId
        self.issueId = issueId
        self.latestRequests = latestRequests
        self.requestId = requestId
        self.assigneeId = assigneeId
    }

    func query(now: Date) throws -> Query {
        var q = Query()
        q.add("event_name", eventName)
        q.add("limit", limit)
        q.add("sort", sort)
        try applyReadWindow(to: &q, order: order, start: start, end: end, lookback: lookback, now: now)
        q.add("conversation_id", conversationId)
        q.add("conversation_ids", conversationIds)
        q.add("service_name", serviceName)
        q.add("environment", environment)
        q.add("runtime_group_id", runtimeGroupId)
        q.add("trace_id", traceId)
        q.add("span_id", spanId)
        q.add("owner_key", ownerKey)
        q.add("event_id", eventIds)
        q.add("runtime_group_unattributed", runtimeGroupUnattributed)
        q.add("lens", lens)
        q.add("pattern_id", patternId)
        q.add("include_superseded", includeSuperseded)
        q.add("status", status)
        q.add("judge_id", judgeId)
        q.add("issue_id", issueId)
        q.add("request", latestRequests)
        q.add("request_id", requestId)
        q.add("assignee_id", assigneeId)
        return q
    }
}

/// Read-only platform events (`/v1/events`).
public struct EventsAPI: Sendable {
    let http: HTTPClient

    public init(http: HTTPClient) { self.http = http }

    /// List events of one family. Throws before any request when the window params conflict;
    /// a `lookback` is pinned to one `now` for every page.
    public func list(_ params: EventListParams) throws -> Paginator<IntrospectionEvent> {
        try list(params, now: Date())
    }

    func list(_ params: EventListParams, now: Date) throws -> Paginator<IntrospectionEvent> {
        http.paginate("/v1/events", query: try params.query(now: now), start: params.next)
    }

    /// Read one event by id, in any family.
    public func get(_ eventId: String) async throws -> IntrospectionEvent {
        try await http.json("GET", "/v1/events/\(pathSegment(eventId))")
    }
}

extension DataPlaneConnection {
    /// Platform events (observations, patterns, feedback, judgements, ...).
    public var events: EventsAPI { EventsAPI(http: dataPlane) }
}
