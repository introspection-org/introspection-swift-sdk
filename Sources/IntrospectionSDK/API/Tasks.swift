import Foundation

// MARK: Enums

/// A task's execution status. Unknown server values are preserved.
public struct TaskStatus: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static let pending: TaskStatus = "pending"
    public static let queued: TaskStatus = "queued"
    public static let scheduled: TaskStatus = "scheduled"
    public static let running: TaskStatus = "running"
    public static let awaitingUser: TaskStatus = "awaiting_user"
    public static let idle: TaskStatus = "idle"
    public static let completed: TaskStatus = "completed"
    public static let failed: TaskStatus = "failed"
    public static let cancelling: TaskStatus = "cancelling"
    public static let cancelled: TaskStatus = "cancelled"

    /// Statuses a task never leaves.
    public static let terminal: Set<TaskStatus> = [.completed, .failed, .cancelled]

    /// Whether the task has finished for good.
    public var isTerminal: Bool { Self.terminal.contains(self) }
}

/// A task's execution shape: `agent` (a conversation), `eval` (an agent run as an
/// evaluation trial) or `process` (internal, one-shot script).
public struct TaskKind: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static let agent: TaskKind = "agent"
    public static let eval: TaskKind = "eval"
    /// Created internally only; `POST /v1/tasks` rejects it.
    public static let process: TaskKind = "process"
}

/// An opt-in enrichment for `GET /v1/tasks/{id}` (`?include=`).
public struct TaskInclude: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// Live sandbox status for an in-flight task (one extra server round-trip).
    public static let agent: TaskInclude = "agent"
}

/// The intent of a new run: `prompt` starts a fresh turn, `steer` injects into the active one.
public struct TaskRunKind: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static let prompt: TaskRunKind = "prompt"
    /// Falls back to `prompt` when no turn is active.
    public static let steer: TaskRunKind = "steer"
}

/// How a run cancel behaves.
public struct TaskCancelMode: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// Interrupt the turn now and keep the sandbox warm; the task returns to `idle`.
    public static let abort: TaskCancelMode = "abort"
    /// Let the turn finish, then tear the sandbox down; the task lands `cancelled`.
    public static let drain: TaskCancelMode = "drain"
}

// MARK: Task

/// Live sandbox info, present on `get(_:include: [.agent])` for an in-flight task.
public struct AgentInfo: Codable, Sendable, Hashable {
    public var sandboxStatus: String?
    public var sessionId: String?

    public init(sandboxStatus: String? = nil, sessionId: String? = nil) {
        self.sandboxStatus = sandboxStatus
        self.sessionId = sessionId
    }

    private enum CodingKeys: String, CodingKey {
        case sandboxStatus = "sandbox_status"
        case sessionId = "session_id"
    }
}

/// A task: one conversation (or process run) and its current state. Named
/// `IntrospectionTask` so it never shadows Swift concurrency's `Task`.
public struct IntrospectionTask: Codable, Sendable, Hashable {
    public var id: String
    public var orgId: String?
    public var projectId: String?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var title: String?
    public var displayIndex: Int?
    public var status: TaskStatus
    public var kind: TaskKind
    /// The member who started the task.
    public var memberId: String?
    /// The automation that created the task.
    public var automationId: String?
    /// The runtime the task is bound to.
    public var runtimeId: String?
    public var isArchived: Bool
    public var startedAt: Date?
    public var completedAt: Date?
    public var lastUserMessageAt: Date?
    /// Mutable task metadata; the platform also writes into it.
    public var metadata: JSONObject?
    /// Immutable filter dimensions stamped onto the task's conversation.
    public var conversationMetadata: [String: String]?
    /// `key:value` grouping tags.
    public var tags: [String]
    public var agent: AgentInfo?

    public init(
        id: String,
        orgId: String? = nil,
        projectId: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        title: String? = nil,
        displayIndex: Int? = nil,
        status: TaskStatus = .pending,
        kind: TaskKind = .agent,
        memberId: String? = nil,
        automationId: String? = nil,
        runtimeId: String? = nil,
        isArchived: Bool = false,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        lastUserMessageAt: Date? = nil,
        metadata: JSONObject? = nil,
        conversationMetadata: [String: String]? = nil,
        tags: [String] = [],
        agent: AgentInfo? = nil
    ) {
        self.id = id
        self.orgId = orgId
        self.projectId = projectId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.title = title
        self.displayIndex = displayIndex
        self.status = status
        self.kind = kind
        self.memberId = memberId
        self.automationId = automationId
        self.runtimeId = runtimeId
        self.isArchived = isArchived
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.lastUserMessageAt = lastUserMessageAt
        self.metadata = metadata
        self.conversationMetadata = conversationMetadata
        self.tags = tags
        self.agent = agent
    }

    /// The conversation this task renders under: `metadata.conversation_id`, else the task id.
    public var conversationId: String {
        metadata?["conversation_id"]?.stringValue ?? id
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, status, kind, metadata, tags, agent
        case orgId = "org_id"
        case projectId = "project_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case displayIndex = "display_index"
        case memberId = "member_id"
        case automationId = "automation_id"
        case runtimeId = "runtime_id"
        case isArchived = "is_archived"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case lastUserMessageAt = "last_user_message_at"
        case conversationMetadata = "conversation_metadata"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        orgId = try c.decodeIfPresent(String.self, forKey: .orgId)
        projectId = try c.decodeIfPresent(String.self, forKey: .projectId)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        displayIndex = try c.decodeIfPresent(Int.self, forKey: .displayIndex)
        status = try c.decodeIfPresent(TaskStatus.self, forKey: .status) ?? .pending
        kind = try c.decodeIfPresent(TaskKind.self, forKey: .kind) ?? .agent
        memberId = try c.decodeIfPresent(String.self, forKey: .memberId)
        automationId = try c.decodeIfPresent(String.self, forKey: .automationId)
        runtimeId = try c.decodeIfPresent(String.self, forKey: .runtimeId)
        isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        lastUserMessageAt = try c.decodeIfPresent(Date.self, forKey: .lastUserMessageAt)
        metadata = try c.decodeIfPresent(JSONObject.self, forKey: .metadata)
        conversationMetadata = try c.decodeIfPresent([String: String].self, forKey: .conversationMetadata)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        agent = try c.decodeIfPresent(AgentInfo.self, forKey: .agent)
    }
}

// MARK: Create / update

/// A reference to an already-uploaded file (`POST /v1/files`), attached to a task or a turn.
public struct TaskFileRef: Codable, Sendable, Hashable {
    /// Files API file id.
    public var id: String
    /// Workspace-relative path to mount the file at; omit to use the file's own name.
    public var name: String?
    public var sizeBytes: Int?

    public init(id: String, name: String? = nil, sizeBytes: Int? = nil) {
        self.id = id
        self.name = name
        self.sizeBytes = sizeBytes
    }

    private enum CodingKeys: String, CodingKey {
        case id, name
        case sizeBytes = "size_bytes"
    }
}

/// A workspace repository to clone before the first turn, and the state to clone it at.
public struct TaskRepoRequest: Codable, Sendable, Hashable {
    /// Registered repository slug, `owner/name`.
    public var repo: String
    /// Branch, tag, or full 40-character commit sha; omit for the default branch.
    public var ref: String?
    /// Shallow-clone depth; `0` clones full history.
    public var depth: Int?

    public init(repo: String, ref: String? = nil, depth: Int? = nil) {
        self.repo = repo
        self.ref = ref
        self.depth = depth
    }
}

/// An Operator-only Recipe patch applied to one development task.
public struct TaskRecipePatch: Codable, Sendable, Hashable {
    public var patchFileId: String
    public var checkoutBaseCommitSha: String
    public var checkoutRepositoryName: String
    public var checkoutRecipeSubPath: String

    public init(patchFileId: String, checkoutBaseCommitSha: String, checkoutRepositoryName: String, checkoutRecipeSubPath: String) {
        self.patchFileId = patchFileId
        self.checkoutBaseCommitSha = checkoutBaseCommitSha
        self.checkoutRepositoryName = checkoutRepositoryName
        self.checkoutRecipeSubPath = checkoutRecipeSubPath
    }

    private enum CodingKeys: String, CodingKey {
        case patchFileId = "patch_file_id"
        case checkoutBaseCommitSha = "checkout_base_commit_sha"
        case checkoutRepositoryName = "checkout_repository_name"
        case checkoutRecipeSubPath = "checkout_recipe_sub_path"
    }
}

/// The body of `POST /v1/tasks`. The server rejects unknown fields.
public struct TaskCreate: Encodable, Sendable, Hashable {
    /// Derived from the prompt by the server when omitted.
    public var title: String?
    public var prompt: String?
    public var kind: TaskKind?
    /// Recipe agent to run; omit for the recipe default (`agents/agent.yaml`).
    public var agentName: String?
    /// Runtime to bind; ignored for a runner credential, whose claim wins.
    public var runtimeId: String?
    /// `false` starts the agent without application-identity MCP bindings instead of failing.
    public var bindingsRequired: Bool?
    /// Exact pushed Recipe commit for an `eval` task.
    public var recipeGitCommitSha: String?
    public var recipePatch: TaskRecipePatch?
    public var repositories: [TaskRepoRequest]?
    /// Idle window (seconds) before the sandbox is torn down; `0` tears down once provisioned.
    public var idleTimeoutSeconds: Int?
    /// Keep the sandbox's stdout/stderr in platform observability.
    public var collectSandboxLogs: Bool?
    public var metadata: JSONObject?
    /// Immutable conversation filter dimensions; they land in append-only telemetry.
    public var conversationMetadata: [String: String]?
    public var tags: [String]?
    public var files: [TaskFileRef]?
    /// Accept `POST /v1/tasks/{id}/commands` for an `eval` task.
    public var commands: Bool?
    /// Compose services beside the agent for an `eval` task, in `docker-compose.yaml` shape.
    public var compose: JSONObject?
    /// Fork from a shared conversation: the `/v1/shares` grant id.
    public var forkShareId: String?

    public init(
        prompt: String? = nil,
        title: String? = nil,
        kind: TaskKind? = nil,
        agentName: String? = nil,
        runtimeId: String? = nil,
        bindingsRequired: Bool? = nil,
        recipeGitCommitSha: String? = nil,
        recipePatch: TaskRecipePatch? = nil,
        repositories: [TaskRepoRequest]? = nil,
        idleTimeoutSeconds: Int? = nil,
        collectSandboxLogs: Bool? = nil,
        metadata: JSONObject? = nil,
        conversationMetadata: [String: String]? = nil,
        tags: [String]? = nil,
        files: [TaskFileRef]? = nil,
        commands: Bool? = nil,
        compose: JSONObject? = nil,
        forkShareId: String? = nil
    ) {
        self.prompt = prompt
        self.title = title
        self.kind = kind
        self.agentName = agentName
        self.runtimeId = runtimeId
        self.bindingsRequired = bindingsRequired
        self.recipeGitCommitSha = recipeGitCommitSha
        self.recipePatch = recipePatch
        self.repositories = repositories
        self.idleTimeoutSeconds = idleTimeoutSeconds
        self.collectSandboxLogs = collectSandboxLogs
        self.metadata = metadata
        self.conversationMetadata = conversationMetadata
        self.tags = tags
        self.files = files
        self.commands = commands
        self.compose = compose
        self.forkShareId = forkShareId
    }

    private enum CodingKeys: String, CodingKey {
        case title, prompt, kind, repositories, metadata, tags, files, commands, compose
        case agentName = "agent_name"
        case runtimeId = "runtime_id"
        case bindingsRequired = "bindings_required"
        case recipeGitCommitSha = "recipe_git_commit_sha"
        case recipePatch = "recipe_patch"
        case idleTimeoutSeconds = "idle_timeout_seconds"
        case collectSandboxLogs = "collect_sandbox_logs"
        case conversationMetadata = "conversation_metadata"
        case forkShareId = "fork_share_id"
    }
}

/// The body of `PATCH /v1/tasks/{id}`.
public struct TaskUpdate: Encodable, Sendable, Hashable {
    public var title: String?
    public var isArchived: Bool?
    /// Merged into the existing metadata.
    public var metadata: JSONObject?
    /// Replaces the tag list wholesale; `[]` clears it.
    public var tags: [String]?

    public init(title: String? = nil, isArchived: Bool? = nil, metadata: JSONObject? = nil, tags: [String]? = nil) {
        self.title = title
        self.isArchived = isArchived
        self.metadata = metadata
        self.tags = tags
    }

    private enum CodingKeys: String, CodingKey {
        case title, metadata, tags
        case isArchived = "is_archived"
    }
}

/// Filters for `GET /v1/tasks`.
public struct TaskListParams: Sendable, Hashable {
    /// Page size (server default 100, max 1000).
    public var limit: Int?
    /// Starting cursor.
    public var next: String?
    public var includeTotal: Bool?
    public var statuses: [TaskStatus]?
    public var runtimeId: String?
    /// Up to 100 runtime ids.
    public var runtimeIds: [String]?
    public var updatedAfter: Date?
    /// `true` returns only tasks created by an automation.
    public var requireAutomationId: Bool?
    public var automationId: String?
    /// Owning member; privileged credentials only.
    public var memberId: String?
    public var conversationId: String?
    /// Up to 100 conversation ids.
    public var conversationIds: [String]?
    /// One `key:value` tag; only narrows the caller's visible set.
    public var tag: String?

    public init(
        limit: Int? = nil,
        next: String? = nil,
        includeTotal: Bool? = nil,
        statuses: [TaskStatus]? = nil,
        runtimeId: String? = nil,
        runtimeIds: [String]? = nil,
        updatedAfter: Date? = nil,
        requireAutomationId: Bool? = nil,
        automationId: String? = nil,
        memberId: String? = nil,
        conversationId: String? = nil,
        conversationIds: [String]? = nil,
        tag: String? = nil
    ) {
        self.limit = limit
        self.next = next
        self.includeTotal = includeTotal
        self.statuses = statuses
        self.runtimeId = runtimeId
        self.runtimeIds = runtimeIds
        self.updatedAfter = updatedAfter
        self.requireAutomationId = requireAutomationId
        self.automationId = automationId
        self.memberId = memberId
        self.conversationId = conversationId
        self.conversationIds = conversationIds
        self.tag = tag
    }

    var query: Query {
        var q = Query()
        q.add("limit", limit)
        q.add("include_total", includeTotal)
        q.add("statuses", statuses)
        q.add("runtime_id", runtimeId)
        q.add("runtime_ids", runtimeIds)
        q.add("updated_after", updatedAfter)
        q.add("require_automation_id", requireAutomationId)
        q.add("automation_id", automationId)
        q.add("member_id", memberId)
        q.add("conversation_id", conversationId)
        q.add("conversation_ids", conversationIds)
        q.add("tag", tag)
        return q
    }
}

// MARK: Runs

/// A run's prompt payload.
public struct TaskPrompt: Codable, Sendable, Hashable {
    public var text: String
    /// Optional base64-encoded image inputs.
    public var images: [String]?

    public init(text: String, images: [String]? = nil) {
        self.text = text
        self.images = images
    }
}

/// One AG-UI resume entry answering a pending interrupt.
public struct TaskResumeEntry: Codable, Sendable, Hashable {
    public var interruptId: String
    /// `resolved` or `cancelled`.
    public var status: String
    /// The answer; must be omitted when cancelled.
    public var payload: JSONValue?

    public init(interruptId: String, status: String, payload: JSONValue? = nil) {
        self.interruptId = interruptId
        self.status = status
        self.payload = payload
    }

    /// Resolve an interrupt with an answer.
    public static func resolved(_ interruptId: String, payload: JSONValue? = nil) -> TaskResumeEntry {
        TaskResumeEntry(interruptId: interruptId, status: "resolved", payload: payload)
    }

    /// Decline an interrupt.
    public static func cancelled(_ interruptId: String) -> TaskResumeEntry {
        TaskResumeEntry(interruptId: interruptId, status: "cancelled")
    }

    // AG-UI wire names are camelCase.
    private enum CodingKeys: String, CodingKey {
        case interruptId, status, payload
    }
}

/// The body of `POST /v1/tasks/{id}/runs` for a new turn.
public struct TaskRunCreate: Encodable, Sendable, Hashable {
    public var prompt: TaskPrompt?
    public var kind: TaskRunKind?
    /// Merged into the task's metadata before the run is dispatched.
    public var metadata: JSONObject?
    /// Files to attach to this turn; materialized into the live sandbox before it runs.
    public var files: [TaskFileRef]?
    /// Stable identity of this message across HTTP retries.
    public var deliveryId: String?
    /// Runtime to rebind to if this run has to provision a new sandbox.
    public var runtimeId: String?

    public init(
        prompt: TaskPrompt? = nil,
        kind: TaskRunKind? = nil,
        metadata: JSONObject? = nil,
        files: [TaskFileRef]? = nil,
        deliveryId: String? = nil,
        runtimeId: String? = nil
    ) {
        self.prompt = prompt
        self.kind = kind
        self.metadata = metadata
        self.files = files
        self.deliveryId = deliveryId
        self.runtimeId = runtimeId
    }

    /// A turn with prompt text.
    public init(
        text: String,
        kind: TaskRunKind? = nil,
        metadata: JSONObject? = nil,
        files: [TaskFileRef]? = nil,
        deliveryId: String? = nil,
        runtimeId: String? = nil
    ) {
        self.init(
            prompt: TaskPrompt(text: text), kind: kind, metadata: metadata, files: files, deliveryId: deliveryId, runtimeId: runtimeId)
    }

    private enum CodingKeys: String, CodingKey {
        case prompt, kind, metadata, files
        case deliveryId = "delivery_id"
        case runtimeId = "runtime_id"
    }
}

/// The body of `POST /v1/tasks/{id}/runs` answering a pending interrupt.
public struct TaskRunResume: Encodable, Sendable, Hashable {
    public var resume: [TaskResumeEntry]
    public var metadata: JSONObject?
    public var deliveryId: String?
    public var runtimeId: String?

    public init(resume: [TaskResumeEntry], metadata: JSONObject? = nil, deliveryId: String? = nil, runtimeId: String? = nil) {
        self.resume = resume
        self.metadata = metadata
        self.deliveryId = deliveryId
        self.runtimeId = runtimeId
    }

    private enum CodingKeys: String, CodingKey {
        case resume, metadata
        case deliveryId = "delivery_id"
        case runtimeId = "runtime_id"
    }
}

/// A run: one turn of a task.
public struct TaskRun: Codable, Sendable, Hashable {
    public var id: String
    public var taskId: String
    public var status: TaskStatus?
    public var createdAt: Date?
    public var updatedAt: Date?

    public init(id: String, taskId: String, status: TaskStatus? = nil, createdAt: Date? = nil, updatedAt: Date? = nil) {
        self.id = id
        self.taskId = taskId
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, status
        case taskId = "task_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// The response of `POST /v1/tasks`: the task and its initial run.
public struct TaskCreateResponse: Codable, Sendable, Hashable {
    public var task: IntrospectionTask
    public var run: TaskRun

    public init(task: IntrospectionTask, run: TaskRun) {
        self.task = task
        self.run = run
    }
}

/// The response of `POST /v1/tasks/{id}/runs`.
public struct TaskRunResponse: Codable, Sendable, Hashable {
    public var run: TaskRun

    public init(run: TaskRun) { self.run = run }
}

/// Options for cancelling a run. Without options the server aborts.
public struct TaskCancelOptions: Encodable, Sendable, Hashable {
    /// Defaults to `abort` when nil.
    public var mode: TaskCancelMode?
    /// Drain only: force teardown after this many seconds.
    public var drainWithinSeconds: Int?

    public init(mode: TaskCancelMode? = nil, drainWithinSeconds: Int? = nil) {
        self.mode = mode
        self.drainWithinSeconds = drainWithinSeconds
    }

    /// Let the active turn finish, then tear the sandbox down.
    public static func drain(within seconds: Int? = nil) -> TaskCancelOptions {
        TaskCancelOptions(mode: .drain, drainWithinSeconds: seconds)
    }

    private enum CodingKeys: String, CodingKey {
        case mode
        case drainWithinSeconds = "drain_within_seconds"
    }
}

/// The response of a run cancel.
public struct TaskCancelResponse: Codable, Sendable, Hashable {
    public var id: String

    public init(id: String) { self.id = id }
}
