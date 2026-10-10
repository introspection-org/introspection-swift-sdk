import Foundation

/// The resource family a share grant targets. Tasks are not shareable.
public struct ShareResourceType: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }

    public static let file: ShareResourceType = "file"
    public static let conversation: ShareResourceType = "conversation"
    public static let issue: ShareResourceType = "issue"
    /// Written only by the control plane; never created through `/v1/shares`.
    public static let channel: ShareResourceType = "channel"
}

/// A sharing grant for a file, conversation or issue. A share admits its grantee; the caller's token scopes decide
/// what they may then do.
public struct ResourceShare: Codable, Sendable, Hashable {
    public var id: String
    public var orgId: String?
    public var projectId: String?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var deletedAt: Date?
    public var resourceType: ShareResourceType
    public var resourceId: String
    /// Admits only this member; ANDed with `grantedTag`, and nil for both means a project-wide grant.
    public var grantedMemberId: String?
    /// Admits only callers whose token carries this tag.
    public var grantedTag: String?
    /// Conversation shares only: spans before this instant stay hidden from share-only readers.
    public var visibleFrom: Date?
    /// The grantor, who alone (with privileged callers) may revoke.
    public var createdByMemberId: String?
    /// Fully-qualified URL of the shared resource; it carries no capability.
    public var url: String?

    public init(
        id: String, resourceType: ShareResourceType, resourceId: String, orgId: String? = nil,
        projectId: String? = nil, createdAt: Date? = nil, updatedAt: Date? = nil, grantedMemberId: String? = nil,
        createdByMemberId: String? = nil, url: String? = nil, grantedTag: String? = nil, visibleFrom: Date? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.resourceType = resourceType
        self.resourceId = resourceId
        self.orgId = orgId
        self.projectId = projectId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.grantedMemberId = grantedMemberId
        self.createdByMemberId = createdByMemberId
        self.url = url
        self.grantedTag = grantedTag
        self.visibleFrom = visibleFrom
        self.deletedAt = deletedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, url
        case orgId = "org_id"
        case projectId = "project_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case resourceType = "resource_type"
        case resourceId = "resource_id"
        case grantedMemberId = "granted_member_id"
        case grantedTag = "granted_tag"
        case visibleFrom = "visible_from"
        case createdByMemberId = "created_by_member_id"
    }
}

/// Body for `POST /v1/shares`. The grantee fields are ANDed; omit both for a project-wide grant.
public struct ShareCreate: Encodable, Sendable, Hashable {
    public var resourceType: ShareResourceType
    public var resourceId: String
    public var grantedMemberId: String?
    /// Admit only holders of this tag; the grantor must hold it.
    public var grantedTag: String?
    /// Conversation shares only; must not be in the future.
    public var visibleFrom: Date?

    public init(
        resourceType: ShareResourceType, resourceId: String, grantedMemberId: String? = nil, grantedTag: String? = nil,
        visibleFrom: Date? = nil
    ) {
        self.resourceType = resourceType
        self.resourceId = resourceId
        self.grantedMemberId = grantedMemberId
        self.grantedTag = grantedTag
        self.visibleFrom = visibleFrom
    }

    private enum CodingKeys: String, CodingKey {
        case resourceType = "resource_type"
        case resourceId = "resource_id"
        case grantedMemberId = "granted_member_id"
        case grantedTag = "granted_tag"
        case visibleFrom = "visible_from"
    }
}

/// Body for `PATCH /v1/shares/{id}`, on a conversation share. A nil `visibleFrom` is sent as `null`, which clears it.
public struct ShareUpdate: Encodable, Sendable, Hashable {
    public var visibleFrom: Date?

    public init(visibleFrom: Date?) { self.visibleFrom = visibleFrom }

    private enum CodingKeys: String, CodingKey {
        case visibleFrom = "visible_from"
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(visibleFrom, forKey: .visibleFrom)
    }
}

/// Filters for `GET /v1/shares`.
public struct ShareListParams: Sendable, Hashable {
    public var limit: Int?
    public var next: String?
    public var resourceType: ShareResourceType?
    public var resourceId: String?
    public var grantedMemberId: String?
    public var grantedTag: String?
    /// Only shares the caller created.
    public var createdByMe: Bool?
    /// Only shares naming the caller: their member, a tag they hold, or both.
    public var grantedToMe: Bool?

    public init(
        limit: Int? = nil, next: String? = nil, resourceType: ShareResourceType? = nil, resourceId: String? = nil,
        grantedMemberId: String? = nil, createdByMe: Bool? = nil, grantedToMe: Bool? = nil, grantedTag: String? = nil
    ) {
        self.limit = limit
        self.next = next
        self.resourceType = resourceType
        self.resourceId = resourceId
        self.grantedMemberId = grantedMemberId
        self.createdByMe = createdByMe
        self.grantedToMe = grantedToMe
        self.grantedTag = grantedTag
    }
}

/// Sharing grants (`/v1/shares`). A share admits its grantee; the caller's scopes decide what they may do.
public struct SharesAPI: Sendable {
    let http: HTTPClient

    public init(http: HTTPClient) { self.http = http }

    /// List grants the caller created or that target them.
    public func list(_ params: ShareListParams = ShareListParams()) -> Paginator<ResourceShare> {
        var query = Query()
        query.add("limit", params.limit)
        query.add("resource_type", params.resourceType)
        query.add("resource_id", params.resourceId)
        query.add("granted_member_id", params.grantedMemberId)
        query.add("granted_tag", params.grantedTag)
        query.add("created_by_me", params.createdByMe)
        query.add("granted_to_me", params.grantedToMe)
        return http.paginate("/v1/shares", query: query, start: params.next)
    }

    /// Create a grant. The caller must own the target resource, and hold the tag a tag share names.
    public func create(_ body: ShareCreate) async throws -> ResourceShare {
        try await http.json("POST", "/v1/shares", body: .encode(body))
    }

    /// Read one grant.
    public func get(_ shareId: String) async throws -> ResourceShare {
        try await http.json("GET", "/v1/shares/\(pathSegment(shareId))")
    }

    /// Change a conversation share's `visibleFrom` (grantor or privileged caller only).
    public func update(_ shareId: String, _ body: ShareUpdate) async throws -> ResourceShare {
        try await http.json("PATCH", "/v1/shares/\(pathSegment(shareId))", body: .encode(body))
    }

    /// Revoke a grant (grantor or privileged caller only).
    public func delete(_ shareId: String) async throws {
        try await http.empty("DELETE", "/v1/shares/\(pathSegment(shareId))")
    }
}

extension DataPlaneConnection {
    /// Sharing grants for files, conversations and issues.
    public var shares: SharesAPI { SharesAPI(http: dataPlane) }
}
