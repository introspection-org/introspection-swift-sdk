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
    /// Runs by hand, or once at a client-set `nextTriggerAt` (a one-off reminder).
    public static let manual: AutomationTriggerType = "manual"
}

/// A platform automation kind. A prompt automation a person created has no kind. Open-ended: an
/// unrecognised value decodes as its raw string.
public struct AutomationKind: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public init(from decoder: any Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// Project-wide: takes no `runtimeGroupId`.
    public static let observationSynthesis: AutomationKind = "observation_synthesis"
    public static let observationClustering: AutomationKind = "observation_clustering"
    /// The project's default check-in; runs as an agent task, so it carries a `prompt`.
    public static let projectCheckIn: AutomationKind = "project_check_in"
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

/// Why a trigger ran nothing (`introspection.automation.skipped`).
public struct AutomationSkipReason: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public init(from decoder: any Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static let automationDeleted: AutomationSkipReason = "automation_deleted"
    public static let executionBlocked: AutomationSkipReason = "execution_blocked"
    public static let conditionsNotMet: AutomationSkipReason = "conditions_not_met"
    public static let noProductionRuntime: AutomationSkipReason = "no_production_runtime"
    public static let slackNotConfigured: AutomationSkipReason = "slack_not_configured"
    public static let targetTaskDeleted: AutomationSkipReason = "target_task_deleted"
    public static let targetTaskArchived: AutomationSkipReason = "target_task_archived"
    public static let targetTaskUnavailable: AutomationSkipReason = "target_task_unavailable"
    public static let targetTaskRefused: AutomationSkipReason = "target_task_refused"
    /// The target task stayed mid-turn through every retry.
    public static let targetBusy: AutomationSkipReason = "target_busy"
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

/// The typed shape of an automation's `metadata` object. The runtime group is the
/// top-level `runtimeGroupId`; the server rejects it inside metadata.
public struct AutomationMetadata: Codable, Sendable, Hashable {
    public var repositories: [AutomationRepositoryRef]?
    /// Several cron expressions; `cron_schedule` on the automation is the single-schedule form.
    public var cronSchedules: [String]?
    /// IANA time zone the cron schedules are evaluated in.
    public var timezone: String?
    public var operatorDefault: String?
    public var conditions: [AutomationCondition]?

    enum CodingKeys: String, CodingKey {
        case repositories
        case cronSchedules = "cron_schedules"
        case timezone
        case operatorDefault = "operator_default"
        case conditions
    }

    public init(
        repositories: [AutomationRepositoryRef]? = nil,
        cronSchedules: [String]? = nil,
        timezone: String? = nil,
        operatorDefault: String? = nil,
        conditions: [AutomationCondition]? = nil
    ) {
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
    /// The next slot: derived from the schedule for `cron`, client-set for a one-off `manual`
    /// automation and cleared once that slot fires.
    public let nextTriggerAt: Date?
    /// The runtime group it runs on (or clusters); nil for `observationSynthesis`.
    public let runtimeGroupId: String?
    /// The existing task each firing posts the prompt into; nil creates a task per firing.
    public let taskId: String?
    public let createdByMemberId: String?
    /// Why the scheduler will not run this automation, when it will not.
    public let executionBlockedReason: String?
    /// Whether the caller may edit it.
    public let canManage: Bool?
    /// `operator` for one that runs as a task (a prompt automation or `projectCheckIn`), nil otherwise.
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
        case runtimeGroupId = "runtime_group_id"
        case taskId = "task_id"
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

/// Body of `POST /v1/automations`. A one-off reminder is a `manual` automation with a future
/// `nextTriggerAt`; a `cron` automation derives its own slots and must not send one.
public struct AutomationCreate: Encodable, Sendable, Hashable {
    public var name: String
    public var triggerType: AutomationTriggerType
    public var description: String?
    public var cronSchedule: String?
    /// Omit for a prompt automation (which then needs `prompt`).
    public var kind: AutomationKind?
    public var prompt: String?
    /// Required unless `kind` is `observationSynthesis`, which must omit it.
    public var runtimeGroupId: String?
    /// An existing task each firing posts the prompt into (prompt automations only).
    public var taskId: String?
    /// A one-off slot for a `manual` automation; must be in the future.
    public var nextTriggerAt: Date?
    /// Build with `AutomationMetadata.jsonObject()`.
    public var metadata: JSONObject?
    public var enabled: Bool?

    enum CodingKeys: String, CodingKey {
        case name
        case triggerType = "trigger_type"
        case description
        case cronSchedule = "cron_schedule"
        case kind, prompt
        case runtimeGroupId = "runtime_group_id"
        case taskId = "task_id"
        case nextTriggerAt = "next_trigger_at"
        case metadata, enabled
    }

    public init(
        name: String,
        triggerType: AutomationTriggerType,
        description: String? = nil,
        cronSchedule: String? = nil,
        kind: AutomationKind? = nil,
        prompt: String? = nil,
        runtimeGroupId: String? = nil,
        taskId: String? = nil,
        nextTriggerAt: Date? = nil,
        metadata: JSONObject? = nil,
        enabled: Bool? = nil
    ) {
        self.name = name
        self.triggerType = triggerType
        self.description = description
        self.cronSchedule = cronSchedule
        self.kind = kind
        self.prompt = prompt
        self.runtimeGroupId = runtimeGroupId
        self.taskId = taskId
        self.nextTriggerAt = nextTriggerAt
        self.metadata = metadata
        self.enabled = enabled
    }
}

/// Body of `PATCH /v1/automations/{id}`. Only set fields are sent and nil leaves a field as it is,
/// so nothing can be cleared. `kind` and `trigger_type` are immutable; `metadata` replaces wholesale.
public struct AutomationUpdate: Encodable, Sendable, Hashable {
    public var name: String?
    public var description: String?
    public var cronSchedule: String?
    public var prompt: String?
    /// Moves a prompt automation to another runtime group.
    public var runtimeGroupId: String?
    public var taskId: String?
    /// Schedules, moves or re-arms a `manual` automation's one-off slot; must be in the future.
    public var nextTriggerAt: Date?
    public var metadata: JSONObject?
    /// `false` pauses and keeps the slot.
    public var enabled: Bool?

    enum CodingKeys: String, CodingKey {
        case name, description
        case cronSchedule = "cron_schedule"
        case prompt
        case runtimeGroupId = "runtime_group_id"
        case taskId = "task_id"
        case nextTriggerAt = "next_trigger_at"
        case metadata, enabled
    }

    public init(
        name: String? = nil,
        description: String? = nil,
        cronSchedule: String? = nil,
        prompt: String? = nil,
        runtimeGroupId: String? = nil,
        taskId: String? = nil,
        nextTriggerAt: Date? = nil,
        metadata: JSONObject? = nil,
        enabled: Bool? = nil
    ) {
        self.name = name
        self.description = description
        self.cronSchedule = cronSchedule
        self.prompt = prompt
        self.runtimeGroupId = runtimeGroupId
        self.taskId = taskId
        self.nextTriggerAt = nextTriggerAt
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
    /// `true`: only automations with a next slot; `false`: only those without.
    public var scheduled: Bool?
    /// Only automations that post into this task. Not served until introspection-cloud#3137 ships.
    public var taskId: String?

    public init(
        limit: Int? = nil,
        next: String? = nil,
        kind: AutomationKind? = nil,
        enabled: Bool? = nil,
        scheduled: Bool? = nil,
        taskId: String? = nil
    ) {
        self.limit = limit
        self.next = next
        self.kind = kind
        self.enabled = enabled
        self.scheduled = scheduled
        self.taskId = taskId
    }

    var query: Query {
        var query = Query()
        query.add("limit", limit)
        query.add("kind", kind)
        query.add("enabled", enabled)
        query.add("scheduled", scheduled)
        query.add("task_id", taskId)
        return query
    }
}

/// Response of a hand trigger. A `skipped` status carries its `reason` and records no event.
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

/// Data Plane `/v1/automations`. The server serves these routes to administrators only today (a 403
/// otherwise); introspection-cloud#3137 opens them to members for their own task-targeted automations.
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

    /// Run an automation now: `POST /v1/automations/{id}/trigger`. Returns `202` with the task it
    /// created or posted into; neither reads nor clears a scheduled slot.
    public func trigger(_ automationId: String) async throws -> AutomationTriggerResponse {
        try await http.json("POST", "/v1/automations/\(pathSegment(automationId))/trigger", as: AutomationTriggerResponse.self)
    }
}

extension DataPlaneConnection {
    /// Data Plane automations.
    public var automations: AutomationsAPI { AutomationsAPI(http: dataPlane) }
}
