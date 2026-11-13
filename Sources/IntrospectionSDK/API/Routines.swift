import Foundation

// MARK: Enums

/// How a routine is triggered.
public struct RoutineTriggerType: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public init(from decoder: any Decoder) throws { rawValue = try decoder.singleString() }
    public func encode(to encoder: any Encoder) throws { try encoder.encodeSingle(rawValue) }

    public static let cron: RoutineTriggerType = "cron"
    /// Runs by hand, or once at a client-set `nextTriggerAt` (a one-off reminder).
    public static let manual: RoutineTriggerType = "manual"
}

/// A platform routine kind. A prompt routine a person created has no kind. Open-ended: an
/// unrecognised value decodes as its raw string.
public struct RoutineKind: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public init(from decoder: any Decoder) throws { rawValue = try decoder.singleString() }
    public func encode(to encoder: any Encoder) throws { try encoder.encodeSingle(rawValue) }

    /// Project-wide: takes no `runtimeGroupId`.
    public static let observationSynthesis: RoutineKind = "observation_synthesis"
    public static let observationClustering: RoutineKind = "observation_clustering"
    /// The project's default check-in; runs as an agent task, so it carries a `prompt`.
    public static let projectCheckIn: RoutineKind = "project_check_in"
}

/// A built-in condition evaluated before a routine runs.
public struct RoutineConditionType: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public init(from decoder: any Decoder) throws { rawValue = try decoder.singleString() }
    public func encode(to encoder: any Encoder) throws { try encoder.encodeSingle(rawValue) }

    public static let hasNewTasksSinceLastRun: RoutineConditionType = "has_new_tasks_since_last_run"
    public static let lastRunIssuesResolved: RoutineConditionType = "last_run_issues_resolved"
    public static let noLiveTaskForRoutine: RoutineConditionType = "no_live_task_for_routine"
}

/// Outcome of one routine execution attempt.
public struct RoutineExecutionStatus: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public init(from decoder: any Decoder) throws { rawValue = try decoder.singleString() }
    public func encode(to encoder: any Encoder) throws { try encoder.encodeSingle(rawValue) }

    public static let triggered: RoutineExecutionStatus = "triggered"
    public static let cancelled: RoutineExecutionStatus = "cancelled"
    public static let failed: RoutineExecutionStatus = "failed"
    public static let skipped: RoutineExecutionStatus = "skipped"
}

/// Why a trigger ran nothing (`introspection.routines.skipped`).
public struct RoutineSkipReason: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public init(from decoder: any Decoder) throws { rawValue = try decoder.singleString() }
    public func encode(to encoder: any Encoder) throws { try encoder.encodeSingle(rawValue) }

    public static let routineDeleted: RoutineSkipReason = "routine_deleted"
    public static let executionBlocked: RoutineSkipReason = "execution_blocked"
    public static let conditionsNotMet: RoutineSkipReason = "conditions_not_met"
    public static let noProductionRuntime: RoutineSkipReason = "no_production_runtime"
    public static let slackNotConfigured: RoutineSkipReason = "slack_not_configured"
    public static let targetTaskDeleted: RoutineSkipReason = "target_task_deleted"
    public static let targetTaskArchived: RoutineSkipReason = "target_task_archived"
    public static let targetTaskUnavailable: RoutineSkipReason = "target_task_unavailable"
    public static let targetTaskRefused: RoutineSkipReason = "target_task_refused"
    /// The target task stayed mid-turn through every retry.
    public static let targetBusy: RoutineSkipReason = "target_busy"
}

// MARK: Metadata

/// One condition stored in a routine's metadata.
public struct RoutineCondition: Codable, Sendable, Hashable {
    public var type: RoutineConditionType
    public var runtimeGroupId: String?

    enum CodingKeys: String, CodingKey {
        case type
        case runtimeGroupId = "runtime_group_id"
    }

    public init(type: RoutineConditionType, runtimeGroupId: String? = nil) {
        self.type = type
        self.runtimeGroupId = runtimeGroupId
    }
}

/// A repository a task-backed routine clones (`owner/name` plus an optional ref).
public struct RoutineRepositoryRef: Codable, Sendable, Hashable {
    public var repo: String
    public var ref: String?

    public init(repo: String, ref: String? = nil) {
        self.repo = repo
        self.ref = ref
    }
}

/// The typed shape of a routine's `metadata` object. The runtime group is the
/// top-level `runtimeGroupId`; the server rejects it inside metadata.
public struct RoutineMetadata: Codable, Sendable, Hashable {
    public var repositories: [RoutineRepositoryRef]?
    /// Several cron expressions; `cron_schedule` on the routine is the single-schedule form.
    public var cronSchedules: [String]?
    /// IANA time zone the cron schedules are evaluated in.
    public var timezone: String?
    public var operatorDefault: String?
    public var conditions: [RoutineCondition]?

    enum CodingKeys: String, CodingKey {
        case repositories
        case cronSchedules = "cron_schedules"
        case timezone
        case operatorDefault = "operator_default"
        case conditions
    }

    public init(
        repositories: [RoutineRepositoryRef]? = nil,
        cronSchedules: [String]? = nil,
        timezone: String? = nil,
        operatorDefault: String? = nil,
        conditions: [RoutineCondition]? = nil
    ) {
        self.repositories = repositories
        self.cronSchedules = cronSchedules
        self.timezone = timezone
        self.operatorDefault = operatorDefault
        self.conditions = conditions
    }

    /// As a JSON object for `RoutineCreate.metadata` / `RoutineUpdate.metadata`.
    public func jsonObject() throws -> JSONObject {
        try JSONValue.from(self).objectValue ?? [:]
    }
}

// MARK: Models

/// A stored routine: scheduled agent work, or platform work when `kind` is set.
public struct Routine: Codable, Sendable, Hashable {
    public let id: String
    public let orgId: String?
    public let projectId: String?
    public let name: String
    public let description: String?
    public let enabled: Bool?
    public let triggerType: RoutineTriggerType?
    public let cronSchedule: String?
    public let kind: RoutineKind?
    public let prompt: String?
    /// Open-ended metadata; read the known fields with `typedMetadata`.
    public let metadata: JSONObject?
    public let tags: [String]?
    public let lastTriggeredAt: Date?
    /// The next slot: derived from the schedule for `cron`, client-set for a one-off `manual`
    /// routine and cleared once that slot fires.
    public let nextTriggerAt: Date?
    /// The runtime group it runs on (or clusters); nil for `observationSynthesis`.
    public let runtimeGroupId: String?
    /// The existing task each firing posts the prompt into; nil creates a task per firing.
    public let taskId: String?
    public let createdByMemberId: String?
    /// Why the scheduler will not run this routine, when it will not.
    public let executionBlockedReason: String?
    /// Whether the caller may edit it.
    public let canManage: Bool?
    /// `operator` for one that runs as a task (a prompt routine or `projectCheckIn`), nil otherwise.
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
    public var typedMetadata: RoutineMetadata? {
        guard let metadata else { return nil }
        return try? JSONValue.object(metadata).decode(RoutineMetadata.self)
    }
}

/// Body of `POST /v1/routines`. A one-off reminder is a `manual` routine with a future
/// `nextTriggerAt`; a `cron` routine derives its own slots and must not send one.
public struct RoutineCreate: Encodable, Sendable, Hashable {
    public var name: String
    public var triggerType: RoutineTriggerType
    public var description: String?
    public var cronSchedule: String?
    /// Omit for a prompt routine (which then needs `prompt`).
    public var kind: RoutineKind?
    public var prompt: String?
    /// Required unless `kind` is `observationSynthesis`, which must omit it.
    public var runtimeGroupId: String?
    /// An existing task each firing posts the prompt into (prompt routines only).
    public var taskId: String?
    /// A one-off slot for a `manual` routine; must be in the future.
    public var nextTriggerAt: Date?
    /// Build with `RoutineMetadata.jsonObject()`.
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
        triggerType: RoutineTriggerType,
        description: String? = nil,
        cronSchedule: String? = nil,
        kind: RoutineKind? = nil,
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

/// Body of `PATCH /v1/routines/{id}`. Only set fields are sent and nil leaves a field as it is,
/// so nothing can be cleared. `kind` and `trigger_type` are immutable; `metadata` replaces wholesale.
public struct RoutineUpdate: Encodable, Sendable, Hashable {
    public var name: String?
    public var description: String?
    public var cronSchedule: String?
    public var prompt: String?
    /// Moves a prompt routine to another runtime group.
    public var runtimeGroupId: String?
    public var taskId: String?
    /// Schedules, moves or re-arms a `manual` routine's one-off slot; must be in the future.
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

/// Filters for `GET /v1/routines`.
public struct RoutineListParams: Sendable, Hashable {
    /// Page size, 1...1000 (server default 100).
    public var limit: Int?
    /// Starting cursor.
    public var next: String?
    public var kind: RoutineKind?
    public var enabled: Bool?
    /// `true`: only routines with a next slot; `false`: only those without.
    public var scheduled: Bool?
    /// Only routines that post into this task. Not served until introspection-cloud#3137 ships.
    public var taskId: String?

    public init(
        limit: Int? = nil,
        next: String? = nil,
        kind: RoutineKind? = nil,
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
public struct RoutineTriggerResponse: Codable, Sendable, Hashable {
    public let status: RoutineExecutionStatus
    public let routineId: String?
    public let taskId: String?
    public let reason: String?
    /// `observation_clustering` only: the run its `introspection.observation_clustering.run` events carry.
    public let runId: String?
    /// `observation_synthesis` only: how many conversations went to the synthesis queue.
    public let enqueued: Int?
    /// `observation_synthesis` with named conversations only: what was queued, per conversation.
    public let conversations: [EnqueuedConversation]?

    enum CodingKeys: String, CodingKey {
        case status
        case routineId = "routine_id"
        case taskId = "task_id"
        case reason
        case runId = "run_id"
        case enqueued
        case conversations
    }
}

/// A conversation a synthesis trigger queued, and the end it queued it at.
public struct EnqueuedConversation: Codable, Sendable, Hashable {
    public let conversationId: String?
    /// The trigger is answered once a synthesis event's `conversation_completed_at` is at or after this.
    public let completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case completedAt = "completed_at"
    }
}

// MARK: API

/// Data Plane `/v1/routines`. The server serves these routes to administrators only today (a 403
/// otherwise); introspection-cloud#3137 opens them to members for their own task-targeted routines.
public struct RoutinesAPI: Sendable {
    let http: HTTPClient

    public init(http: HTTPClient) {
        self.http = http
    }

    /// List this project's routines.
    public func list(_ params: RoutineListParams = RoutineListParams()) -> Paginator<Routine> {
        http.paginate("/v1/routines", query: params.query, start: params.next, as: Routine.self)
    }

    /// Create a routine.
    public func create(_ body: RoutineCreate) async throws -> Routine {
        try await http.json("POST", "/v1/routines", body: try .encode(body), as: Routine.self)
    }

    /// Read one routine (soft-deleted ones included).
    public func get(_ routineId: String) async throws -> Routine {
        try await http.json("GET", "/v1/routines/\(pathSegment(routineId))", as: Routine.self)
    }

    /// Update a routine.
    public func update(_ routineId: String, _ body: RoutineUpdate) async throws -> Routine {
        try await http.json("PATCH", "/v1/routines/\(pathSegment(routineId))", body: try .encode(body), as: Routine.self)
    }

    /// Soft-delete a routine.
    public func delete(_ routineId: String) async throws {
        try await http.empty("DELETE", "/v1/routines/\(pathSegment(routineId))")
    }

    /// Run a routine now: `POST /v1/routines/{id}/trigger`. Returns `202` with the task it
    /// created or posted into; neither reads nor clears a scheduled slot.
    public func trigger(_ routineId: String) async throws -> RoutineTriggerResponse {
        try await http.json("POST", "/v1/routines/\(pathSegment(routineId))/trigger", as: RoutineTriggerResponse.self)
    }
}

extension DataPlaneConnection {
    /// Data Plane routines.
    public var routines: RoutinesAPI { RoutinesAPI(http: dataPlane) }
}
