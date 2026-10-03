import Foundation

// MARK: Organization

/// The caller's organization.
public struct Organization: Codable, Sendable, Hashable {
    public var id: String
    public var name: String?
    public var slug: String?
    public var externalOrgId: String?
    public var imageUrl: String?
    public var hostedGit: Bool?

    public init(id: String, name: String? = nil, slug: String? = nil, externalOrgId: String? = nil, imageUrl: String? = nil, hostedGit: Bool? = nil) {
        self.id = id
        self.name = name
        self.slug = slug
        self.externalOrgId = externalOrgId
        self.imageUrl = imageUrl
        self.hostedGit = hostedGit
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, slug
        case externalOrgId = "external_org_id"
        case imageUrl = "image_url"
        case hostedGit = "hosted_git"
    }
}

/// Read access to the caller's organization.
public struct OrganizationsAPI: Sendable {
    let http: HTTPClient

    public init(http: HTTPClient) { self.http = http }

    /// `GET /v1/organizations/current`.
    public func current() async throws -> Organization {
        try await http.json("GET", "/v1/organizations/current")
    }
}

// MARK: Projects

/// A project in the caller's organization.
public struct Project: Codable, Sendable, Hashable {
    public var id: String
    public var orgId: String?
    public var deploymentId: String?
    public var name: String?
    public var slug: String?
    public var description: String?
    public var settings: JSONObject?
    public var createdByMemberId: String?

    public init(
        id: String, orgId: String? = nil, deploymentId: String? = nil, name: String? = nil, slug: String? = nil,
        description: String? = nil, settings: JSONObject? = nil, createdByMemberId: String? = nil
    ) {
        self.id = id
        self.orgId = orgId
        self.deploymentId = deploymentId
        self.name = name
        self.slug = slug
        self.description = description
        self.settings = settings
        self.createdByMemberId = createdByMemberId
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, slug, description, settings
        case orgId = "org_id"
        case deploymentId = "deployment_id"
        case createdByMemberId = "created_by_member_id"
    }
}

/// Paging and filters for `GET /v1/projects`.
public struct ProjectListParams: Sendable, Hashable {
    /// Only the project with this slug or id.
    public var project: String?
    public var limit: Int?
    public var next: String?

    public init(project: String? = nil, limit: Int? = nil, next: String? = nil) {
        self.project = project
        self.limit = limit
        self.next = next
    }
}

/// Read access to `/v1/projects`.
public struct ProjectsAPI: Sendable {
    let http: HTTPClient

    public init(http: HTTPClient) { self.http = http }

    /// List the organization's projects.
    public func list(_ params: ProjectListParams = ProjectListParams()) -> Paginator<Project> {
        var query = Query()
        query.add("project", params.project)
        query.add("limit", params.limit)
        return http.paginate("/v1/projects", query: query, start: params.next)
    }

    /// Fetch a project by slug or id.
    public func get(_ project: String) async throws -> Project {
        try await http.json("GET", "/v1/projects/\(pathSegment(project))")
    }
}

// MARK: Members

/// What kind of principal a member is.
public struct MemberType: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    /// A person at the business.
    public static let business: MemberType = "business"
    /// A system agent or service account.
    public static let agent: MemberType = "agent"
    /// A federated end customer.
    public static let customer: MemberType = "customer"
}

/// A member of the organization.
public struct Member: Codable, Sendable, Hashable {
    public var id: String
    public var orgId: String?
    public var email: String?
    public var name: String?
    public var externalUserId: String?
    public var imageUrl: String?
    public var role: String?
    public var memberType: MemberType?
    public var isDeactivated: Bool?
    public var tags: [String]?
    public var applicationIdpId: String?
    public var connectorId: String?
    public var integrationId: String?
    public var isExternalCredentialAgent: Bool?
    public var createdAt: Date?
    public var updatedAt: Date?

    public init(
        id: String, orgId: String? = nil, email: String? = nil, name: String? = nil, externalUserId: String? = nil,
        imageUrl: String? = nil, role: String? = nil, memberType: MemberType? = nil, isDeactivated: Bool? = nil,
        tags: [String]? = nil, applicationIdpId: String? = nil, connectorId: String? = nil,
        integrationId: String? = nil, isExternalCredentialAgent: Bool? = nil, createdAt: Date? = nil, updatedAt: Date? = nil
    ) {
        self.id = id
        self.orgId = orgId
        self.email = email
        self.name = name
        self.externalUserId = externalUserId
        self.imageUrl = imageUrl
        self.role = role
        self.memberType = memberType
        self.isDeactivated = isDeactivated
        self.tags = tags
        self.applicationIdpId = applicationIdpId
        self.connectorId = connectorId
        self.integrationId = integrationId
        self.isExternalCredentialAgent = isExternalCredentialAgent
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, email, name, role, tags
        case orgId = "org_id"
        case externalUserId = "external_user_id"
        case imageUrl = "image_url"
        case memberType = "member_type"
        case isDeactivated = "is_deactivated"
        case applicationIdpId = "application_idp_id"
        case connectorId = "connector_id"
        case integrationId = "integration_id"
        case isExternalCredentialAgent = "is_external_credential_agent"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Filters for `GET /v1/members`.
public struct MemberListParams: Sendable, Hashable {
    public var memberType: MemberType?
    /// Customer members minted by one connector's deliveries.
    public var connectorId: String?
    /// Customer members federated through one brokered IdP.
    public var applicationIdpId: String?
    /// A `key:value` grouping tag, for example `customer:acme`.
    public var tag: String?
    /// Resolve these member ids (unions with `externalUserIds`).
    public var ids: [String]?
    /// Resolve these tier-prefixed external keys, for example `user:abc`.
    public var externalUserIds: [String]?
    /// Project id, for deployment-authenticated reads.
    public var project: String?
    public var limit: Int?
    public var next: String?

    public init(
        memberType: MemberType? = nil, connectorId: String? = nil, applicationIdpId: String? = nil, tag: String? = nil,
        ids: [String]? = nil, externalUserIds: [String]? = nil, project: String? = nil, limit: Int? = nil, next: String? = nil
    ) {
        self.memberType = memberType
        self.connectorId = connectorId
        self.applicationIdpId = applicationIdpId
        self.tag = tag
        self.ids = ids
        self.externalUserIds = externalUserIds
        self.project = project
        self.limit = limit
        self.next = next
    }
}

/// The signed-in principal, from `GET /v1/oidc/me`.
public struct CurrentMember: Codable, Sendable, Hashable {
    public var authenticated: Bool?
    public var orgId: String?
    public var memberId: String?
    public var email: String?
    public var name: String?
    public var picture: String?
    /// Server-evaluated feature flags.
    public var featureFlags: JSONObject?
    /// Set when this session is an operator impersonating the member.
    public var impersonatingMemberId: String?
    public var impersonatorEmail: String?

    public init(
        authenticated: Bool? = nil, orgId: String? = nil, memberId: String? = nil, email: String? = nil,
        name: String? = nil, picture: String? = nil, featureFlags: JSONObject? = nil,
        impersonatingMemberId: String? = nil, impersonatorEmail: String? = nil
    ) {
        self.authenticated = authenticated
        self.orgId = orgId
        self.memberId = memberId
        self.email = email
        self.name = name
        self.picture = picture
        self.featureFlags = featureFlags
        self.impersonatingMemberId = impersonatingMemberId
        self.impersonatorEmail = impersonatorEmail
    }

    private enum CodingKeys: String, CodingKey {
        case authenticated, email, name, picture
        case orgId = "org_id"
        case memberId = "member_id"
        case featureFlags = "feature_flags"
        case impersonatingMemberId = "impersonating_member_id"
        case impersonatorEmail = "impersonator_email"
    }
}

/// Read access to `/v1/members`.
public struct MembersAPI: Sendable {
    let http: HTTPClient

    public init(http: HTTPClient) { self.http = http }

    /// List the organization's members.
    public func list(_ params: MemberListParams = MemberListParams()) -> Paginator<Member> {
        var query = Query()
        query.add("project", params.project)
        query.add("member_type", params.memberType)
        query.add("connector_id", params.connectorId)
        query.add("application_idp_id", params.applicationIdpId)
        query.add("tag", params.tag)
        query.add("id", params.ids)
        query.add("external_user_id", params.externalUserIds)
        query.add("limit", params.limit)
        return http.paginate("/v1/members", query: query, start: params.next)
    }

    /// Fetch one member.
    public func get(_ memberId: String, project: String? = nil) async throws -> Member {
        try await http.json("GET", "/v1/members/\(pathSegment(memberId))", query: cpProjectQuery(project))
    }

    /// The signed-in principal (`GET /v1/oidc/me`).
    public func me() async throws -> CurrentMember {
        try await http.json("GET", "/v1/oidc/me")
    }
}

extension IntrospectionClient {
    /// The caller's organization.
    public var organizations: OrganizationsAPI { OrganizationsAPI(http: controlPlane) }

    /// Projects in the caller's organization.
    public var projects: ProjectsAPI { ProjectsAPI(http: controlPlane) }

    /// Members of the caller's organization.
    public var members: MembersAPI { MembersAPI(http: controlPlane) }
}
