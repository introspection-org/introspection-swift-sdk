import Foundation

/// A judge a Recipe declares. Its definition is authored in the Recipe; only `enabled` and `sampleRate` change
/// here.
public struct Judge: Codable, Sendable, Hashable {
    public var id: String
    public var orgId: String?
    public var projectId: String?
    public var runtimeGroupId: String?
    public var name: String?
    public var description: String?
    public var enabled: Bool?
    /// The fraction of conversations judged, `0.0` to `1.0`.
    public var sampleRate: Double?
    /// Where the definition came from (`recipe`).
    public var source: String?
    public var repositoryId: String?
    public var recipeGitCommitSha: String?
    public var sourcePath: String?
    public var definitionHash: String?
    public var createdByMemberId: String?
    public var createdAt: Date?
    public var updatedAt: Date?

    /// A value with only its id set; decoding fills the rest.
    public init(id: String) { self.id = id }

    private enum CodingKeys: String, CodingKey {
        case id, name, description, enabled, source
        case orgId = "org_id"
        case projectId = "project_id"
        case runtimeGroupId = "runtime_group_id"
        case sampleRate = "sample_rate"
        case repositoryId = "repository_id"
        case recipeGitCommitSha = "recipe_git_commit_sha"
        case sourcePath = "source_path"
        case definitionHash = "definition_hash"
        case createdByMemberId = "created_by_member_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Filters for `GET /v1/judges`.
public struct JudgeListParams: Sendable, Hashable {
    /// The project's slug or id, when the credential does not name one.
    public var project: String?
    public var runtimeGroupId: String?
    public var limit: Int?
    public var next: String?

    public init(project: String? = nil, runtimeGroupId: String? = nil, limit: Int? = nil, next: String? = nil) {
        self.project = project
        self.runtimeGroupId = runtimeGroupId
        self.limit = limit
        self.next = next
    }
}

/// Body of `PATCH /v1/judges/{id}`: a judge's operational state only.
public struct JudgeUpdate: Encodable, Sendable, Hashable {
    public var enabled: Bool?
    /// The fraction of conversations judged, `0.0` to `1.0`.
    public var sampleRate: Double?

    public init(enabled: Bool? = nil, sampleRate: Double? = nil) {
        self.enabled = enabled
        self.sampleRate = sampleRate
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case sampleRate = "sample_rate"
    }
}

/// The judges a project's Recipes declare (`/v1/judges`). A judge is published with its Recipe, so there is no
/// create or delete. Needs `judges:read` / `judges:write`.
public struct JudgesAPI: Sendable {
    let collection: ProjectScopedCollection

    public init(http: HTTPClient) { collection = ProjectScopedCollection(http: http, path: "/v1/judges") }

    /// List the project's judges.
    public func list(_ params: JudgeListParams = JudgeListParams()) -> Paginator<Judge> {
        var filters = Query()
        filters.add("runtime_group_id", params.runtimeGroupId)
        return collection.list(project: params.project, limit: params.limit, next: params.next, filters: filters)
    }

    /// Fetch one judge.
    public func get(_ judgeId: String, project: String? = nil) async throws -> Judge {
        try await collection.get(judgeId, project: project)
    }

    /// Turn a judge on or off, or change how often it runs.
    public func update(_ judgeId: String, _ body: JudgeUpdate, project: String? = nil) async throws -> Judge {
        try await collection.update(judgeId, body, project: project)
    }
}

extension IntrospectionClient {
    /// The judges the project's Recipes declare.
    public var judges: JudgesAPI { JudgesAPI(http: controlPlane) }
}
