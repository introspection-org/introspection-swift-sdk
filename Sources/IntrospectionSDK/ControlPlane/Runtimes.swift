import Foundation

// MARK: Models

/// How a runtime is delivered.
public struct RuntimeKind: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let byor: RuntimeKind = "byor"
    public static let byoh: RuntimeKind = "byoh"
    public static let platform: RuntimeKind = "platform"
}

/// How a runtime acquires LLM provider credentials: `managed` keys or the project's `byok` endpoints.
public struct RuntimeLlmMode: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let managed: RuntimeLlmMode = "managed"
    public static let byok: RuntimeLlmMode = "byok"
}

/// Image build lifecycle of a runtime version.
public struct RuntimeImageStatus: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let pending: RuntimeImageStatus = "pending"
    public static let queued: RuntimeImageStatus = "queued"
    public static let building: RuntimeImageStatus = "building"
    public static let ready: RuntimeImageStatus = "ready"
    public static let failed: RuntimeImageStatus = "failed"
}

/// Whether a runtime version was built from a preview or a production recipe ref.
public struct RuntimeRecipeKind: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let preview: RuntimeRecipeKind = "preview"
    public static let production: RuntimeRecipeKind = "production"
}

/// Optional read-time projections on `GET /v1/runtimes/{id}`.
public struct RuntimeInclude: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let mcpRequirements: RuntimeInclude = "mcp_requirements"
}

/// Metadata of a runtime's last image build.
public struct RuntimeImageBuildMetadata: Codable, Sendable, Hashable {
    public var imageTag: String?
    public var builtAt: Date?
    public var sizeBytes: Int?
    public var externalImageName: String?
    public var externalArtifacts: [String: String]?

    public init(imageTag: String? = nil, builtAt: Date? = nil, sizeBytes: Int? = nil, externalImageName: String? = nil, externalArtifacts: [String: String]? = nil) {
        self.imageTag = imageTag
        self.builtAt = builtAt
        self.sizeBytes = sizeBytes
        self.externalImageName = externalImageName
        self.externalArtifacts = externalArtifacts
    }

    private enum CodingKeys: String, CodingKey {
        case imageTag = "image_tag"
        case builtAt = "built_at"
        case sizeBytes = "size_bytes"
        case externalImageName = "external_image_name"
        case externalArtifacts = "external_artifacts"
    }
}

/// One recipe-declared MCP server requirement resolved for one environment.
public struct RuntimeMcpRequirement: Codable, Sendable, Hashable {
    public var slug: String?
    public var environment: RuntimeEnvironment?
    /// `ready`, `missing_connector`, `ambiguous_connector`, `authorization_required`, `missing_endpoint`, `conflicting_endpoint`, ...
    public var state: String?
    public var connectorId: String?
    public var connectorProvider: String?
    public var candidateConnectorIds: [String]?
    public var connectionId: String?
    public var connectionStatus: ConnectionStatus?
    public var mcpServerId: String?
    public var mcpRequired: Bool?
    public var endpointId: String?
    public var mcpServerUrl: String?
    public var mcpServerUrlSource: String?
    public var detail: String?

    public init(
        slug: String? = nil, environment: RuntimeEnvironment? = nil, state: String? = nil,
        connectorId: String? = nil, connectorProvider: String? = nil, candidateConnectorIds: [String]? = nil,
        connectionId: String? = nil, connectionStatus: ConnectionStatus? = nil, mcpServerId: String? = nil,
        mcpRequired: Bool? = nil, endpointId: String? = nil, mcpServerUrl: String? = nil,
        mcpServerUrlSource: String? = nil, detail: String? = nil
    ) {
        self.slug = slug
        self.environment = environment
        self.state = state
        self.connectorId = connectorId
        self.connectorProvider = connectorProvider
        self.candidateConnectorIds = candidateConnectorIds
        self.connectionId = connectionId
        self.connectionStatus = connectionStatus
        self.mcpServerId = mcpServerId
        self.mcpRequired = mcpRequired
        self.endpointId = endpointId
        self.mcpServerUrl = mcpServerUrl
        self.mcpServerUrlSource = mcpServerUrlSource
        self.detail = detail
    }

    private enum CodingKeys: String, CodingKey {
        case slug, environment, state, detail
        case connectorId = "connector_id"
        case connectorProvider = "connector_provider"
        case candidateConnectorIds = "candidate_connector_ids"
        case connectionId = "connection_id"
        case connectionStatus = "connection_status"
        case mcpServerId = "mcp_server_id"
        case mcpRequired = "mcp_required"
        case endpointId = "endpoint_id"
        case mcpServerUrl = "mcp_server_url"
        case mcpServerUrlSource = "mcp_server_url_source"
    }
}

/// One runtime version: a recipe pin inside a runtime group, served to one or more environments.
public struct Runtime: Codable, Sendable, Hashable {
    public var id: String
    public var orgId: String?
    public var projectId: String?
    public var runtimeGroupId: String?
    public var name: String?
    /// The runtime group slug, shared across versions.
    public var slug: String?
    public var description: String?
    public var kind: RuntimeKind?
    public var llmMode: RuntimeLlmMode?
    public var configJson: JSONObject?
    public var recipeId: String?
    public var recipeKind: RuntimeRecipeKind?
    public var recipeRef: String?
    /// Environments this version currently serves.
    public var environments: [RuntimeEnvironment]?
    public var imageBuildStatus: RuntimeImageStatus?
    public var imageBuildErrorMessage: String?
    public var imageBuildMetadata: RuntimeImageBuildMetadata?
    public var createdByMemberId: String?
    /// Set when this version was withdrawn; it never resolves as active again.
    public var yankedAt: Date?
    public var yankedReason: String?
    /// Git ref each environment tracks (`main`, `pr/N` or a sha); an absent key is untracked.
    public var environmentRef: [String: String]?
    /// Present only when requested with `include: [.mcpRequirements]`.
    public var mcpRequirements: [RuntimeMcpRequirement]?
    public var createdAt: Date?
    public var updatedAt: Date?

    public init(
        id: String, orgId: String? = nil, projectId: String? = nil, runtimeGroupId: String? = nil,
        name: String? = nil, slug: String? = nil, description: String? = nil, kind: RuntimeKind? = nil,
        llmMode: RuntimeLlmMode? = nil, configJson: JSONObject? = nil, recipeId: String? = nil,
        recipeKind: RuntimeRecipeKind? = nil, recipeRef: String? = nil, environments: [RuntimeEnvironment]? = nil,
        imageBuildStatus: RuntimeImageStatus? = nil, imageBuildErrorMessage: String? = nil,
        imageBuildMetadata: RuntimeImageBuildMetadata? = nil, createdByMemberId: String? = nil,
        yankedAt: Date? = nil, yankedReason: String? = nil, environmentRef: [String: String]? = nil,
        mcpRequirements: [RuntimeMcpRequirement]? = nil, createdAt: Date? = nil, updatedAt: Date? = nil
    ) {
        self.id = id
        self.orgId = orgId
        self.projectId = projectId
        self.runtimeGroupId = runtimeGroupId
        self.name = name
        self.slug = slug
        self.description = description
        self.kind = kind
        self.llmMode = llmMode
        self.configJson = configJson
        self.recipeId = recipeId
        self.recipeKind = recipeKind
        self.recipeRef = recipeRef
        self.environments = environments
        self.imageBuildStatus = imageBuildStatus
        self.imageBuildErrorMessage = imageBuildErrorMessage
        self.imageBuildMetadata = imageBuildMetadata
        self.createdByMemberId = createdByMemberId
        self.yankedAt = yankedAt
        self.yankedReason = yankedReason
        self.environmentRef = environmentRef
        self.mcpRequirements = mcpRequirements
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, slug, description, kind, environments
        case orgId = "org_id"
        case projectId = "project_id"
        case runtimeGroupId = "runtime_group_id"
        case llmMode = "llm_mode"
        case configJson = "config_json"
        case recipeId = "recipe_id"
        case recipeKind = "recipe_kind"
        case recipeRef = "recipe_ref"
        case imageBuildStatus = "image_build_status"
        case imageBuildErrorMessage = "image_build_error_message"
        case imageBuildMetadata = "image_build_metadata"
        case createdByMemberId = "created_by_member_id"
        case yankedAt = "yanked_at"
        case yankedReason = "yanked_reason"
        case environmentRef = "environment_ref"
        case mcpRequirements = "mcp_requirements"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Filters for `GET /v1/runtimes`, newest first.
public struct RuntimeListParams: Sendable, Hashable {
    /// Project slug or id; defaults to the credential's project.
    public var project: String?
    /// Runtime group slug or id.
    public var runtime: String?
    public var recipeId: String?
    /// Only versions serving this environment. An API key already selects one, so passing both is a 400.
    public var environment: RuntimeEnvironment?
    /// Page size (1 to 1000).
    public var limit: Int?
    /// Starting cursor.
    public var next: String?

    public init(
        project: String? = nil,
        runtime: String? = nil,
        recipeId: String? = nil,
        environment: RuntimeEnvironment? = nil,
        limit: Int? = nil,
        next: String? = nil
    ) {
        self.project = project
        self.runtime = runtime
        self.recipeId = recipeId
        self.environment = environment
        self.limit = limit
        self.next = next
    }
}

// MARK: API

/// Read and resolve `/v1/runtimes` and open runners. Runtime lifecycle is managed by the CLI and platform.
///
/// ```swift
/// let runner = try await client.runtimes("customer-agent").run(RunRequest(identity: .init(userId: "u_42")))
/// ```
public struct RuntimesAPI: Sendable {
    let client: IntrospectionClient

    public init(client: IntrospectionClient) { self.client = client }

    private var http: HTTPClient { client.controlPlane }

    /// List runtime versions matching `params`, newest first.
    public func list(_ params: RuntimeListParams = RuntimeListParams()) -> Paginator<Runtime> {
        var query = Query()
        query.add("project", params.project)
        query.add("runtime", params.runtime)
        query.add("recipe_id", params.recipeId)
        query.add("environment", params.environment)
        query.add("limit", params.limit)
        return http.paginate("/v1/runtimes", query: query, start: params.next)
    }

    /// Fetch one runtime version.
    public func get(_ id: String, project: String? = nil, include: [RuntimeInclude]? = nil) async throws -> Runtime {
        var query = Query()
        query.add("project", project)
        query.add("include", include)
        return try await http.json("GET", "/v1/runtimes/\(pathSegment(id))", query: query)
    }

    /// Resolve a runtime group slug or id to the version it currently serves.
    public func resolve(_ runtime: String, project: String? = nil) async throws -> Runtime {
        // The route answers newest first, so one row is the version the group serves now.
        let page = try await list(RuntimeListParams(project: project, runtime: runtime, limit: 1)).firstPage()
        if let match = page.records.first { return match }
        let scope = project.map { " in project \($0)" } ?? ""
        throw IntrospectionError(kind: .notFound, message: "Runtime '\(runtime)' not found\(scope)", status: 404, code: "not_found")
    }

    /// `POST /v1/runtimes/{id}/run`: mint a runner session spec without wrapping it.
    public func openRunner(_ id: String, _ request: RunRequest = RunRequest(), project: String? = nil) async throws -> RunnerSpec {
        var query = Query()
        query.add("project", project)
        return try await http.json("POST", "/v1/runtimes/\(pathSegment(id))/run", query: query, body: .encode(request))
    }

    /// Open a runner on a runtime version id.
    public func run(_ id: String, _ request: RunRequest = RunRequest(), project: String? = nil) async throws -> Runner {
        let spec = try await openRunner(id, request, project: project)
        return try Runner(
            spec: spec,
            template: client.dataPlane,
            controlPlane: http,
            source: .runtime(id: id, request: request, project: project)
        )
    }

    /// A handle on a runtime group slug or id that resolves it on every `run()`.
    public func callAsFunction(_ runtime: String, project: String? = nil) -> RuntimeHandle {
        RuntimeHandle(api: self, runtime: runtime, project: project)
    }
}

/// A runtime group selector (slug or id). Each `run()` resolves it again, so a
/// long-lived handle always reaches the version the group serves now rather
/// than one that has since been yanked.
public struct RuntimeHandle: Sendable {
    let api: RuntimesAPI
    /// The runtime group slug or id.
    public let runtime: String
    public let project: String?

    public init(api: RuntimesAPI, runtime: String, project: String? = nil) {
        self.api = api
        self.runtime = runtime
        self.project = project
    }

    /// Resolve the runtime and open a runner on it.
    public func run(_ request: RunRequest = RunRequest()) async throws -> Runner {
        let resolved = try await api.resolve(runtime, project: project)
        return try await api.run(resolved.id, request, project: project)
    }

    /// Resolve the runtime version the group currently serves.
    public func resolve() async throws -> Runtime {
        try await api.resolve(runtime, project: project)
    }
}

extension IntrospectionClient {
    /// Runtimes: list, resolve and run. Call it as `client.runtimes("slug")` for a handle.
    public var runtimes: RuntimesAPI { RuntimesAPI(client: self) }

    /// A handle on a runtime group slug or id that resolves it on every `run()`.
    public func runtime(_ runtime: String, project: String? = nil) -> RuntimeHandle {
        RuntimeHandle(api: runtimes, runtime: runtime, project: project)
    }
}
