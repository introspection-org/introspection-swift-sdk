import Foundation

// MARK: Enums

/// An issue's status. Unknown server values are preserved.
public struct IssueStatus: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public init(from decoder: any Decoder) throws { rawValue = try decoder.singleString() }
    public func encode(to encoder: any Encoder) throws { try encoder.encodeSingle(rawValue) }

    /// A new issue starts here.
    public static let open: IssueStatus = "open"
    public static let waiting: IssueStatus = "waiting"
    public static let closed: IssueStatus = "closed"
    public static let cancelled: IssueStatus = "cancelled"
}

/// An issue's priority.
public struct IssuePriority: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public init(from decoder: any Decoder) throws { rawValue = try decoder.singleString() }
    public func encode(to encoder: any Encoder) throws { try encoder.encodeSingle(rawValue) }

    public static let low: IssuePriority = "low"
    /// The server default.
    public static let medium: IssuePriority = "medium"
    public static let high: IssuePriority = "high"
    public static let urgent: IssuePriority = "urgent"
}

/// Who owns an issue, for `IssueListParams.owner`.
public struct IssueOwner: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public init(from decoder: any Decoder) throws { rawValue = try decoder.singleString() }
    public func encode(to encoder: any Encoder) throws { try encoder.encodeSingle(rawValue) }

    /// Project-owned (Operator) issues.
    public static let project: IssueOwner = "project"
    /// The caller's own private issues.
    public static let me: IssueOwner = "me"
}

/// A human request's status.
public struct IssueRequestStatus: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public init(from decoder: any Decoder) throws { rawValue = try decoder.singleString() }
    public func encode(to encoder: any Encoder) throws { try encoder.encodeSingle(rawValue) }

    /// A new request is open.
    public static let open: IssueRequestStatus = "open"
    /// Needs a `resolution`.
    public static let resolved: IssueRequestStatus = "resolved"
    /// Needs a `resolution`.
    public static let cancelled: IssueRequestStatus = "cancelled"
}

// MARK: Evidence

/// A Data Plane file cited as evidence.
public struct IssueFile: Codable, Sendable, Hashable {
    public var fileId: String
    public var name: String?
    public var checksum: String?
    /// The events the file came from (at most 100).
    public var sourceEventIds: [String]?

    enum CodingKeys: String, CodingKey {
        case fileId = "file_id"
        case name, checksum
        case sourceEventIds = "source_event_ids"
    }

    public init(fileId: String, name: String? = nil, checksum: String? = nil, sourceEventIds: [String]? = nil) {
        self.fileId = fileId
        self.name = name
        self.checksum = checksum
        self.sourceEventIds = sourceEventIds
    }
}

/// An HTTP or HTTPS link cited as evidence, such as a pull request.
public struct IssueLink: Codable, Sendable, Hashable {
    public var url: String
    public var title: String?

    public init(url: String, title: String? = nil) {
        self.url = url
        self.title = title
    }
}

/// A recorded event cited as evidence; the caller must be able to read it.
public struct IssueEventReference: Codable, Sendable, Hashable {
    public var eventId: String

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
    }

    public init(eventId: String) { self.eventId = eventId }
}

/// A conversation span cited as evidence; the caller must be able to read the exact pair.
public struct IssueSpanReference: Codable, Sendable, Hashable {
    /// 32 hex characters.
    public var traceId: String
    /// 16 hex characters.
    public var spanId: String

    enum CodingKeys: String, CodingKey {
        case traceId = "trace_id"
        case spanId = "span_id"
    }

    public init(traceId: String, spanId: String) {
        self.traceId = traceId
        self.spanId = spanId
    }
}

// MARK: Models

/// One open human request, as projected onto its issue.
public struct IssueOpenRequest: Codable, Sendable, Hashable {
    public let id: String
    public let question: String
    public let assigneeId: String
    public let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, question
        case assigneeId = "assignee_id"
        case createdAt = "created_at"
    }
}

/// An issue: its brief, the evidence it cites and its open human requests.
public struct Issue: Codable, Sendable, Hashable {
    public let id: String
    public let orgId: String
    public let projectId: String
    public let title: String
    public let description: String
    public let priority: IssuePriority?
    public let status: IssueStatus?
    /// Send it back as `IssueUpdate.expectedRevision`.
    public let revision: Int?
    /// Project-scoped display ID.
    public let displayIndex: Int?
    public let files: [IssueFile]?
    public let links: [IssueLink]?
    public let events: [IssueEventReference]?
    public let spans: [IssueSpanReference]?
    /// Free-form tags, conventionally `key:value`.
    public let tags: [String]?
    /// Caller-defined attributes; values are strings, numbers, booleans or null.
    public let metadata: JSONObject?
    /// The fixed worker task behind the issue chat and Slack replies.
    public let taskId: String?
    public let taskStatus: TaskStatus?
    /// The owner of a private issue; nil for a project-owned (Operator) issue.
    public let memberId: String?
    /// When the issue last entered `closed` or `cancelled`.
    public let closedAt: Date?
    /// Oldest first.
    public let openRequests: [IssueOpenRequest]?
    public let createdAt: Date?
    public let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case orgId = "org_id"
        case projectId = "project_id"
        case title, description, priority, status, revision
        case displayIndex = "display_index"
        case files, links, events, spans, tags, metadata
        case taskId = "task_id"
        case taskStatus = "task_status"
        case memberId = "member_id"
        case closedAt = "closed_at"
        case openRequests = "open_requests"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Body of `POST /v1/issues`. The issue starts `open`; set its status later with an `IssueUpdate`.
public struct IssueCreate: Encodable, Sendable, Hashable {
    public var title: String
    public var description: String
    /// The fixed worker task behind the issue chat and Slack replies.
    public var taskId: String
    public var priority: IssuePriority?
    public var files: [IssueFile]?
    public var links: [IssueLink]?
    public var events: [IssueEventReference]?
    public var spans: [IssueSpanReference]?
    public var tags: [String]?
    /// Values are strings, numbers, booleans or null.
    public var metadata: JSONObject?

    enum CodingKeys: String, CodingKey {
        case title, description
        case taskId = "task_id"
        case priority, files, links, events, spans, tags, metadata
    }

    public init(
        title: String,
        description: String,
        taskId: String,
        priority: IssuePriority? = nil,
        files: [IssueFile]? = nil,
        links: [IssueLink]? = nil,
        events: [IssueEventReference]? = nil,
        spans: [IssueSpanReference]? = nil,
        tags: [String]? = nil,
        metadata: JSONObject? = nil
    ) {
        // jscpd:ignore-start: memberwise init of a public type; the assignments cannot be shared
        self.title = title
        self.description = description
        self.taskId = taskId
        self.priority = priority
        self.files = files
        self.links = links
        self.events = events
        self.spans = spans
        self.tags = tags
        self.metadata = metadata
        // jscpd:ignore-end
    }
}

/// An edit to an issue's brief (`PATCH /v1/issues/{id}`). Nil fields are omitted and stay unchanged; each list
/// and `metadata` replaces its value wholesale, so `[]` (or `[:]`) clears it.
public struct IssueUpdate: Encodable, Sendable, Hashable {
    /// The `revision` the edit was made against; a stale one is refused with 409.
    public var expectedRevision: Int
    public var title: String?
    public var description: String?
    public var priority: IssuePriority?
    public var status: IssueStatus?
    public var files: [IssueFile]?
    public var links: [IssueLink]?
    public var events: [IssueEventReference]?
    public var spans: [IssueSpanReference]?
    public var tags: [String]?
    public var metadata: JSONObject?

    enum CodingKeys: String, CodingKey {
        case expectedRevision = "expected_revision"
        case title, description, priority, status, files, links, events, spans, tags, metadata
    }

    public init(
        expectedRevision: Int,
        title: String? = nil,
        description: String? = nil,
        priority: IssuePriority? = nil,
        status: IssueStatus? = nil,
        files: [IssueFile]? = nil,
        links: [IssueLink]? = nil,
        events: [IssueEventReference]? = nil,
        spans: [IssueSpanReference]? = nil,
        tags: [String]? = nil,
        metadata: JSONObject? = nil
    ) {
        // jscpd:ignore-start: memberwise init of a public type; the assignments cannot be shared
        self.expectedRevision = expectedRevision
        self.title = title
        self.description = description
        self.priority = priority
        self.status = status
        self.files = files
        self.links = links
        self.events = events
        self.spans = spans
        self.tags = tags
        self.metadata = metadata
        // jscpd:ignore-end
    }
}

/// Creates one human request on an issue, or changes one.
public struct IssueRequestMutation: Encodable, Sendable, Hashable {
    /// The request's id; a new request takes a client-minted UUIDv7.
    public var id: String
    /// 0 creates the request; otherwise the request's own current revision (stale is refused with 409).
    public var expectedRevision: Int
    /// What the assignee is asked; required to create.
    public var question: String?
    /// The member asked; required to create, set again to reassign.
    public var assigneeId: String?
    /// `resolved` and `cancelled` need a `resolution`.
    public var status: IssueRequestStatus?
    /// The decision and its basis, when closing.
    public var resolution: String?

    enum CodingKeys: String, CodingKey {
        case id
        case expectedRevision = "expected_revision"
        case question
        case assigneeId = "assignee_id"
        case status, resolution
    }

    public init(
        id: String,
        expectedRevision: Int,
        question: String? = nil,
        assigneeId: String? = nil,
        status: IssueRequestStatus? = nil,
        resolution: String? = nil
    ) {
        self.id = id
        self.expectedRevision = expectedRevision
        self.question = question
        self.assigneeId = assigneeId
        self.status = status
        self.resolution = resolution
    }

    /// A new request (`expectedRevision` 0). Without an `id`, one is minted as a UUIDv7.
    public static func create(question: String, assigneeId: String, id: String? = nil) -> IssueRequestMutation {
        IssueRequestMutation(id: id ?? makeUUIDv7(), expectedRevision: 0, question: question, assigneeId: assigneeId)
    }
}

/// The `{"request": ...}` body of `PATCH /v1/issues/{id}`: create or change one human request.
public struct IssueMutation: Encodable, Sendable, Hashable {
    public var request: IssueRequestMutation

    public init(request: IssueRequestMutation) { self.request = request }
}

/// Filters for `GET /v1/issues`. Array filters are sent as repeated parameters.
public struct IssueListParams: Sendable, Hashable {
    /// Page size, 1...200 (server default 50).
    public var limit: Int?
    /// Starting cursor; keep the filters unchanged while paging.
    public var next: String?
    /// ORed.
    public var status: [IssueStatus]?
    /// ORed; nil lists every issue the caller may read.
    public var owner: [IssueOwner]?
    /// `true`: has an open request assigned to the caller; `false`: has none.
    public var assignedToMe: Bool?
    /// Whether any human request is open.
    public var hasOpenRequests: Bool?
    /// The worker task's status.
    public var taskStatus: [TaskStatus]?
    /// Excludes these worker task statuses; an issue without a live task is kept.
    public var excludeTaskStatus: [TaskStatus]?
    /// Project-scoped display ID.
    public var displayIndex: Int?
    /// A `key:value` tag, e.g. `customer:acme`.
    public var tag: String?
    /// Issues whose metadata holds every pair (at most 16 keys). Sent as repeated `metadata=key:value`.
    public var metadata: [String: String]?
    /// Include `totalCount` for the filtered set.
    public var includeTotal: Bool?

    public init(
        limit: Int? = nil,
        next: String? = nil,
        status: [IssueStatus]? = nil,
        owner: [IssueOwner]? = nil,
        assignedToMe: Bool? = nil,
        hasOpenRequests: Bool? = nil,
        taskStatus: [TaskStatus]? = nil,
        excludeTaskStatus: [TaskStatus]? = nil,
        displayIndex: Int? = nil,
        tag: String? = nil,
        metadata: [String: String]? = nil,
        includeTotal: Bool? = nil
    ) {
        // jscpd:ignore-start: memberwise init of a public type; the assignments cannot be shared
        self.limit = limit
        self.next = next
        self.status = status
        self.owner = owner
        self.assignedToMe = assignedToMe
        self.hasOpenRequests = hasOpenRequests
        self.taskStatus = taskStatus
        self.excludeTaskStatus = excludeTaskStatus
        self.displayIndex = displayIndex
        self.tag = tag
        self.metadata = metadata
        self.includeTotal = includeTotal
        // jscpd:ignore-end
    }

    var query: Query {
        var query = Query()
        query.add("limit", limit)
        query.add("status", status)
        query.add("owner", owner)
        query.add("assigned_to_me", assignedToMe)
        query.add("has_open_requests", hasOpenRequests)
        query.add("task_status", taskStatus)
        query.add("exclude_task_status", excludeTaskStatus)
        query.add("display_index", displayIndex)
        query.add("tag", tag)
        query.add("metadata", metadata.map { pairs in pairs.keys.sorted().compactMap { key in pairs[key].map { "\(key):\($0)" } } })
        query.add("include_total", includeTotal)
        return query
    }
}

// MARK: API

/// Data Plane `/v1/issues`. Each write takes an optional `idempotencyKey`, sent as `Idempotency-Key`: one key per
/// deliberate write, resent unchanged when retrying it so it applies once.
public struct IssuesAPI: Sendable {
    let http: HTTPClient

    public init(http: HTTPClient) {
        self.http = http
    }

    /// List the issues the caller may read, newest activity first.
    public func list(_ params: IssueListParams = IssueListParams()) -> Paginator<Issue> {
        http.paginate("/v1/issues", query: params.query, start: params.next, as: Issue.self)
    }

    /// Open an issue on its worker task. It starts `open`.
    public func create(_ body: IssueCreate, idempotencyKey: String? = nil) async throws -> Issue {
        try await http.json(
            "POST", "/v1/issues", body: try .encode(body), headers: idempotencyHeaders(idempotencyKey), as: Issue.self)
    }

    /// Read one issue with its evidence, open requests and current `revision`.
    public func get(_ issueId: String) async throws -> Issue {
        try await http.json("GET", "/v1/issues/\(pathSegment(issueId))", as: Issue.self)
    }

    /// Edit an issue's brief. A stale `expectedRevision` is refused with 409: read the issue again before retrying.
    public func update(_ issueId: String, _ body: IssueUpdate, idempotencyKey: String? = nil) async throws -> Issue {
        try await patch(issueId, body: try .encode(body), idempotencyKey: idempotencyKey)
    }

    /// Create or change one human request on an issue. Returns the updated issue.
    public func update(_ issueId: String, _ body: IssueMutation, idempotencyKey: String? = nil) async throws -> Issue {
        try await patch(issueId, body: try .encode(body), idempotencyKey: idempotencyKey)
    }

    /// Soft-delete an issue. Its activity history is kept.
    public func delete(_ issueId: String, idempotencyKey: String? = nil) async throws {
        try await http.empty("DELETE", "/v1/issues/\(pathSegment(issueId))", headers: idempotencyHeaders(idempotencyKey))
    }

    private func patch(_ issueId: String, body: RequestBody, idempotencyKey: String?) async throws -> Issue {
        try await http.json(
            "PATCH", "/v1/issues/\(pathSegment(issueId))", body: body, headers: idempotencyHeaders(idempotencyKey),
            as: Issue.self)
    }

    private func idempotencyHeaders(_ key: String?) -> [String: String] {
        key.map { ["Idempotency-Key": $0] } ?? [:]
    }
}

extension DataPlaneConnection {
    /// Data Plane issues (`/v1/issues`).
    public var issues: IssuesAPI { IssuesAPI(http: dataPlane) }
}
