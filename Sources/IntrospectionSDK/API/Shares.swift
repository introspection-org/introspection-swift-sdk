import Foundation

/// The resource family a share grant targets. Tasks are not shareable.
public struct ShareResourceType: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }

    public static let file: ShareResourceType = "file"
    public static let conversation: ShareResourceType = "conversation"
    /// Written only by the control plane; never created through `/v1/shares`.
    public static let channel: ShareResourceType = "channel"
}

/// A read-sharing grant for a file or conversation.
public struct ResourceShare: Codable, Sendable, Hashable {
    public var id: String
    public var orgId: String?
    public var projectId: String?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var resourceType: ShareResourceType
    public var resourceId: String
    /// Targeted member; nil means a project-wide grant.
    public var grantedMemberId: String?
    /// The grantor, who alone (with privileged callers) may revoke.
    public var createdByMemberId: String?
    /// Fully-qualified URL of the shared resource, carrying the `share_id` capability.
    public var url: String?

    public init(
        id: String, resourceType: ShareResourceType, resourceId: String, orgId: String? = nil,
        projectId: String? = nil, createdAt: Date? = nil, updatedAt: Date? = nil, grantedMemberId: String? = nil,
        createdByMemberId: String? = nil, url: String? = nil
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
    }

    private enum CodingKeys: String, CodingKey {
        case id, url
        case orgId = "org_id"
        case projectId = "project_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case resourceType = "resource_type"
        case resourceId = "resource_id"
        case grantedMemberId = "granted_member_id"
        case createdByMemberId = "created_by_member_id"
    }
}

/// Body for `POST /v1/shares`. Omit `grantedMemberId` for a project-wide grant.
public struct ShareCreate: Encodable, Sendable, Hashable {
    public var resourceType: ShareResourceType
    public var resourceId: String
    public var grantedMemberId: String?

    public init(resourceType: ShareResourceType, resourceId: String, grantedMemberId: String? = nil) {
        self.resourceType = resourceType
        self.resourceId = resourceId
        self.grantedMemberId = grantedMemberId
    }

    private enum CodingKeys: String, CodingKey {
        case resourceType = "resource_type"
        case resourceId = "resource_id"
        case grantedMemberId = "granted_member_id"
    }
}

/// Filters for `GET /v1/shares`.
public struct ShareListParams: Sendable, Hashable {
    public var limit: Int?
    public var next: String?
    public var resourceType: ShareResourceType?
    public var resourceId: String?
    public var grantedMemberId: String?
    /// Only shares the caller created.
    public var createdByMe: Bool?
    /// Only shares targeting the caller.
    public var grantedToMe: Bool?

    public init(
        limit: Int? = nil, next: String? = nil, resourceType: ShareResourceType? = nil, resourceId: String? = nil,
        grantedMemberId: String? = nil, createdByMe: Bool? = nil, grantedToMe: Bool? = nil
    ) {
        self.limit = limit
        self.next = next
        self.resourceType = resourceType
        self.resourceId = resourceId
        self.grantedMemberId = grantedMemberId
        self.createdByMe = createdByMe
        self.grantedToMe = grantedToMe
    }
}

/// Read-sharing grants (`/v1/shares`).
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
        query.add("created_by_me", params.createdByMe)
        query.add("granted_to_me", params.grantedToMe)
        return http.paginate("/v1/shares", query: query, start: params.next)
    }

    /// Create a grant. The caller must own the target resource.
    public func create(_ body: ShareCreate) async throws -> ResourceShare {
        try await http.json("POST", "/v1/shares", body: .encode(body))
    }

    /// Read one grant.
    public func get(_ shareId: String) async throws -> ResourceShare {
        try await http.json("GET", "/v1/shares/\(pathSegment(shareId))")
    }

    /// Revoke a grant (grantor or privileged caller only).
    public func delete(_ shareId: String) async throws {
        try await http.empty("DELETE", "/v1/shares/\(pathSegment(shareId))")
    }
}

extension DataPlaneConnection {
    /// Read-sharing grants for files and conversations.
    public var shares: SharesAPI { SharesAPI(http: dataPlane) }
}
