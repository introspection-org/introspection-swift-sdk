import Foundation

extension DataPlaneConnection {
    /// Tasks and their runs (`/v1/tasks`).
    public var tasks: TasksAPI { TasksAPI(http: dataPlane, runtimeSelector: runtimeSelector) }
}

/// Tasks: create, read, update, archive and delete conversations, and drive their runs.
public struct TasksAPI: Sendable {
    let http: HTTPClient
    let runtimeSelector: RuntimeSelector?
    /// Runs of a task: new turns, interrupt resumes, cancel and the AG-UI stream.
    public let runs: TaskRunsAPI

    /// `runtimeSelector` fills `runtime_id` on creates that name none.
    public init(http: HTTPClient, runtimeSelector: RuntimeSelector? = nil) {
        self.http = http
        self.runtimeSelector = runtimeSelector
        runs = TaskRunsAPI(http: http, runtimeSelector: runtimeSelector)
    }

    /// List tasks the caller can see, most recent user activity first.
    public func list(_ params: TaskListParams = TaskListParams()) -> Paginator<IntrospectionTask> {
        http.paginate("/v1/tasks", query: params.query, start: params.next, as: IntrospectionTask.self)
    }

    /// Create a task and its initial run.
    public func create(_ body: TaskCreate) async throws -> TaskCreateResponse {
        var body = body
        if body.runtimeId == nil, let runtimeSelector { body.runtimeId = try await runtimeSelector.runtimeId() }
        return try await http.json("POST", "/v1/tasks", body: .encode(body), as: TaskCreateResponse.self)
    }

    /// Get a task. The default read is a cheap row lookup; `include` opts into enrichments.
    public func get(_ taskId: String, include: [TaskInclude] = []) async throws -> IntrospectionTask {
        var query = Query()
        query.add("include", include.isEmpty ? nil : include)
        return try await http.json("GET", "/v1/tasks/\(pathSegment(taskId))", query: query, as: IntrospectionTask.self)
    }

    /// Update a task's title, archive flag, metadata (merged) or tags (replaced).
    public func update(_ taskId: String, _ body: TaskUpdate) async throws -> IntrospectionTask {
        try await http.json("PATCH", "/v1/tasks/\(pathSegment(taskId))", body: .encode(body), as: IntrospectionTask.self)
    }

    /// Delete a task.
    public func delete(_ taskId: String) async throws {
        try await http.empty("DELETE", "/v1/tasks/\(pathSegment(taskId))")
    }

    /// Archive a task, cancelling any active work in the background.
    public func archive(_ taskId: String) async throws {
        try await http.empty("POST", "/v1/tasks/\(pathSegment(taskId))/archive")
    }

    /// Unarchive a task.
    public func unarchive(_ taskId: String) async throws {
        try await http.empty("POST", "/v1/tasks/\(pathSegment(taskId))/unarchive")
    }

    /// Create a task and return a handle on its initial run.
    public func start(_ body: TaskCreate) async throws -> RunHandle {
        let response = try await create(body)
        return RunHandle(task: response.task, run: response.run, runs: runs)
    }

    /// Create a task with `prompt` (overriding `body.prompt`) and return a handle on its initial run.
    public func start(prompt: String, _ body: TaskCreate = TaskCreate()) async throws -> RunHandle {
        var body = body
        body.prompt = prompt
        return try await start(body)
    }
}

/// Runs of a task (`/v1/tasks/{id}/runs`). `runId` may be `"current"` for the active run.
public struct TaskRunsAPI: Sendable {
    let http: HTTPClient
    let runtimeSelector: RuntimeSelector?

    /// `runtimeSelector` fills `runtime_id` on turns that name none, so a restarted
    /// sandbox adopts the runtime version the group serves now.
    public init(http: HTTPClient, runtimeSelector: RuntimeSelector? = nil) {
        self.http = http
        self.runtimeSelector = runtimeSelector
    }

    /// Send a turn. A running task is steered; an idle or settled one is resumed or restarted.
    public func create(_ taskId: String, _ body: TaskRunCreate) async throws -> RunHandle {
        var body = body
        if body.runtimeId == nil, let runtimeSelector { body.runtimeId = try await runtimeSelector.runtimeId() }
        let response = try await http.json(
            "POST", "/v1/tasks/\(pathSegment(taskId))/runs", body: .encode(body), as: TaskRunResponse.self
        )
        return RunHandle(task: nil, run: response.run, runs: self)
    }

    /// Send a turn with prompt text.
    public func create(_ taskId: String, text: String, kind: TaskRunKind? = nil) async throws -> RunHandle {
        try await create(taskId, TaskRunCreate(text: text, kind: kind))
    }

    /// Answer the task's pending interrupt with AG-UI resume entries.
    public func resume(_ taskId: String, _ body: TaskRunResume) async throws -> RunHandle {
        var body = body
        if body.runtimeId == nil, let runtimeSelector { body.runtimeId = try await runtimeSelector.runtimeId() }
        let response = try await http.json(
            "POST", "/v1/tasks/\(pathSegment(taskId))/runs", body: .encode(body), as: TaskRunResponse.self
        )
        return RunHandle(task: nil, run: response.run, runs: self)
    }

    /// Get a run's status.
    public func get(_ taskId: String, _ runId: String) async throws -> TaskRun {
        try await http.json("GET", "/v1/tasks/\(pathSegment(taskId))/runs/\(pathSegment(runId))", as: TaskRun.self)
    }

    /// Cancel a run. Without options the server aborts the turn and keeps the sandbox warm.
    public func cancel(_ taskId: String, _ runId: String, options: TaskCancelOptions? = nil) async throws -> TaskCancelResponse {
        let path = "/v1/tasks/\(pathSegment(taskId))/runs/\(pathSegment(runId))/cancel"
        guard var options else {
            return try await http.json("POST", path, as: TaskCancelResponse.self)
        }
        if options.mode == nil { options.mode = .abort }
        return try await http.json("POST", path, body: .encode(options), as: TaskCancelResponse.self)
    }

    /// Stream a run's AG-UI events, resuming transparently across disconnects.
    public func stream(
        _ taskId: String, _ runId: String, options: RunStreamOptions = RunStreamOptions()
    ) -> AsyncThrowingStream<AGUIEvent, Error> {
        RunStream.events(http: http, taskId: taskId, runId: runId, options: options)
    }
}

/// A handle on one run: stream it, cancel it, or collect its text.
public struct RunHandle: Sendable {
    /// The task, when the handle came from `TasksAPI.start`.
    public let task: IntrospectionTask?
    public let run: TaskRun
    let runs: TaskRunsAPI

    public init(task: IntrospectionTask?, run: TaskRun, runs: TaskRunsAPI) {
        self.task = task
        self.run = run
        self.runs = runs
    }

    /// The run's resumable AG-UI event stream.
    public func stream(options: RunStreamOptions = RunStreamOptions()) -> AsyncThrowingStream<AGUIEvent, Error> {
        runs.stream(run.taskId, run.id, options: options)
    }

    /// Cancel the run.
    public func cancel(options: TaskCancelOptions? = nil) async throws -> TaskCancelResponse {
        try await runs.cancel(run.taskId, run.id, options: options)
    }

    /// Stream the run to its end and return the assistant text deltas joined.
    public func text(options: RunStreamOptions = RunStreamOptions()) async throws -> String {
        var text = ""
        for try await event in stream(options: options)
        where event.eventType == .textMessageContent || event.eventType == .textMessageChunk {
            text += event.delta ?? ""
        }
        return text
    }
}
