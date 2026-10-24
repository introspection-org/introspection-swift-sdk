import Foundation

// MARK: Enums

/// What a task command does.
public struct TaskCommandKind: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let exec: TaskCommandKind = "exec"
    public static let upload: TaskCommandKind = "upload"
    public static let download: TaskCommandKind = "download"
}

/// Progress of a task command.
public struct TaskCommandStatus: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let queued: TaskCommandStatus = "queued"
    public static let running: TaskCommandStatus = "running"
    public static let completed: TaskCommandStatus = "completed"
    public static let failed: TaskCommandStatus = "failed"

    /// Whether the command has finished, either way.
    public var isTerminal: Bool { self == .completed || self == .failed }
}

// MARK: Models

/// A command against an eval task's live sandbox, tagged on the wire by `kind`. `service` names a compose
/// service; nil (or `main`) is the agent's own container.
public enum TaskCommandSpec: Encodable, Sendable, Hashable {
    /// Run an argv (never a shell string) and record its exit and output. `timeoutSeconds` defaults to 300.
    case exec(command: [String], cwd: String? = nil, timeoutSeconds: Int? = nil, service: String? = nil)
    /// Copy a Files API object to an absolute `path` inside the sandbox.
    case upload(fileId: String, path: String)
    /// Copy the file at an absolute `path` out into a new Files API object, reported as `outputFileId`.
    case download(path: String, service: String? = nil)

    private enum CodingKeys: String, CodingKey {
        case kind, command, cwd, service, path
        case timeoutSeconds = "timeout_seconds"
        case fileId = "file_id"
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .exec(command, cwd, timeoutSeconds, service):
            try container.encode(TaskCommandKind.exec, forKey: .kind)
            try container.encode(command, forKey: .command)
            try container.encodeIfPresent(cwd, forKey: .cwd)
            try container.encodeIfPresent(timeoutSeconds, forKey: .timeoutSeconds)
            try container.encodeIfPresent(service, forKey: .service)
        case let .upload(fileId, path):
            try container.encode(TaskCommandKind.upload, forKey: .kind)
            try container.encode(fileId, forKey: .fileId)
            try container.encode(path, forKey: .path)
        case let .download(path, service):
            try container.encode(TaskCommandKind.download, forKey: .kind)
            try container.encode(path, forKey: .path)
            try container.encodeIfPresent(service, forKey: .service)
        }
    }
}

/// A recorded command and, once terminal, its outcome.
public struct TaskCommand: Codable, Sendable, Hashable {
    public var id: String
    public var taskId: String?
    public var kind: TaskCommandKind?
    /// The spec as the API normalized it.
    public var spec: JSONObject?
    public var status: TaskCommandStatus?
    public var exitCode: Int?
    public var stdout: String?
    public var stderr: String?
    /// The Files API object a `download` wrote.
    public var outputFileId: String?
    public var error: String?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var startedAt: Date?
    public var finishedAt: Date?

    /// A value with only its id set; decoding fills the rest.
    public init(id: String) { self.id = id }

    private enum CodingKeys: String, CodingKey {
        case id, kind, spec, status, stdout, stderr, error
        case taskId = "task_id"
        case exitCode = "exit_code"
        case outputFileId = "output_file_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case startedAt = "started_at"
        case finishedAt = "finished_at"
    }
}

/// Filters for `GET /v1/tasks/{id}/commands`.
public struct TaskCommandListParams: Sendable, Hashable {
    public var status: TaskCommandStatus?
    public var limit: Int?
    public var next: String?

    public init(status: TaskCommandStatus? = nil, limit: Int? = nil, next: String? = nil) {
        self.status = status
        self.limit = limit
        self.next = next
    }
}

// MARK: API

/// `exec`, `upload` and `download` against an eval task's live sandbox (`/v1/tasks/{id}/commands`).
///
/// A command is a row the task's workflow executes: the create returns it `queued`, and ``get(_:_:waitSeconds:)``
/// reads its outcome, optionally holding the read until it finishes. Eval tasks only, created with
/// `kind: .eval` and `commands: true`, behind `tasks:exec` on a plane with evals enabled.
public struct TaskCommandsAPI: Sendable {
    /// The longest ``get(_:_:waitSeconds:)`` asks the API to hold a read. The API allows 60 seconds, but it has
    /// to answer inside the SDK's default 60-second request timeout or the read fails instead.
    public static let maxWaitSeconds = 50
    /// How far below a shorter configured request timeout the wait is held.
    static let timeoutHeadroomSeconds = 10

    let http: HTTPClient

    public init(http: HTTPClient) { self.http = http }

    private func base(_ taskId: String) -> String { "/v1/tasks/\(pathSegment(taskId))/commands" }

    /// Record a command and send it to the task's workflow.
    public func create(_ taskId: String, _ spec: TaskCommandSpec) async throws -> TaskCommand {
        try await http.json("POST", base(taskId), body: .encode(spec))
    }

    /// List a task's commands, newest first.
    public func list(_ taskId: String, _ params: TaskCommandListParams = TaskCommandListParams()) -> Paginator<TaskCommand> {
        var query = Query()
        query.add("status", params.status)
        query.add("limit", params.limit)
        return http.paginate(base(taskId), query: query, start: params.next)
    }

    /// Fetch a command. `waitSeconds` holds the read until it finishes or the wait runs out, and returns it in
    /// whatever state it is then. The wait is capped at ``maxWaitSeconds`` (less under a shorter request
    /// timeout), so call again to wait longer.
    public func get(_ taskId: String, _ commandId: String, waitSeconds: Int? = nil) async throws -> TaskCommand {
        var query = Query()
        query.add("wait_seconds", waitSeconds.map { Self.cappedWait($0, timeout: http.options.timeout) })
        return try await http.json("GET", "\(base(taskId))/\(pathSegment(commandId))", query: query)
    }

    static func cappedWait(_ requested: Int, timeout: TimeInterval?) -> Int {
        var cap = maxWaitSeconds
        if let timeout { cap = min(cap, Int(timeout) - timeoutHeadroomSeconds) }
        return max(0, min(requested, cap))
    }
}

extension TasksAPI {
    /// Commands against an eval task's live sandbox.
    public var commands: TaskCommandsAPI { TaskCommandsAPI(http: http) }
}
