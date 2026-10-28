import Foundation

/// A project offering one of its runtime groups' configuration to another project. Read-only here: granting,
/// changing or revoking a peering is a person's act in the web app (`runtime_peerings:write`), which no API key holds.
public struct RuntimePeering: Codable, Sendable, Hashable {
    public var id: String
    public var orgId: String?
    /// The source project offering the runtime group.
    public var projectId: String?
    public var runtimeGroupId: String?
    public var grantedOrgId: String?
    /// The project admitted; nil when the grant names an organization or deployment instead.
    public var grantedProjectId: String?
    public var grantedDeploymentId: String?
    /// Nil when the peering never expires.
    public var expiresAt: Date?
    public var createdByMemberId: String?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var deletedAt: Date?

    /// A value with only its id set; decoding fills the rest.
    public init(id: String) { self.id = id }

    private enum CodingKeys: String, CodingKey {
        case id
        case orgId = "org_id"
        case projectId = "project_id"
        case runtimeGroupId = "runtime_group_id"
        case grantedOrgId = "granted_org_id"
        case grantedProjectId = "granted_project_id"
        case grantedDeploymentId = "granted_deployment_id"
        case expiresAt = "expires_at"
        case createdByMemberId = "created_by_member_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

extension ProjectsAPI {
    /// List the peerings a project offers, by project slug or id, optionally narrowed to one runtime group (slug or
    /// id). With `granted: true` it lists the peerings other projects grant to this one instead; the server refuses
    /// `granted` combined with `runtime`. Needs `runtime_peerings:read`.
    public func peerings(
        _ project: String, runtime: String? = nil, granted: Bool = false, limit: Int? = nil, next: String? = nil
    ) -> Paginator<RuntimePeering> {
        var query = Query()
        query.add("runtime", runtime)
        if granted { query.add("granted", true) }
        query.add("limit", limit)
        return http.paginate("/v1/projects/\(pathSegment(project))/peerings", query: query, start: next)
    }

    /// Fetch one peering the project offers or one that admits it; any other id is not found.
    public func peering(_ project: String, _ peeringId: String) async throws -> RuntimePeering {
        try await http.json("GET", "/v1/projects/\(pathSegment(project))/peerings/\(pathSegment(peeringId))")
    }
}
