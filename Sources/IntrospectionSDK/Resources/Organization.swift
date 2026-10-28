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

    public init(
        id: String, name: String? = nil, slug: String? = nil, externalOrgId: String? = nil, imageUrl: String? = nil, hostedGit: Bool? = nil
    ) {
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

    /// `GET /v1/organizations/me`.
    public func current() async throws -> Organization {
        try await http.json("GET", "/v1/organizations/me")
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

/// The body of `POST /v1/projects`.
public struct ProjectCreate: Encodable, Sendable, Hashable {
    public var name: String
    /// The deployment the project runs on; it must be able to take new projects.
    public var deploymentId: String
    /// A stable identifier; the server derives one from `name` when omitted.
    public var slug: String?
    public var description: String?
    public var settings: JSONObject?
    /// Seed the Ark runtime. Unset, an organization's first project takes it and later ones do not.
    public var includeArk: Bool?

    public init(
        name: String, deploymentId: String, slug: String? = nil, description: String? = nil, settings: JSONObject? = nil,
        includeArk: Bool? = nil
    ) {
        self.name = name
        self.deploymentId = deploymentId
        self.slug = slug
        self.description = description
        self.settings = settings
        self.includeArk = includeArk
    }

    private enum CodingKeys: String, CodingKey {
        case name, slug, description, settings
        case deploymentId = "deployment_id"
        case includeArk = "include_ark"
    }
}

/// The body of `PATCH /v1/projects/{project}`. A body with every field nil is refused as "no fields to update".
public struct ProjectUpdate: Encodable, Sendable, Hashable {
    public var name: String?
    public var description: String?
    public var settings: JSONObject?

    public init(name: String? = nil, description: String? = nil, settings: JSONObject? = nil) {
        self.name = name
        self.description = description
        self.settings = settings
    }
}

/// `/v1/projects`.
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

    /// Create a project. A slug already taken in the organization is a conflict.
    public func create(_ body: ProjectCreate) async throws -> Project {
        try await http.json("POST", "/v1/projects", body: .encode(body))
    }

    /// Update a project, by slug or id.
    public func update(_ project: String, _ body: ProjectUpdate) async throws -> Project {
        try await http.json("PATCH", "/v1/projects/\(pathSegment(project))", body: .encode(body))
    }

    /// Soft-delete a project, by slug or id, with its project-scoped resources and credentials.
    public func delete(_ project: String) async throws {
        try await http.empty("DELETE", "/v1/projects/\(pathSegment(project))")
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
    /// Access-bearing: the member can read and write files and tasks whose tags intersect these.
    public var tags: [String]?
    /// Customer-defined `key: value` labels; filterable, and grants nothing.
    public var metadata: [String: String]?
    public var applicationIdpId: String?
    public var connectorId: String?
    public var integrationId: String?
    public var isExternalCredentialAgent: Bool?
    /// Attributes the recipe's Cedar policies read for this member.
    public var policyAttributes: JSONObject?
    public var createdAt: Date?
    public var updatedAt: Date?

    public init(
        id: String, orgId: String? = nil, email: String? = nil, name: String? = nil, externalUserId: String? = nil,
        imageUrl: String? = nil, role: String? = nil, memberType: MemberType? = nil, isDeactivated: Bool? = nil,
        tags: [String]? = nil, metadata: [String: String]? = nil, applicationIdpId: String? = nil, connectorId: String? = nil,
        integrationId: String? = nil, isExternalCredentialAgent: Bool? = nil, policyAttributes: JSONObject? = nil,
        createdAt: Date? = nil, updatedAt: Date? = nil
    ) {
        // jscpd:ignore-start: memberwise init of a public type; the assignments cannot be shared
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
        self.metadata = metadata
        self.applicationIdpId = applicationIdpId
        self.connectorId = connectorId
        self.integrationId = integrationId
        self.isExternalCredentialAgent = isExternalCredentialAgent
        self.policyAttributes = policyAttributes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        // jscpd:ignore-end
    }

    private enum CodingKeys: String, CodingKey {
        case id, email, name, role, tags, metadata
        case orgId = "org_id"
        case externalUserId = "external_user_id"
        case imageUrl = "image_url"
        case memberType = "member_type"
        case isDeactivated = "is_deactivated"
        case applicationIdpId = "application_idp_id"
        case connectorId = "connector_id"
        case integrationId = "integration_id"
        case isExternalCredentialAgent = "is_external_credential_agent"
        case policyAttributes = "policy_attributes"
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
    /// Members whose metadata holds every pair as an exact value (at most 16 keys). Sent as repeated
    /// `metadata=key:value`.
    public var metadata: [String: String]?
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
        metadata: [String: String]? = nil, ids: [String]? = nil, externalUserIds: [String]? = nil, project: String? = nil,
        limit: Int? = nil, next: String? = nil
    ) {
        self.memberType = memberType
        self.connectorId = connectorId
        self.applicationIdpId = applicationIdpId
        self.tag = tag
        self.metadata = metadata
        self.ids = ids
        self.externalUserIds = externalUserIds
        self.project = project
        self.limit = limit
        self.next = next
    }
}

/// A business member invited by email.
public struct BusinessMemberCreate: Codable, Sendable, Hashable {
    public var email: String
    /// First and last name; the server rejects a single word.
    public var name: String
    /// `member` (server default), `admin` or `owner`.
    public var role: String?
    /// Access-bearing; setting any needs `members:manage`.
    public var tags: [String]?
    /// Keys are letters, digits, `_` and `-`; values non-empty strings; at most 64 entries.
    public var metadata: [String: String]?
    /// Attributes the recipe's Cedar policies read for this member.
    public var policyAttributes: JSONObject?

    public init(
        email: String, name: String, role: String? = nil, tags: [String]? = nil, metadata: [String: String]? = nil,
        policyAttributes: JSONObject? = nil
    ) {
        self.email = email
        self.name = name
        self.role = role
        self.tags = tags
        self.metadata = metadata
        self.policyAttributes = policyAttributes
    }

    private enum CodingKeys: String, CodingKey {
        case email, name, role, tags, metadata
        case policyAttributes = "policy_attributes"
    }
}

/// A customer member keyed by its external identity, so its attributes are ready before its first session.
public struct CustomerMemberCreate: Codable, Sendable, Hashable {
    /// `user:{id}` or `anon:{id}`.
    public var externalUserId: String
    public var name: String?
    public var email: String?
    public var tags: [String]?
    public var metadata: [String: String]?
    /// Attributes the recipe's Cedar policies read for this member.
    public var policyAttributes: JSONObject?

    public init(
        externalUserId: String, name: String? = nil, email: String? = nil, tags: [String]? = nil,
        metadata: [String: String]? = nil, policyAttributes: JSONObject? = nil
    ) {
        self.externalUserId = externalUserId
        self.name = name
        self.email = email
        self.tags = tags
        self.metadata = metadata
        self.policyAttributes = policyAttributes
    }

    private enum CodingKeys: String, CodingKey {
        case name, email, tags, metadata
        case externalUserId = "external_user_id"
        case policyAttributes = "policy_attributes"
    }
}

/// The body of `POST /v1/members`. Customers, tags and policy attributes need `members:manage`.
public enum MemberCreate: Codable, Sendable, Hashable {
    case business(BusinessMemberCreate)
    case customer(CustomerMemberCreate)

    private enum CodingKeys: String, CodingKey {
        case memberType = "member_type"
    }

    /// The server reads a missing `member_type` as `business`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decodeIfPresent(MemberType.self, forKey: .memberType) ?? .business {
        case .business: self = .business(try BusinessMemberCreate(from: decoder))
        case .customer: self = .customer(try CustomerMemberCreate(from: decoder))
        case let other:
            throw DecodingError.dataCorruptedError(
                forKey: .memberType, in: container, debugDescription: "member_type must be business or customer, got \(other.rawValue)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .business(body):
            try container.encode(MemberType.business, forKey: .memberType)
            try body.encode(to: encoder)
        case let .customer(body):
            try container.encode(MemberType.customer, forKey: .memberType)
            try body.encode(to: encoder)
        }
    }
}

/// The body of `PATCH /v1/members/{id}` (needs `members:manage`). A nil field is left untouched.
public struct MemberUpdate: Encodable, Sendable, Hashable {
    public var name: String?
    public var imageUrl: String?
    public var role: String?
    /// Replaces the tag list wholesale; `[]` clears it.
    public var tags: [String]?
    /// Replaces the metadata map wholesale; `[:]` clears it.
    public var metadata: [String: String]?
    /// Replaces the policy attributes wholesale; `[:]` clears them.
    public var policyAttributes: JSONObject?

    public init(
        name: String? = nil, imageUrl: String? = nil, role: String? = nil, tags: [String]? = nil, metadata: [String: String]? = nil,
        policyAttributes: JSONObject? = nil
    ) {
        self.name = name
        self.imageUrl = imageUrl
        self.role = role
        self.tags = tags
        self.metadata = metadata
        self.policyAttributes = policyAttributes
    }

    private enum CodingKeys: String, CodingKey {
        case name, role, tags, metadata
        case imageUrl = "image_url"
        case policyAttributes = "policy_attributes"
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

/// `/v1/members`.
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
        query.add("metadata", params.metadata.map { pairs in pairs.keys.sorted().compactMap { key in pairs[key].map { "\(key):\($0)" } } })
        query.add("id", params.ids)
        query.add("external_user_id", params.externalUserIds)
        query.add("limit", params.limit)
        return http.paginate("/v1/members", query: query, start: params.next)
    }

    /// Fetch one member.
    public func get(_ memberId: String, project: String? = nil) async throws -> Member {
        try await http.json("GET", "/v1/members/\(pathSegment(memberId))", query: cpProjectQuery(project))
    }

    /// Invite a business member (admin or owner only).
    public func create(_ body: MemberCreate) async throws -> Member {
        try await http.json("POST", "/v1/members", body: try .encode(body), as: Member.self)
    }

    /// Update a member.
    public func update(_ memberId: String, _ body: MemberUpdate) async throws -> Member {
        try await http.json("PATCH", "/v1/members/\(pathSegment(memberId))", body: try .encode(body), as: Member.self)
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
