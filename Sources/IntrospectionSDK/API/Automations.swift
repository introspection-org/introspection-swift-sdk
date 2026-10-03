import Foundation

// MARK: Enums

/// How an automation is triggered.
public struct AutomationTriggerType: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public init(from decoder: any Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static let cron: AutomationTriggerType = "cron"
    public static let manual: AutomationTriggerType = "manual"
}

/// A platform-work automation kind. A prompt automation has no kind.
public struct AutomationKind: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public init(from decoder: any Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static let observationSynthesis: AutomationKind = "observation_synthesis"
    /// Requires `metadata.runtime_group_id`.
    public static let observationClustering: AutomationKind = "observation_clustering"
}

/// A built-in condition evaluated before an automation runs.
public struct AutomationConditionType: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public init(from decoder: any Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static let hasNewTasksSinceLastRun: AutomationConditionType = "has_new_tasks_since_last_run"
    public static let lastRunIssuesResolved: AutomationConditionType = "last_run_issues_resolved"
    public static let noLiveTaskForAutomation: AutomationConditionType = "no_live_task_for_automation"
}

/// Outcome of one automation execution attempt.
public struct AutomationExecutionStatus: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public init(from decoder: any Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static let triggered: AutomationExecutionStatus = "triggered"
    public static let cancelled: AutomationExecutionStatus = "cancelled"
    public static let failed: AutomationExecutionStatus = "failed"
    public static let skipped: AutomationExecutionStatus = "skipped"
}

// MARK: Metadata

/// One condition stored in an automation's metadata.
public struct AutomationCondition: Codable, Sendable, Hashable {
    public var type: AutomationConditionType
    public var runtimeGroupId: String?

    enum CodingKeys: String, CodingKey {
        case type
        case runtimeGroupId = "runtime_group_id"
    }

    public init(type: AutomationConditionType, runtimeGroupId: String? = nil) {
        self.type = type
        self.runtimeGroupId = runtimeGroupId
    }
}

/// A repository a task-backed automation clones (`owner/name` plus an optional ref).
public struct AutomationRepositoryRef: Codable, Sendable, Hashable {
    public var repo: String
    public var ref: String?

    public init(repo: String, ref: String? = nil) {
        self.repo = repo
        self.ref = ref
    }
}

/// The typed shape of an automation's `metadata` object.
public struct AutomationMetadata: Codable, Sendable, Hashable {
    public var runtimeGroupId: String?
    public var repositories: [AutomationRepositoryRef]?
    /// Several cron expressions; `cron_schedule` on the automation is the single-schedule form.
    public var cronSchedules: [String]?
    /// IANA time zone the cron schedules are evaluated in.
    public var timezone: String?
    public var operatorDefault: String?
    public var conditions: [AutomationCondition]?

    enum CodingKeys: String, CodingKey {
        case runtimeGroupId = "runtime_group_id"
        case repositories
        case cronSchedules = "cron_schedules"
        case timezone
        case operatorDefault = "operator_default"
        case conditions
    }

    public init(
        runtimeGroupId: String? = nil,
        repositories: [AutomationRepositoryRef]? = nil,
        cronSchedules: [String]? = nil,
        timezone: String? = nil,
        operatorDefault: String? = nil,
        conditions: [AutomationCondition]? = nil
    ) {
        self.runtimeGroupId = runtimeGroupId
        self.repositories = repositories
        self.cronSchedules = cronSchedules
        self.timezone = timezone
        self.operatorDefault = operatorDefault
        self.conditions = conditions
    }

    /// As a JSON object for `AutomationCreate.metadata` / `AutomationUpdate.metadata`.
    public func jsonObject() throws -> JSONObject {
        try JSONValue.from(self).objectValue ?? [:]
    }
}

// MARK: Models

/// A stored automation: scheduled agent work, or platform work when `kind` is set.
public struct Automation: Codable, Sendable, Hashable {
    public let id: String
    public let orgId: String?
    public let projectId: String?
    public let name: String
    public let description: String?
    public let enabled: Bool?
    public let triggerType: AutomationTriggerType?
    public let cronSchedule: String?
    public let kind: AutomationKind?
    public let prompt: String?
    /// Open-ended metadata; read the known fields with `typedMetadata`.
    public let metadata: JSONObject?
    public let tags: [String]?
    public let lastTriggeredAt: Date?
    public let nextTriggerAt: Date?
    public let agentMemberId: String?
    public let createdByMemberId: String?
    /// Why the scheduler will not run this automation, when it will not.
    public let executionBlockedReason: String?
    /// Whether the caller may edit it.
    public let canManage: Bool?
    /// `operator` for a prompt automation, nil for platform work.
    public let ownerRole: String?
    public let createdAt: Date?
    public let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case orgId = "org_id"
        case projectId = "project_id"
        case name, description, enabled
        case triggerType = "trigger_type"
        case cronSchedule = "cron_schedule"
        case kind, prompt, metadata, tags
        case lastTriggeredAt = "last_triggered_at"
        case nextTriggerAt = "next_trigger_at"
        case agentMemberId = "agent_member_id"
        case createdByMemberId = "created_by_member_id"
        case executionBlockedReason = "execution_blocked_reason"
        case canManage = "can_manage"
        case ownerRole = "owner_role"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// `metadata` decoded into its typed shape, or nil if it does not fit.
    public var typedMetadata: AutomationMetadata? {
        guard let metadata else { return nil }
        return try? JSONValue.object(metadata).decode(AutomationMetadata.self)
    }
}

/// Body of `POST /v1/automations`.
public struct AutomationCreate: Encodable, Sendable, Hashable {
    public var name: String
    public var triggerType: AutomationTriggerType
    public var description: String?
    public var cronSchedule: String?
    /// Omit for a prompt automation (which then needs `prompt`).
    public var kind: AutomationKind?
    public var prompt: String?
    public var metadata: JSONObject?
    public var enabled: Bool?

    enum CodingKeys: String, CodingKey {
        case name
        case triggerType = "trigger_type"
        case description
        case cronSchedule = "cron_schedule"
        case kind, prompt, metadata, enabled
    }

    public init(
        name: String,
        triggerType: AutomationTriggerType,
        description: String? = nil,
        cronSchedule: String? = nil,
        kind: AutomationKind? = nil,
        prompt: String? = nil,
        metadata: JSONObject? = nil,
        enabled: Bool? = nil
    ) {
        self.name = name
        self.triggerType = triggerType
        self.description = description
        self.cronSchedule = cronSchedule
        self.kind = kind
        self.prompt = prompt
        self.metadata = metadata
        self.enabled = enabled
    }
}

/// Body of `PATCH /v1/automations/{id}`. `kind` and `trigger_type` are immutable; `metadata` replaces wholesale.
public struct AutomationUpdate: Encodable, Sendable, Hashable {
    public var name: String?
    public var description: String?
    public var cronSchedule: String?
    public var prompt: String?
    public var metadata: JSONObject?
    public var enabled: Bool?

    enum CodingKeys: String, CodingKey {
        case name, description
        case cronSchedule = "cron_schedule"
        case prompt, metadata, enabled
    }

    public init(
        name: String? = nil,
        description: String? = nil,
        cronSchedule: String? = nil,
        prompt: String? = nil,
        metadata: JSONObject? = nil,
        enabled: Bool? = nil
    ) {
        self.name = name
        self.description = description
        self.cronSchedule = cronSchedule
        self.prompt = prompt
        self.metadata = metadata
        self.enabled = enabled
    }
}

/// Filters for `GET /v1/automations`.
public struct AutomationListParams: Sendable, Hashable {
    /// Page size, 1...1000 (server default 100).
    public var limit: Int?
    /// Starting cursor.
    public var next: String?
    public var kind: AutomationKind?
    public var enabled: Bool?

    public init(
        limit: Int? = nil,
        next: String? = nil,
        kind: AutomationKind? = nil,
        enabled: Bool? = nil
    ) {
        self.limit = limit
        self.next = next
        self.kind = kind
        self.enabled = enabled
    }

    var query: Query {
        var query = Query()
        query.add("limit", limit)
        query.add("kind", kind)
        query.add("enabled", enabled)
        return query
    }
}

/// Response of a manual trigger.
public struct AutomationTriggerResponse: Codable, Sendable, Hashable {
    public let status: AutomationExecutionStatus
    public let automationId: String?
    public let taskId: String?
    public let reason: String?

    enum CodingKeys: String, CodingKey {
        case status
        case automationId = "automation_id"
        case taskId = "task_id"
        case reason
    }
}

// MARK: API

/// Data Plane `/v1/automations`.
public struct AutomationsAPI: Sendable {
    let http: HTTPClient

    public init(http: HTTPClient) {
        self.http = http
    }

    /// List this project's automations.
    public func list(_ params: AutomationListParams = AutomationListParams()) -> Paginator<Automation> {
        http.paginate("/v1/automations", query: params.query, start: params.next, as: Automation.self)
    }

    /// Create an automation.
    public func create(_ body: AutomationCreate) async throws -> Automation {
        try await http.json("POST", "/v1/automations", body: try .encode(body), as: Automation.self)
    }

    /// Read one automation (soft-deleted ones included).
    public func get(_ automationId: String) async throws -> Automation {
        try await http.json("GET", "/v1/automations/\(pathSegment(automationId))", as: Automation.self)
    }

    /// Update an automation.
    public func update(_ automationId: String, _ body: AutomationUpdate) async throws -> Automation {
        try await http.json("PATCH", "/v1/automations/\(pathSegment(automationId))", body: try .encode(body), as: Automation.self)
    }

    /// Soft-delete an automation.
    public func delete(_ automationId: String) async throws {
        try await http.empty("DELETE", "/v1/automations/\(pathSegment(automationId))")
    }

    /// Run an automation now: `POST /v1/automations/{id}/trigger`. Legacy and admin-only
    /// (privileged members); returns `202` with the launched task.
    public func trigger(_ automationId: String) async throws -> AutomationTriggerResponse {
        try await http.json("POST", "/v1/automations/\(pathSegment(automationId))/trigger", as: AutomationTriggerResponse.self)
    }
}

extension DataPlaneConnection {
    /// Data Plane automations.
    public var automations: AutomationsAPI { AutomationsAPI(http: dataPlane) }
}
