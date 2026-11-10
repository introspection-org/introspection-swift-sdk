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

/// How a member stands to an issue. Unknown server values are preserved.
public struct IssueMemberRelation: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public init(from decoder: any Decoder) throws { rawValue = try decoder.singleString() }
    public func encode(to encoder: any Encoder) throws { try encoder.encodeSingle(rawValue) }

    public static let creator: IssueMemberRelation = "creator"
    public static let assignee: IssueMemberRelation = "assignee"
    public static let reviewer: IssueMemberRelation = "reviewer"
    public static let follower: IssueMemberRelation = "follower"
}

/// The related lists an issue read or write returns with the brief (repeated `include`).
public struct IssueInclude: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }

    /// `members`.
    public static let members: IssueInclude = "members"
    /// `links`, `files`, `events` and `spans`.
    public static let attachments: IssueInclude = "attachments"
    /// `comments`, at most 500, on ``IssuesAPI/get(_:include:)`` only; the list and the writes refuse it with 422.
    public static let comments: IssueInclude = "comments"
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

/// One person on an issue.
public struct IssueMember: Codable, Sendable, Hashable {
    public let memberId: String
    public let relation: IssueMemberRelation

    enum CodingKeys: String, CodingKey {
        case relation
        case memberId = "member_id"
    }
}

/// One comment on an issue. Comments are append-only: they cannot be edited or deleted.
public struct IssueComment: Codable, Sendable, Hashable {
    /// The comment's id, which is its event's id.
    public let id: String
    public let issueId: String
    public let comment: String
    /// The member who commented.
    public let memberId: String?
    /// The member acting for `memberId`, when delegated.
    public let actorMemberId: String?
    /// The actor's capacity: `agent`, `dev` or `impersonation`.
    public let actorMemberType: String?
    public let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, comment
        case issueId = "issue_id"
        case memberId = "member_id"
        case actorMemberId = "actor_member_id"
        case actorMemberType = "actor_member_type"
        case createdAt = "created_at"
    }
}

/// An issue: its brief, and each related list the read asked for with `include`. A list that was not
/// included is nil.
public struct Issue: Codable, Sendable, Hashable {
    public let id: String
    public let orgId: String
    public let projectId: String
    public let title: String
    public let description: String
    public let priority: IssuePriority
    public let status: IssueStatus
    /// Orders the issue's snapshots on the server; conditional writes use ``etag`` instead.
    public let revision: Int
    /// Project-scoped display ID.
    public let displayIndex: Int?
    /// Free-form tags, conventionally `key:value`.
    public let tags: [String]
    /// Caller-defined attributes; values are strings, numbers, booleans or null.
    public let metadata: JSONObject
    /// The fixed worker task behind the issue chat and Slack replies.
    public let taskId: String?
    public let taskStatus: TaskStatus?
    /// The owner of a private issue; nil for a project-owned (Operator) issue.
    public let memberId: String?
    /// Nil when the issue was created by a caller that is not a member.
    public let createdByMemberId: String?
    public let assigneeMemberId: String?
    public let reviewerMemberId: String?
    /// When the issue last entered `closed` or `cancelled`.
    public let closedAt: Date?
    /// With `.members`: the creator, then the assignee, the reviewer, and the followers in the order they were added.
    public let members: [IssueMember]?
    /// With `.attachments`.
    public let links: [IssueLink]?
    /// With `.attachments`.
    public let files: [IssueFile]?
    /// With `.attachments`.
    public let events: [IssueEventReference]?
    /// With `.attachments`.
    public let spans: [IssueSpanReference]?
    /// With `.comments`: oldest first, at most 500. Page the issue's events for more.
    public let comments: [IssueComment]?
    public let createdAt: Date?
    public var updatedAt: Date? { updatedAtStamp?.date }
    private let updatedAtStamp: WireTimestamp?

    enum CodingKeys: String, CodingKey {
        case id
        case orgId = "org_id"
        case projectId = "project_id"
        case title, description, priority, status, revision
        case displayIndex = "display_index"
        case tags, metadata
        case taskId = "task_id"
        case taskStatus = "task_status"
        case memberId = "member_id"
        case createdByMemberId = "created_by_member_id"
        case assigneeMemberId = "assignee_member_id"
        case reviewerMemberId = "reviewer_member_id"
        case closedAt = "closed_at"
        case members, links, files, events, spans, comments
        case createdAt = "created_at"
        case updatedAtStamp = "updated_at"
    }

    /// The `ETag` the server sends for this issue, to pass as `ifMatch`: `updated_at` exactly as received, quoted.
    /// Nil without it.
    public var etag: String? { updatedAtStamp?.text.map { "\"\($0)\"" } }
}

/// A timestamp that keeps its wire text: the server compares `If-Match` to the microsecond, finer than a `Date`
/// decoded by ``ISO8601`` keeps.
private struct WireTimestamp: Codable, Sendable, Hashable {
    let date: Date
    let text: String?

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        date = try container.decode(Date.self)
        text = try? container.decode(String.self)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        if let text { try container.encode(text) } else { try container.encode(date) }
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
    public var assigneeMemberId: String?
    public var reviewerMemberId: String?
    /// At most 50, each once.
    public var followerMemberIds: [String]?

    enum CodingKeys: String, CodingKey {
        case title, description
        case taskId = "task_id"
        case priority, files, links, events, spans, tags, metadata
        case assigneeMemberId = "assignee_member_id"
        case reviewerMemberId = "reviewer_member_id"
        case followerMemberIds = "follower_member_ids"
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
        metadata: JSONObject? = nil,
        assigneeMemberId: String? = nil,
        reviewerMemberId: String? = nil,
        followerMemberIds: [String]? = nil
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
        self.assigneeMemberId = assigneeMemberId
        self.reviewerMemberId = reviewerMemberId
        self.followerMemberIds = followerMemberIds
    }
}

/// An edit to an issue (`PATCH /v1/issues/{id}`). Nil fields are omitted and stay unchanged; each list
/// and `metadata` replaces its value wholesale, so `[]` (or `[:]`) clears it.
///
/// The API tells an omitted assignee or reviewer from a null one, so `assigneeMemberId: .some(nil)` unassigns
/// the issue and leaving it `nil` leaves the assignee alone; `reviewerMemberId` is the same.
public struct IssueUpdate: Encodable, Sendable, Hashable {
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
    public var assigneeMemberId: String??
    public var reviewerMemberId: String??
    /// Replaces the followers wholesale (at most 50, each once).
    public var followerMemberIds: [String]?

    enum CodingKeys: String, CodingKey {
        case title, description, priority, status, files, links, events, spans, tags, metadata
        case assigneeMemberId = "assignee_member_id"
        case reviewerMemberId = "reviewer_member_id"
        case followerMemberIds = "follower_member_ids"
    }

    public init(
        title: String? = nil,
        description: String? = nil,
        priority: IssuePriority? = nil,
        status: IssueStatus? = nil,
        files: [IssueFile]? = nil,
        links: [IssueLink]? = nil,
        events: [IssueEventReference]? = nil,
        spans: [IssueSpanReference]? = nil,
        tags: [String]? = nil,
        metadata: JSONObject? = nil,
        assigneeMemberId: String?? = nil,
        reviewerMemberId: String?? = nil,
        followerMemberIds: [String]? = nil
    ) {
        // jscpd:ignore-start: memberwise init of a public type; the assignments cannot be shared
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
        self.assigneeMemberId = assigneeMemberId
        self.reviewerMemberId = reviewerMemberId
        self.followerMemberIds = followerMemberIds
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(priority, forKey: .priority)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(files, forKey: .files)
        try container.encodeIfPresent(links, forKey: .links)
        try container.encodeIfPresent(events, forKey: .events)
        try container.encodeIfPresent(spans, forKey: .spans)
        try container.encodeIfPresent(tags, forKey: .tags)
        try container.encodeIfPresent(metadata, forKey: .metadata)
        // An omitted key leaves the member; an explicit null clears it.
        if let assigneeMemberId { try container.encode(assigneeMemberId, forKey: .assigneeMemberId) }
        if let reviewerMemberId { try container.encode(reviewerMemberId, forKey: .reviewerMemberId) }
        try container.encodeIfPresent(followerMemberIds, forKey: .followerMemberIds)
    }
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
    /// ORed. On its own, the issues the caller is on in one of these relations; with `memberId`, that member's.
    public var relation: [IssueMemberRelation]?
    /// The member whose relations to match instead of the caller's; alone, any relation.
    public var memberId: String?
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
    /// `.members` and `.attachments`.
    public var include: [IssueInclude]?

    public init(
        limit: Int? = nil,
        next: String? = nil,
        status: [IssueStatus]? = nil,
        owner: [IssueOwner]? = nil,
        relation: [IssueMemberRelation]? = nil,
        memberId: String? = nil,
        taskStatus: [TaskStatus]? = nil,
        excludeTaskStatus: [TaskStatus]? = nil,
        displayIndex: Int? = nil,
        tag: String? = nil,
        metadata: [String: String]? = nil,
        includeTotal: Bool? = nil,
        include: [IssueInclude]? = nil
    ) {
        // jscpd:ignore-start: memberwise init of a public type; the assignments cannot be shared
        self.limit = limit
        self.next = next
        self.status = status
        self.owner = owner
        self.relation = relation
        self.memberId = memberId
        self.taskStatus = taskStatus
        self.excludeTaskStatus = excludeTaskStatus
        self.displayIndex = displayIndex
        self.tag = tag
        self.metadata = metadata
        self.includeTotal = includeTotal
        // jscpd:ignore-end
        self.include = include
    }

    var query: Query {
        var query = Query()
        query.add("limit", limit)
        query.add("status", status)
        query.add("owner", owner)
        query.add("relation", relation)
        query.add("member_id", memberId)
        query.add("task_status", taskStatus)
        query.add("exclude_task_status", excludeTaskStatus)
        query.add("display_index", displayIndex)
        query.add("tag", tag)
        query.add("metadata", metadata.map { pairs in pairs.keys.sorted().compactMap { key in pairs[key].map { "\(key):\($0)" } } })
        query.add("include_total", includeTotal)
        query.add("include", include)
        return query
    }
}

// MARK: API

/// Data Plane `/v1/issues`. An edit applies the fields it names and the last write wins; pass ``Issue/etag`` as
/// `ifMatch` to have a brief edit or delete refused with 412 when the issue changed since it was read.
public struct IssuesAPI: Sendable {
    let http: HTTPClient

    public init(http: HTTPClient) {
        self.http = http
    }

    /// List the issues the caller may read, newest activity first.
    public func list(_ params: IssueListParams = IssueListParams()) -> Paginator<Issue> {
        http.paginate("/v1/issues", query: params.query, start: params.next, as: Issue.self)
    }

    /// Open an issue on its worker task. It starts `open`; repeating it for the same task is safe.
    public func create(_ body: IssueCreate, include: [IssueInclude]? = nil) async throws -> Issue {
        try await http.json("POST", "/v1/issues", query: includeQuery(include), body: try .encode(body), as: Issue.self)
    }

    /// Read one issue's brief, with the lists `include` names.
    public func get(_ issueId: String, include: [IssueInclude]? = nil) async throws -> Issue {
        try await http.json("GET", "/v1/issues/\(pathSegment(issueId))", query: includeQuery(include), as: Issue.self)
    }

    /// Edit an issue. With `ifMatch` (an ``Issue/etag``), a changed issue is refused with 412.
    public func update(
        _ issueId: String, _ body: IssueUpdate, ifMatch: String? = nil, include: [IssueInclude]? = nil
    ) async throws -> Issue {
        try await http.json(
            "PATCH", "/v1/issues/\(pathSegment(issueId))", query: includeQuery(include), body: try .encode(body),
            headers: ifMatchHeaders(ifMatch), as: Issue.self
        )
    }

    /// Soft-delete an issue. Its activity history is kept. With `ifMatch`, a changed issue is refused with 412.
    public func delete(_ issueId: String, ifMatch: String? = nil) async throws {
        try await http.empty("DELETE", "/v1/issues/\(pathSegment(issueId))", headers: ifMatchHeaders(ifMatch))
    }

    /// Comments on an issue.
    public var comments: IssueCommentsAPI { IssueCommentsAPI(http: http) }

    private func includeQuery(_ include: [IssueInclude]?) -> Query {
        var query = Query()
        query.add("include", include)
        return query
    }

    private func ifMatchHeaders(_ tag: String?) -> [String: String] {
        tag.map { ["If-Match": $0] } ?? [:]
    }
}

/// Comments of an issue (`/v1/issues/{id}/comments`). They are read with `include: [.comments]` on
/// ``IssuesAPI/get(_:include:)`` or from the issue's events; there is no list route.
public struct IssueCommentsAPI: Sendable {
    let http: HTTPClient

    public init(http: HTTPClient) { self.http = http }

    /// Comment on an issue. The comment is recorded as an event and does not change the issue's `etag`; a read
    /// made straight after may not include it yet.
    public func create(_ issueId: String, comment: String) async throws -> IssueComment {
        try await http.json(
            "POST", "/v1/issues/\(pathSegment(issueId))/comments", body: try .encode(IssueCommentCreate(comment: comment)),
            as: IssueComment.self
        )
    }
}

private struct IssueCommentCreate: Encodable {
    let comment: String
}

extension DataPlaneConnection {
    /// Data Plane issues (`/v1/issues`).
    public var issues: IssuesAPI { IssuesAPI(http: dataPlane) }
}
