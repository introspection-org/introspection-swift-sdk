import Foundation

// MARK: Enums

/// Where an issue stands.
public struct IssueStatus: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public init(from decoder: any Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static let open: IssueStatus = "open"
    /// Waiting on a human request.
    public static let waiting: IssueStatus = "waiting"
    public static let closed: IssueStatus = "closed"
    public static let cancelled: IssueStatus = "cancelled"
}

/// How urgent an issue is.
public struct IssuePriority: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public init(from decoder: any Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static let low: IssuePriority = "low"
    public static let medium: IssuePriority = "medium"
    public static let high: IssuePriority = "high"
    public static let urgent: IssuePriority = "urgent"
}

/// Who owns an issue, for the `owner` list filter.
public struct IssueOwner: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public init(from decoder: any Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// Project-owned (Operator) issues.
    public static let project: IssueOwner = "project"
    /// The caller's own private issues.
    public static let me: IssueOwner = "me"
}

/// Where a human request on an issue stands.
public struct IssueRequestStatus: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public init(from decoder: any Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static let open: IssueRequestStatus = "open"
    public static let resolved: IssueRequestStatus = "resolved"
    public static let cancelled: IssueRequestStatus = "cancelled"
}

// MARK: Evidence

/// A file attached to an issue as evidence.
public struct IssueFile: Codable, Sendable, Hashable {
    public var fileId: String
    public var name: String?
    public var checksum: String?
    public var sourceEventIds: [String]?

    public init(fileId: String, name: String? = nil, checksum: String? = nil, sourceEventIds: [String]? = nil) {
        self.fileId = fileId
        self.name = name
        self.checksum = checksum
        self.sourceEventIds = sourceEventIds
    }

    enum CodingKeys: String, CodingKey {
        case fileId = "file_id"
        case name, checksum
        case sourceEventIds = "source_event_ids"
    }
}

/// An HTTP or HTTPS link attached to an issue; the URL may not carry credentials.
public struct IssueLink: Codable, Sendable, Hashable {
    public var url: String
    public var title: String?

    public init(url: String, title: String? = nil) {
        self.url = url
        self.title = title
    }
}

/// A platform event attached to an issue.
public struct IssueEventReference: Codable, Sendable, Hashable {
    public var eventId: String

    public init(eventId: String) { self.eventId = eventId }

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
    }
}

/// A span attached to an issue: a 32-hex trace id and a 16-hex span id.
public struct IssueSpanReference: Codable, Sendable, Hashable {
    public var traceId: String
    public var spanId: String

    public init(traceId: String, spanId: String) {
        self.traceId = traceId
        self.spanId = spanId
    }

    enum CodingKeys: String, CodingKey {
        case traceId = "trace_id"
        case spanId = "span_id"
    }
}

/// One open human request on an issue, oldest first.
public struct IssueOpenRequest: Codable, Sendable, Hashable {
    public var id: String
    public var question: String?
    public var assigneeId: String?
    public var createdAt: Date?

    public init(id: String, question: String? = nil, assigneeId: String? = nil, createdAt: Date? = nil) {
        self.id = id
        self.question = question
        self.assigneeId = assigneeId
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, question
        case assigneeId = "assignee_id"
        case createdAt = "created_at"
    }
}

// MARK: Models

/// A project pursuit with a living brief and a fixed worker task. Its history is the activity stream in events.
public struct Issue: Codable, Sendable, Hashable {
    public var id: String
    public var orgId: String?
    public var projectId: String?
    /// Project-scoped display id.
    public var displayIndex: Int?
    public var title: String
    public var description: String?
    public var priority: IssuePriority?
    public var status: IssueStatus?
    /// Pass back as ``IssueUpdate/expectedRevision`` to edit the brief.
    public var revision: Int?
    /// Free-form tags, conventionally `key:value`; access-bearing, like file tags.
    public var tags: [String]?
    public var metadata: JSONObject?
    public var files: [IssueFile]?
    public var links: [IssueLink]?
    public var events: [IssueEventReference]?
    public var spans: [IssueSpanReference]?
    /// The fixed worker task behind the issue chat.
    public var taskId: String?
    public var taskStatus: TaskStatus?
    /// The owner of a private issue; nil for a project-owned (Operator) issue.
    public var memberId: String?
    /// When the issue last entered closed or cancelled.
    public var closedAt: Date?
    public var openRequests: [IssueOpenRequest]?
    public var createdAt: Date?
    public var updatedAt: Date?

    public init(
        id: String, title: String, orgId: String? = nil, projectId: String? = nil, displayIndex: Int? = nil,
        description: String? = nil, priority: IssuePriority? = nil, status: IssueStatus? = nil, revision: Int? = nil,
        tags: [String]? = nil, metadata: JSONObject? = nil, files: [IssueFile]? = nil, links: [IssueLink]? = nil,
        events: [IssueEventReference]? = nil, spans: [IssueSpanReference]? = nil, taskId: String? = nil,
        taskStatus: TaskStatus? = nil, memberId: String? = nil, closedAt: Date? = nil,
        openRequests: [IssueOpenRequest]? = nil, createdAt: Date? = nil, updatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.orgId = orgId
        self.projectId = projectId
        self.displayIndex = displayIndex
        self.description = description
        self.priority = priority
        self.status = status
        self.revision = revision
        self.tags = tags
        self.metadata = metadata
        self.files = files
        self.links = links
        self.events = events
        self.spans = spans
        self.taskId = taskId
        self.taskStatus = taskStatus
        self.memberId = memberId
        self.closedAt = closedAt
        self.openRequests = openRequests
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case orgId = "org_id"
        case projectId = "project_id"
        case displayIndex = "display_index"
        case title, description, priority, status, revision, tags, metadata, files, links, events, spans
        case taskId = "task_id"
        case taskStatus = "task_status"
        case memberId = "member_id"
        case closedAt = "closed_at"
        case openRequests = "open_requests"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Body of `POST /v1/issues`. Title and description must be nonblank.
public struct IssueCreate: Encodable, Sendable, Hashable {
    public var title: String
    public var description: String
    /// The fixed worker task used by the issue chat and Slack replies.
    public var taskId: String
    /// Server default `medium`.
    public var priority: IssuePriority?
    public var tags: [String]?
    /// Values are strings, numbers, booleans or null.
    public var metadata: JSONObject?
    public var files: [IssueFile]?
    public var links: [IssueLink]?
    public var events: [IssueEventReference]?
    public var spans: [IssueSpanReference]?

    public init(
        title: String, description: String, taskId: String, priority: IssuePriority? = nil, tags: [String]? = nil,
        metadata: JSONObject? = nil, files: [IssueFile]? = nil, links: [IssueLink]? = nil,
        events: [IssueEventReference]? = nil, spans: [IssueSpanReference]? = nil
    ) {
        self.title = title
        self.description = description
        self.taskId = taskId
        self.priority = priority
        self.tags = tags
        self.metadata = metadata
        self.files = files
        self.links = links
        self.events = events
        self.spans = spans
    }

    enum CodingKeys: String, CodingKey {
        case title, description
        case taskId = "task_id"
        case priority, tags, metadata, files, links, events, spans
    }
}

/// Body of `PATCH /v1/issues/{id}` editing the brief. Only set fields are sent; the lists and `metadata`
/// replace wholesale, so `[]` or `[:]` clears one.
public struct IssueUpdate: Encodable, Sendable, Hashable {
    /// The ``Issue/revision`` the edit is based on; a stale one is refused with a conflict.
    public var expectedRevision: Int
    public var title: String?
    public var description: String?
    public var priority: IssuePriority?
    public var status: IssueStatus?
    public var tags: [String]?
    public var metadata: JSONObject?
    public var files: [IssueFile]?
    public var links: [IssueLink]?
    public var events: [IssueEventReference]?
    public var spans: [IssueSpanReference]?

    public init(
        expectedRevision: Int, title: String? = nil, description: String? = nil, priority: IssuePriority? = nil,
        status: IssueStatus? = nil, tags: [String]? = nil, metadata: JSONObject? = nil, files: [IssueFile]? = nil,
        links: [IssueLink]? = nil, events: [IssueEventReference]? = nil, spans: [IssueSpanReference]? = nil
    ) {
        self.expectedRevision = expectedRevision
        self.title = title
        self.description = description
        self.priority = priority
        self.status = status
        self.tags = tags
        self.metadata = metadata
        self.files = files
        self.links = links
        self.events = events
        self.spans = spans
    }

    enum CodingKeys: String, CodingKey {
        case expectedRevision = "expected_revision"
        case title, description, priority, status, tags, metadata, files, links, events, spans
    }
}

/// Creates or changes one human request on an issue, sent as `PATCH /v1/issues/{id}` `{"request": ...}`.
///
/// A new request has `expectedRevision` 0 and needs `question` and `assigneeId`; closing one (`resolved` or
/// `cancelled`) needs a `resolution`.
public struct IssueRequestMutation: Encodable, Sendable, Hashable {
    /// The request's id; a new request takes a fresh one from the caller.
    public var id: String
    /// The request's current revision, or 0 to create it.
    public var expectedRevision: Int
    public var question: String?
    public var assigneeId: String?
    public var status: IssueRequestStatus?
    /// The decision and its basis.
    public var resolution: String?

    public init(
        id: String, expectedRevision: Int, question: String? = nil, assigneeId: String? = nil,
        status: IssueRequestStatus? = nil, resolution: String? = nil
    ) {
        self.id = id
        self.expectedRevision = expectedRevision
        self.question = question
        self.assigneeId = assigneeId
        self.status = status
        self.resolution = resolution
    }

    enum CodingKeys: String, CodingKey {
        case id
        case expectedRevision = "expected_revision"
        case question
        case assigneeId = "assignee_id"
        case status, resolution
    }
}

struct IssueMutation: Encodable {
    var request: IssueRequestMutation
}

/// Filters for `GET /v1/issues`. Rows come newest activity first; keep the filters unchanged while paging.
public struct IssueListParams: Sendable, Hashable {
    /// Page size, 1...200 (server default 50).
    public var limit: Int?
    public var next: String?
    /// ORed.
    public var status: [IssueStatus]?
    /// ORed; omit for every issue the caller may read.
    public var owner: [IssueOwner]?
    /// `true`: has an open request assigned to the caller; `false`: has none.
    public var assignedToMe: Bool?
    public var hasOpenRequests: Bool?
    /// The worker task's status.
    public var taskStatus: [TaskStatus]?
    /// Excludes these worker task statuses; an issue without a live task is kept.
    public var excludeTaskStatus: [TaskStatus]?
    public var displayIndex: Int?
    /// A `key:value` tag.
    public var tag: String?
    /// ANDed `key:value` metadata matches, at most 16.
    public var metadata: [String: String]?
    /// Case-insensitive substring of the title.
    public var search: String?
    /// Include `total_count` for the filtered set.
    public var includeTotal: Bool?

    public init(
        limit: Int? = nil, next: String? = nil, status: [IssueStatus]? = nil, owner: [IssueOwner]? = nil,
        assignedToMe: Bool? = nil, hasOpenRequests: Bool? = nil, taskStatus: [TaskStatus]? = nil,
        excludeTaskStatus: [TaskStatus]? = nil, displayIndex: Int? = nil, tag: String? = nil,
        metadata: [String: String]? = nil, search: String? = nil, includeTotal: Bool? = nil
    ) {
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
        self.search = search
        self.includeTotal = includeTotal
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
        query.add("search", search)
        query.add("include_total", includeTotal)
        return query
    }
}

// MARK: API

/// Data Plane `/v1/issues`. Writes accept an `Idempotency-Key`, so a retried call with the same key applies once.
public struct IssuesAPI: Sendable {
    let http: HTTPClient

    public init(http: HTTPClient) { self.http = http }

    /// List the issues the caller may read.
    public func list(_ params: IssueListParams = IssueListParams()) -> Paginator<Issue> {
        http.paginate("/v1/issues", query: params.query, start: params.next)
    }

    /// Create an issue.
    public func create(_ body: IssueCreate, idempotencyKey: String? = nil) async throws -> Issue {
        try await http.json("POST", "/v1/issues", body: .encode(body), headers: Self.headers(idempotencyKey))
    }

    /// Read one issue.
    public func get(_ issueId: String) async throws -> Issue {
        try await http.json("GET", "/v1/issues/\(pathSegment(issueId))")
    }

    /// Edit an issue's brief.
    public func update(_ issueId: String, _ body: IssueUpdate, idempotencyKey: String? = nil) async throws -> Issue {
        try await http.json(
            "PATCH", "/v1/issues/\(pathSegment(issueId))", body: .encode(body), headers: Self.headers(idempotencyKey))
    }

    /// Create or change one human request on an issue.
    public func update(_ issueId: String, request: IssueRequestMutation, idempotencyKey: String? = nil) async throws -> Issue {
        try await http.json(
            "PATCH", "/v1/issues/\(pathSegment(issueId))", body: .encode(IssueMutation(request: request)),
            headers: Self.headers(idempotencyKey))
    }

    /// Delete an issue (`issues:delete`).
    public func delete(_ issueId: String, idempotencyKey: String? = nil) async throws {
        try await http.empty("DELETE", "/v1/issues/\(pathSegment(issueId))", headers: Self.headers(idempotencyKey))
    }

    private static func headers(_ idempotencyKey: String?) -> [String: String] {
        idempotencyKey.map { ["Idempotency-Key": $0] } ?? [:]
    }
}

extension DataPlaneConnection {
    /// Project issues: pursuits with a living brief and a fixed worker task.
    public var issues: IssuesAPI { IssuesAPI(http: dataPlane) }
}
