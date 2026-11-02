import Foundation

// MARK: Models

/// An endpoint's role.
public struct EndpointKind: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    /// A model provider; counts toward a BYOK runtime's endpoints.
    public static let llm: EndpointKind = "llm"
    /// A plain upstream HTTP API.
    public static let api: EndpointKind = "api"
    /// An MCP server over streamable HTTP.
    public static let mcp: EndpointKind = "mcp"
}

/// An endpoint's non-secret metadata, carried into the session bootstrap.
public struct EndpointMetadata: Codable, Sendable, Hashable {
    /// The logical MCP server id (`kind: .mcp` only).
    public var mcpServerId: String?
    /// The connector whose connection authenticates this MCP endpoint.
    public var connectorId: String?
    /// The app this binding wants, where the connector's provider fronts many behind one host.
    public var providerApp: String?
    /// Hosts reached with nothing injected, for URLs that carry their own credential.
    public var extraHosts: [String]?
    /// The stable application-auth audience of a logical MCP server.
    public var authAudience: String?

    public init(
        mcpServerId: String? = nil, connectorId: String? = nil, providerApp: String? = nil, extraHosts: [String]? = nil,
        authAudience: String? = nil
    ) {
        self.mcpServerId = mcpServerId
        self.connectorId = connectorId
        self.providerApp = providerApp
        self.extraHosts = extraHosts
        self.authAudience = authAudience
    }

    private enum CodingKeys: String, CodingKey {
        case mcpServerId = "mcp_server_id"
        case connectorId = "connector_id"
        case providerApp = "provider_app"
        case extraHosts = "extra_hosts"
        case authAudience = "auth_audience"
    }
}

/// Where an MCP endpoint's tool discovery stands.
public struct McpCheckStatus: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let pending: McpCheckStatus = "pending"
    public static let ok: McpCheckStatus = "ok"
    public static let failed: McpCheckStatus = "failed"
    public static let skipped: McpCheckStatus = "skipped"
}

/// The latest tool discovery of an MCP endpoint.
public struct EndpointMcpCheck: Codable, Sendable, Hashable {
    public var checkId: String
    public var status: McpCheckStatus
    public var requestedAt: Date
    public var requestedByMemberId: String?
    public var checkedAt: Date?
    public var serverName: String?
    public var tools: [String]?
    public var errorMessage: String?

    private enum CodingKeys: String, CodingKey {
        case status, tools
        case checkId = "check_id"
        case requestedAt = "requested_at"
        case requestedByMemberId = "requested_by_member_id"
        case checkedAt = "checked_at"
        case serverName = "server_name"
        case errorMessage = "error_message"
    }
}

/// A project's egress endpoint: an upstream host the sandbox may call, with the headers injected on the way out.
/// Header values carry credential references (`${NAME}`) unresolved; secrets never appear here.
public struct Endpoint: Codable, Sendable, Hashable {
    public var id: String
    public var orgId: String?
    public var projectId: String?
    public var name: String?
    public var host: String?
    public var baseUrl: String?
    public var kind: EndpointKind?
    public var metadata: EndpointMetadata?
    public var headers: [String: String]?
    public var headerNames: [String]?
    /// Credential names the header values reference.
    public var credentialRefs: [String]?
    /// Extra claims merged into the endpoint's identity assertions.
    public var assertionClaims: [String: String]?
    /// The application that signs this endpoint's identity assertions.
    public var authorizedApplicationId: String?
    /// Scope: nil for every runtime in the project.
    public var runtimeId: String?
    public var runtimeGroupId: String?
    public var environment: RuntimeEnvironment?
    public var verifyPath: String?
    public var lastVerifiedAt: Date?
    public var createdByMemberId: String?
    public var createdAt: Date?
    public var updatedAt: Date?
    /// The latest tool discovery, on an MCP endpoint that has had one.
    public var mcpCheck: EndpointMcpCheck?

    public init(
        id: String, orgId: String? = nil, projectId: String? = nil, name: String? = nil, host: String? = nil, baseUrl: String? = nil,
        kind: EndpointKind? = nil, metadata: EndpointMetadata? = nil, headers: [String: String]? = nil, headerNames: [String]? = nil,
        credentialRefs: [String]? = nil, assertionClaims: [String: String]? = nil, authorizedApplicationId: String? = nil,
        runtimeId: String? = nil, runtimeGroupId: String? = nil, environment: RuntimeEnvironment? = nil, verifyPath: String? = nil,
        lastVerifiedAt: Date? = nil, createdByMemberId: String? = nil, createdAt: Date? = nil, updatedAt: Date? = nil
    ) {
        // jscpd:ignore-start: memberwise init of a public type; the assignments cannot be shared
        self.id = id
        self.orgId = orgId
        self.projectId = projectId
        self.name = name
        self.host = host
        self.baseUrl = baseUrl
        self.kind = kind
        self.metadata = metadata
        self.headers = headers
        self.headerNames = headerNames
        self.credentialRefs = credentialRefs
        self.assertionClaims = assertionClaims
        self.authorizedApplicationId = authorizedApplicationId
        self.runtimeId = runtimeId
        self.runtimeGroupId = runtimeGroupId
        self.environment = environment
        self.verifyPath = verifyPath
        self.lastVerifiedAt = lastVerifiedAt
        self.createdByMemberId = createdByMemberId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        // jscpd:ignore-end
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, host, kind, metadata, headers, environment
        case orgId = "org_id"
        case projectId = "project_id"
        case baseUrl = "base_url"
        case headerNames = "header_names"
        case credentialRefs = "credential_refs"
        case assertionClaims = "assertion_claims"
        case authorizedApplicationId = "authorized_application_id"
        case runtimeId = "runtime_id"
        case runtimeGroupId = "runtime_group_id"
        case verifyPath = "verify_path"
        case lastVerifiedAt = "last_verified_at"
        case createdByMemberId = "created_by_member_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case mcpCheck = "mcp_check"
    }
}

/// The body of `POST /v1/endpoints`. Header values may reference credentials as `${NAME}`. With a `verifyPath` the
/// Control Plane calls the upstream first, and refuses the endpoint if the check fails.
public struct EndpointCreate: Encodable, Sendable, Hashable {
    /// Display label, not unique.
    public var name: String
    /// Hostname: no scheme, path or port.
    public var host: String
    public var headers: [String: String]
    /// Defaults to ``EndpointKind/llm``.
    public var kind: EndpointKind?
    public var baseUrl: String?
    public var metadata: EndpointMetadata?
    public var assertionClaims: [String: String]?
    public var runtimeId: String?
    public var runtimeGroupId: String?
    public var environment: RuntimeEnvironment?
    public var verifyPath: String?
    public var authorizedApplicationId: String?

    // jscpd:ignore-start: memberwise init and CodingKeys of a public type; EndpointUpdate has the same fields, all optional
    public init(
        name: String, host: String, headers: [String: String] = [:], kind: EndpointKind? = nil, baseUrl: String? = nil,
        metadata: EndpointMetadata? = nil, assertionClaims: [String: String]? = nil, runtimeId: String? = nil,
        runtimeGroupId: String? = nil, environment: RuntimeEnvironment? = nil, verifyPath: String? = nil,
        authorizedApplicationId: String? = nil
    ) {
        self.name = name
        self.host = host
        self.headers = headers
        self.kind = kind
        self.baseUrl = baseUrl
        self.metadata = metadata
        self.assertionClaims = assertionClaims
        self.runtimeId = runtimeId
        self.runtimeGroupId = runtimeGroupId
        self.environment = environment
        self.verifyPath = verifyPath
        self.authorizedApplicationId = authorizedApplicationId
    }

    private enum CodingKeys: String, CodingKey {
        case name, host, headers, kind, metadata, environment
        case baseUrl = "base_url"
        case assertionClaims = "assertion_claims"
        case runtimeId = "runtime_id"
        case runtimeGroupId = "runtime_group_id"
        case verifyPath = "verify_path"
        case authorizedApplicationId = "authorized_application_id"
    }
    // jscpd:ignore-end
}

/// The body of `PATCH /v1/endpoints/{id}`. Changing the host, base URL, headers or verify path of an endpoint
/// with a verify path re-runs its pre-flight check, which must pass.
public struct EndpointUpdate: Encodable, Sendable, Hashable {
    public var name: String?
    public var host: String?
    public var baseUrl: String?
    public var headers: [String: String]?
    public var kind: EndpointKind?
    public var metadata: EndpointMetadata?
    public var assertionClaims: [String: String]?
    public var runtimeId: String?
    public var runtimeGroupId: String?
    public var environment: RuntimeEnvironment?
    public var verifyPath: String?
    /// Linking cannot be cleared: omit it to leave it unchanged.
    public var authorizedApplicationId: String?

    public init(
        name: String? = nil, host: String? = nil, baseUrl: String? = nil, headers: [String: String]? = nil, kind: EndpointKind? = nil,
        metadata: EndpointMetadata? = nil, assertionClaims: [String: String]? = nil, runtimeId: String? = nil,
        runtimeGroupId: String? = nil, environment: RuntimeEnvironment? = nil, verifyPath: String? = nil,
        authorizedApplicationId: String? = nil
    ) {
        self.name = name
        self.host = host
        self.baseUrl = baseUrl
        self.headers = headers
        self.kind = kind
        self.metadata = metadata
        self.assertionClaims = assertionClaims
        self.runtimeId = runtimeId
        self.runtimeGroupId = runtimeGroupId
        self.environment = environment
        self.verifyPath = verifyPath
        self.authorizedApplicationId = authorizedApplicationId
    }

    private enum CodingKeys: String, CodingKey {
        case name, host, headers, kind, metadata, environment
        case baseUrl = "base_url"
        case assertionClaims = "assertion_claims"
        case runtimeId = "runtime_id"
        case runtimeGroupId = "runtime_group_id"
        case verifyPath = "verify_path"
        case authorizedApplicationId = "authorized_application_id"
    }
}

/// Filters for `GET /v1/endpoints`.
public struct EndpointListParams: Sendable, Hashable {
    /// Project slug or id; defaults to the credential's project.
    public var project: String?
    public var kind: EndpointKind?
    /// Only endpoints pinned to this runtime version.
    public var runtimeId: String?
    /// Only endpoints pinned to this runtime group, by slug or id.
    public var runtime: String?
    public var environment: RuntimeEnvironment?
    public var mcpServerId: String?
    public var limit: Int?
    public var next: String?

    // jscpd:ignore-start: memberwise init of a public type; the assignments cannot be shared
    public init(
        project: String? = nil, kind: EndpointKind? = nil, runtimeId: String? = nil, runtime: String? = nil,
        environment: RuntimeEnvironment? = nil, mcpServerId: String? = nil, limit: Int? = nil, next: String? = nil
    ) {
        self.project = project
        self.kind = kind
        self.runtimeId = runtimeId
        self.runtime = runtime
        self.environment = environment
        self.mcpServerId = mcpServerId
        self.limit = limit
        self.next = next
    }
    // jscpd:ignore-end
}

// MARK: API

/// `/v1/endpoints`: a project's egress endpoints. A connector grant binds its MCP endpoint itself.
public struct EndpointsAPI: Sendable {
    let collection: ProjectScopedCollection

    public init(http: HTTPClient) { collection = ProjectScopedCollection(http: http, path: "/v1/endpoints") }

    /// List endpoints matching `params`.
    public func list(_ params: EndpointListParams = EndpointListParams()) -> Paginator<Endpoint> {
        var filters = Query()
        filters.add("kind", params.kind)
        filters.add("runtime_id", params.runtimeId)
        filters.add("runtime", params.runtime)
        filters.add("environment", params.environment)
        filters.add("mcp_server_id", params.mcpServerId)
        return collection.list(project: params.project, limit: params.limit, next: params.next, filters: filters)
    }

    /// Fetch one endpoint.
    public func get(_ id: String, project: String? = nil) async throws -> Endpoint {
        try await collection.get(id, project: project)
    }

    /// Create an endpoint.
    public func create(_ body: EndpointCreate, project: String? = nil) async throws -> Endpoint {
        try await collection.create(body, project: project)
    }

    /// Update an endpoint.
    public func update(_ id: String, _ body: EndpointUpdate, project: String? = nil) async throws -> Endpoint {
        try await collection.update(id, body, project: project)
    }

    /// Soft-delete an endpoint; a new one may then take its host and scope.
    public func delete(_ id: String, project: String? = nil) async throws {
        try await collection.delete(id, project: project)
    }
}

extension IntrospectionClient {
    /// A project's egress endpoints.
    public var endpoints: EndpointsAPI { EndpointsAPI(http: controlPlane) }
}
