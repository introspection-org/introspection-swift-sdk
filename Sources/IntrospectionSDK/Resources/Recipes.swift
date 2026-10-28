import Foundation

/// Validation verdict of a recipe pin.
public struct RecipeValidationStatus: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let pending: RecipeValidationStatus = "pending"
    public static let valid: RecipeValidationStatus = "valid"
    public static let invalid: RecipeValidationStatus = "invalid"
    public static let failed: RecipeValidationStatus = "failed"
}

/// One validation finding, located in the recipe source.
public struct RecipeValidationDiagnostic: Codable, Sendable, Hashable {
    public struct Span: Codable, Sendable, Hashable {
        public var line: Int
        public var column: Int

        public init(line: Int, column: Int) {
            self.line = line
            self.column = column
        }
    }

    public var code: String?
    public var path: String?
    public var span: Span?
    public var message: String?
    public var help: String?

    public init(code: String? = nil, path: String? = nil, span: Span? = nil, message: String? = nil, help: String? = nil) {
        self.code = code
        self.path = path
        self.span = span
        self.message = message
        self.help = help
    }
}

/// The validation state of a recipe pin.
public struct RecipeValidation: Codable, Sendable, Hashable {
    public var status: RecipeValidationStatus?
    public var validatorName: String?
    public var validatorVersion: String?
    public var checkedAt: Date?
    public var errorMessage: String?
    public var diagnostics: [RecipeValidationDiagnostic]?

    public init(
        status: RecipeValidationStatus? = nil, validatorName: String? = nil, validatorVersion: String? = nil,
        checkedAt: Date? = nil, errorMessage: String? = nil, diagnostics: [RecipeValidationDiagnostic]? = nil
    ) {
        self.status = status
        self.validatorName = validatorName
        self.validatorVersion = validatorVersion
        self.checkedAt = checkedAt
        self.errorMessage = errorMessage
        self.diagnostics = diagnostics
    }

    private enum CodingKeys: String, CodingKey {
        case status, diagnostics
        case validatorName = "validator_name"
        case validatorVersion = "validator_version"
        case checkedAt = "checked_at"
        case errorMessage = "error_message"
    }
}

/// An MCP server a recipe declares.
public struct RecipeMcpServer: Codable, Sendable, Hashable {
    public struct Tools: Codable, Sendable, Hashable {
        public var include: [String]?
        public var exclude: [String]?

        public init(include: [String]? = nil, exclude: [String]? = nil) {
            self.include = include
            self.exclude = exclude
        }
    }

    public var id: String
    public var required: Bool?
    public var tools: Tools?

    public init(id: String, required: Bool? = nil, tools: Tools? = nil) {
        self.id = id
        self.required = required
        self.tools = tools
    }
}

/// An immutable recipe pin: repository, git ref, commit sha and optional sub-path.
public struct Recipe: Codable, Sendable, Hashable {
    public var id: String
    public var orgId: String?
    public var projectId: String?
    public var repositoryId: String?
    /// Operator label, shared across versions.
    public var name: String?
    public var slug: String?
    public var description: String?
    public var gitRef: String?
    public var gitCommitSha: String?
    public var gitCommitSubject: String?
    public var subPath: String?
    public var mcpServers: [RecipeMcpServer]?
    public var validation: RecipeValidation?
    public var createdByMemberId: String?
    public var createdAt: Date?
    public var updatedAt: Date?

    public init(
        id: String, orgId: String? = nil, projectId: String? = nil, repositoryId: String? = nil, name: String? = nil,
        slug: String? = nil, description: String? = nil, gitRef: String? = nil, gitCommitSha: String? = nil,
        gitCommitSubject: String? = nil, subPath: String? = nil, mcpServers: [RecipeMcpServer]? = nil,
        validation: RecipeValidation? = nil, createdByMemberId: String? = nil, createdAt: Date? = nil, updatedAt: Date? = nil
    ) {
        self.id = id
        self.orgId = orgId
        self.projectId = projectId
        self.repositoryId = repositoryId
        self.name = name
        self.slug = slug
        self.description = description
        self.gitRef = gitRef
        self.gitCommitSha = gitCommitSha
        self.gitCommitSubject = gitCommitSubject
        self.subPath = subPath
        self.mcpServers = mcpServers
        self.validation = validation
        self.createdByMemberId = createdByMemberId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, slug, description, validation
        case orgId = "org_id"
        case projectId = "project_id"
        case repositoryId = "repository_id"
        case gitRef = "git_ref"
        case gitCommitSha = "git_commit_sha"
        case gitCommitSubject = "git_commit_subject"
        case subPath = "sub_path"
        case mcpServers = "mcp_servers"
        case createdByMemberId = "created_by_member_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Filters for `GET /v1/recipes`.
public struct RecipeListParams: Sendable, Hashable {
    public var project: String?
    /// Recipe name (groups versions across commits).
    public var name: String?
    public var repositoryId: String?
    public var limit: Int?
    public var next: String?

    public init(project: String? = nil, name: String? = nil, repositoryId: String? = nil, limit: Int? = nil, next: String? = nil) {
        self.project = project
        self.name = name
        self.repositoryId = repositoryId
        self.limit = limit
        self.next = next
    }
}

/// The body of `POST /v1/recipes`: a pin of one commit of a project's repository.
public struct RecipeCreate: Encodable, Sendable, Hashable {
    /// The operator's label, shared across the recipe's versions.
    public var name: String
    /// The project slug or id the recipe belongs to.
    public var project: String
    public var repositoryId: String?
    /// The branch, tag or short sha the operator picked.
    public var gitRef: String?
    /// The 40-hex commit the recipe pins.
    public var gitCommitSha: String?
    public var subPath: String?
    /// Derived from `name` and the short sha when omitted.
    public var slug: String?
    public var description: String?

    public init(
        name: String, project: String, repositoryId: String? = nil, gitRef: String? = nil, gitCommitSha: String? = nil,
        subPath: String? = nil, slug: String? = nil, description: String? = nil
    ) {
        self.name = name
        self.project = project
        self.repositoryId = repositoryId
        self.gitRef = gitRef
        self.gitCommitSha = gitCommitSha
        self.subPath = subPath
        self.slug = slug
        self.description = description
    }

    private enum CodingKeys: String, CodingKey {
        case name, project, slug, description
        case repositoryId = "repository_id"
        case gitRef = "git_ref"
        case gitCommitSha = "git_commit_sha"
        case subPath = "sub_path"
    }
}

/// The body of `PATCH /v1/recipes/{id}`. The Git pin is immutable: other content is a new recipe.
public struct RecipeUpdate: Encodable, Sendable, Hashable {
    public var name: String?
    public var description: String?

    public init(name: String? = nil, description: String? = nil) {
        self.name = name
        self.description = description
    }
}

/// `/v1/recipes`: the immutable pins runtimes and experiment arms reference.
public struct RecipesAPI: Sendable {
    let http: HTTPClient

    public init(http: HTTPClient) { self.http = http }

    /// List recipes matching `params`.
    public func list(_ params: RecipeListParams = RecipeListParams()) -> Paginator<Recipe> {
        var query = Query()
        query.add("project", params.project)
        query.add("name", params.name)
        query.add("repository_id", params.repositoryId)
        query.add("limit", params.limit)
        return http.paginate("/v1/recipes", query: query, start: params.next)
    }

    /// Fetch one recipe.
    public func get(_ id: String, project: String? = nil) async throws -> Recipe {
        var query = Query()
        query.add("project", project)
        return try await http.json("GET", "/v1/recipes/\(pathSegment(id))", query: query)
    }

    /// Pin a commit. Idempotent: the same repository, name, commit and sub-path return the existing recipe.
    public func create(_ body: RecipeCreate) async throws -> Recipe {
        try await http.json("POST", "/v1/recipes", body: .encode(body))
    }

    /// Update a recipe's name or description.
    public func update(_ id: String, _ body: RecipeUpdate, project: String? = nil) async throws -> Recipe {
        try await http.json("PATCH", "/v1/recipes/\(pathSegment(id))", query: cpProjectQuery(project), body: .encode(body))
    }

    /// Soft-delete a recipe. Runtimes keep referencing it, but no task can start on it any more.
    public func delete(_ id: String, project: String? = nil) async throws {
        try await http.empty("DELETE", "/v1/recipes/\(pathSegment(id))", query: cpProjectQuery(project))
    }
}

extension IntrospectionClient {
    /// Recipes: the immutable pins runtimes and experiment arms reference.
    public var recipes: RecipesAPI { RecipesAPI(http: controlPlane) }
}
