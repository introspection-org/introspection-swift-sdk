import Foundation

// MARK: Models

/// A Git repository linked to a project: the source a recipe pins.
public struct Repository: Codable, Sendable, Hashable {
    public var id: String
    public var projectId: String?
    /// GitHub App installation reaching a `github` repository; nil when hosted.
    public var integrationId: String?
    /// Credential-free Git transport URL.
    public var url: String?
    public var name: String?
    /// `owner/repo` for GitHub, the hosted slug otherwise.
    public var slug: String?
    /// `github` or `hosted`.
    public var provider: String?
    public var defaultBranch: String?
    public var provisioningStatus: String?
    public var seedTemplate: String?
    public var createdAt: Date?
    public var pushedAt: Date?
    public var headCommitSha: String?
    public var isRecipeSource: Bool?

    public init(
        id: String, projectId: String? = nil, integrationId: String? = nil, url: String? = nil, name: String? = nil,
        slug: String? = nil, provider: String? = nil, defaultBranch: String? = nil, provisioningStatus: String? = nil,
        seedTemplate: String? = nil, createdAt: Date? = nil, pushedAt: Date? = nil, headCommitSha: String? = nil,
        isRecipeSource: Bool? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.integrationId = integrationId
        self.url = url
        self.name = name
        self.slug = slug
        self.provider = provider
        self.defaultBranch = defaultBranch
        self.provisioningStatus = provisioningStatus
        self.seedTemplate = seedTemplate
        self.createdAt = createdAt
        self.pushedAt = pushedAt
        self.headCommitSha = headCommitSha
        self.isRecipeSource = isRecipeSource
    }

    private enum CodingKeys: String, CodingKey {
        case id, url, name, slug, provider
        case projectId = "project_id"
        case integrationId = "integration_id"
        case defaultBranch = "default_branch"
        case provisioningStatus = "provisioning_status"
        case seedTemplate = "seed_template"
        case createdAt = "created_at"
        case pushedAt = "pushed_at"
        case headCommitSha = "head_commit_sha"
        case isRecipeSource = "is_recipe_source"
    }
}

/// Kind of a directory entry.
public struct RepositoryEntryType: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let file: RepositoryEntryType = "file"
    public static let dir: RepositoryEntryType = "dir"
    public static let symlink: RepositoryEntryType = "symlink"
    public static let submodule: RepositoryEntryType = "submodule"
}

/// One entry of a directory listing.
public struct RepositoryEntry: Codable, Sendable, Hashable {
    public var name: String
    public var path: String
    public var type: RepositoryEntryType
    public var size: Int?
    public var sha: String?

    public init(name: String, path: String, type: RepositoryEntryType, size: Int? = nil, sha: String? = nil) {
        self.name = name
        self.path = path
        self.type = type
        self.size = size
        self.sha = sha
    }
}

/// One page of a directory listing, read at `commitSha`.
public struct RepositoryDirectory: Codable, Sendable, Hashable {
    public var path: String
    /// What `ref` resolved to; every page of the listing is read at it.
    public var commitSha: String?
    public var records: [RepositoryEntry]
    public var count: Int?
    /// Cursor for the next page; nil when exhausted.
    public var next: String?

    public init(path: String, commitSha: String? = nil, records: [RepositoryEntry], count: Int? = nil, next: String? = nil) {
        self.path = path
        self.commitSha = commitSha
        self.records = records
        self.count = count
        self.next = next
    }

    private enum CodingKeys: String, CodingKey {
        case path, records, count, next
        case commitSha = "commit_sha"
    }
}

/// A file read. `content` is UTF-8 text or base64 per `encoding`, and empty when `truncated`.
public struct RepositoryFile: Codable, Sendable, Hashable {
    public var name: String
    public var path: String
    public var size: Int?
    public var sha: String?
    public var commitSha: String?
    /// `utf-8` or `base64`.
    public var encoding: String
    public var content: String
    /// The file is larger than a read returns.
    public var truncated: Bool?

    public init(
        name: String, path: String, size: Int? = nil, sha: String? = nil, commitSha: String? = nil, encoding: String, content: String,
        truncated: Bool? = nil
    ) {
        self.name = name
        self.path = path
        self.size = size
        self.sha = sha
        self.commitSha = commitSha
        self.encoding = encoding
        self.content = content
        self.truncated = truncated
    }

    /// The decoded bytes, or nil when truncated or not decodable.
    public var data: Data? {
        if truncated == true { return nil }
        return encoding == "base64" ? Data(base64Encoded: content) : Data(content.utf8)
    }

    /// The content as text, or nil when it is not valid UTF-8 or was truncated.
    public var text: String? {
        if encoding != "base64" { return truncated == true ? nil : content }
        return data.flatMap { String(data: $0, encoding: .utf8) }
    }

    private enum CodingKeys: String, CodingKey {
        case name, path, size, sha, encoding, content, truncated
        case commitSha = "commit_sha"
    }
}

/// A contents read: a directory page or a file, discriminated on `type`.
public enum RepositoryContent: Codable, Sendable, Hashable {
    case directory(RepositoryDirectory)
    case file(RepositoryFile)

    private enum CodingKeys: String, CodingKey { case type }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decodeIfPresent(String.self, forKey: .type)
        if type == "dir" {
            self = .directory(try RepositoryDirectory(from: decoder))
        } else {
            self = .file(try RepositoryFile(from: decoder))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .directory(directory):
            try container.encode("dir", forKey: .type)
            try directory.encode(to: encoder)
        case let .file(file):
            try container.encode("file", forKey: .type)
            try file.encode(to: encoder)
        }
    }

    /// The path this read answered for.
    public var path: String {
        switch self {
        case let .directory(directory): return directory.path
        case let .file(file): return file.path
        }
    }
}

/// The author or committer of a commit.
public struct RepositoryCommitPerson: Codable, Sendable, Hashable {
    public var name: String?
    public var email: String?
    public var date: String?

    public init(name: String? = nil, email: String? = nil, date: String? = nil) {
        self.name = name
        self.email = email
        self.date = date
    }
}

/// One commit in a repository's history.
public struct RepositoryCommit: Codable, Sendable, Hashable {
    public var sha: String
    public var parents: [String]?
    public var message: String?
    public var author: RepositoryCommitPerson?
    public var committer: RepositoryCommitPerson?

    public init(
        sha: String, parents: [String]? = nil, message: String? = nil, author: RepositoryCommitPerson? = nil,
        committer: RepositoryCommitPerson? = nil
    ) {
        self.sha = sha
        self.parents = parents
        self.message = message
        self.author = author
        self.committer = committer
    }
}

/// A file a commit changed.
public struct RepositoryCommitFile: Codable, Sendable, Hashable {
    public var filename: String
    /// `added`, `removed`, `modified` or `renamed`.
    public var status: String?
    public var additions: Int?
    public var deletions: Int?
    public var changes: Int?

    public init(filename: String, status: String? = nil, additions: Int? = nil, deletions: Int? = nil, changes: Int? = nil) {
        self.filename = filename
        self.status = status
        self.additions = additions
        self.deletions = deletions
        self.changes = changes
    }
}

/// One commit with the files it changed and its unified diff.
public struct RepositoryCommitDetail: Codable, Sendable, Hashable {
    public var sha: String
    public var parents: [String]?
    public var message: String?
    public var author: RepositoryCommitPerson?
    public var committer: RepositoryCommitPerson?
    public var files: [RepositoryCommitFile]?
    /// The whole commit as a unified git diff.
    public var patch: String?

    public init(
        sha: String, parents: [String]? = nil, message: String? = nil, author: RepositoryCommitPerson? = nil,
        committer: RepositoryCommitPerson? = nil, files: [RepositoryCommitFile]? = nil, patch: String? = nil
    ) {
        self.sha = sha
        self.parents = parents
        self.message = message
        self.author = author
        self.committer = committer
        self.files = files
        self.patch = patch
    }
}

/// Body of `POST /v1/repositories/{id}/merges`.
public struct RepositoryMergeCreate: Encodable, Sendable, Hashable {
    /// Branch to merge into.
    public var base: String
    /// Branch name or commit sha to merge.
    public var head: String
    /// Defaults server-side to `Merge {head} into {base}`.
    public var commitMessage: String?

    public init(base: String, head: String, commitMessage: String? = nil) {
        self.base = base
        self.head = head
        self.commitMessage = commitMessage
    }

    private enum CodingKeys: String, CodingKey {
        case base, head
        case commitMessage = "commit_message"
    }
}

/// The commit `base` now points at.
public struct RepositoryMerge: Codable, Sendable, Hashable {
    public var sha: String
    public var base: String?
    public var head: String?
    public var headSha: String?
    public var parents: [String]?

    public init(sha: String, base: String? = nil, head: String? = nil, headSha: String? = nil, parents: [String]? = nil) {
        self.sha = sha
        self.base = base
        self.head = head
        self.headSha = headSha
        self.parents = parents
    }

    private enum CodingKeys: String, CodingKey {
        case sha, base, head, parents
        case headSha = "head_sha"
    }
}

/// Options for walking a repository's history.
public struct RepositoryCommitsParams: Sendable, Hashable {
    /// Branch, tag or commit to walk back from; the default branch when nil.
    public var sha: String?
    /// Only commits touching this path.
    public var path: String?
    /// Page size, at most 100.
    public var limit: Int?
    /// Starting cursor.
    public var cursor: String?

    public init(sha: String? = nil, path: String? = nil, limit: Int? = nil, cursor: String? = nil) {
        self.sha = sha
        self.path = path
        self.limit = limit
        self.cursor = cursor
    }
}

/// The body of `POST /v1/repositories` for a repository hosted on the project's Data Plane. Idempotent on `slug`;
/// the hosted copy exists once provisioning lands (`provisioningStatus`). Linking a GitHub repository is a CLI action.
public struct HostedRepositoryCreate: Encodable, Sendable, Hashable {
    public var slug: String
    public var defaultBranch: String?
    /// A template of the deployment's rendered as the first commit; omitted, the deployment's default.
    public var seedTemplate: String?

    public init(slug: String, defaultBranch: String? = nil, seedTemplate: String? = nil) {
        self.slug = slug
        self.defaultBranch = defaultBranch
        self.seedTemplate = seedTemplate
    }

    private enum CodingKeys: String, CodingKey {
        case provider, slug
        case defaultBranch = "default_branch"
        case seedTemplate = "seed_template"
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("introspection", forKey: .provider)
        try container.encode(slug, forKey: .slug)
        try container.encodeIfPresent(defaultBranch, forKey: .defaultBranch)
        try container.encodeIfPresent(seedTemplate, forKey: .seedTemplate)
    }
}

/// A branch of a repository and its head commit.
public struct RepositoryBranch: Codable, Sendable, Hashable {
    public var name: String
    public var sha: String
    /// Only with `sort: .recent`: the Git date as the server formats it.
    public var committedAt: String?

    public init(name: String, sha: String, committedAt: String? = nil) {
        self.name = name
        self.sha = sha
        self.committedAt = committedAt
    }

    private enum CodingKeys: String, CodingKey {
        case name, sha
        case committedAt = "committed_at"
    }
}

/// The order of `repositories.branches`.
public struct RepositoryBranchSort: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    /// Pages by name.
    public static let name: RepositoryBranchSort = "name"
    /// One name-sorted page, newest commit first, with `committedAt`; it never has a next page.
    public static let recent: RepositoryBranchSort = "recent"
}

/// Filters for `GET /v1/repositories/{id}/branches`.
public struct RepositoryBranchesParams: Sendable, Hashable {
    /// Only branches whose name contains this, ignoring case.
    public var query: String?
    public var sort: RepositoryBranchSort?
    public var limit: Int?
    public var cursor: String?

    public init(query: String? = nil, sort: RepositoryBranchSort? = nil, limit: Int? = nil, cursor: String? = nil) {
        self.query = query
        self.sort = sort
        self.limit = limit
        self.cursor = cursor
    }
}

// MARK: APIs

/// Reads of a repository's files and directories through the Data Plane.
public struct RepositoryContentsAPI: Sendable {
    let http: HTTPClient

    public init(http: HTTPClient) { self.http = http }

    static func path(_ repositoryId: String, _ path: String) -> String {
        let base = "/v1/repositories/\(pathSegment(repositoryId))/contents"
        let segments = path.split(separator: "/", omittingEmptySubsequences: true).map { pathSegment(String($0)) }
        return segments.isEmpty ? base : "\(base)/\(segments.joined(separator: "/"))"
    }

    /// Read one path: a directory page or a file.
    public func get(
        _ repositoryId: String, path: String = "", ref: String? = nil, limit: Int? = nil, cursor: String? = nil
    ) async throws -> RepositoryContent {
        var query = Query()
        query.add("ref", ref)
        query.add("cursor", cursor)
        query.add("limit", limit)
        return try await http.json("GET", Self.path(repositoryId, path), query: query)
    }

    /// Every entry of the directory at `path` (the root by default), across pages.
    /// Fails with a validation error when `path` is a file.
    public func list(_ repositoryId: String, path: String = "", ref: String? = nil, limit: Int? = nil) -> Paginator<RepositoryEntry> {
        let api = self
        return Paginator { cursor in
            let content = try await api.get(repositoryId, path: path, ref: ref, limit: limit, cursor: cursor)
            guard case let .directory(directory) = content else {
                throw IntrospectionError(
                    kind: .validation,
                    message: "'\(content.path)' is a file, not a directory; read it with repositories.contents.get()",
                    status: 422,
                    code: "repository_path_is_file"
                )
            }
            return Page(records: directory.records, count: directory.count, next: directory.next)
        }
    }

    /// Shorthand for `list`.
    public func callAsFunction(
        _ repositoryId: String, path: String = "", ref: String? = nil, limit: Int? = nil
    ) -> Paginator<RepositoryEntry> {
        list(repositoryId, path: path, ref: ref, limit: limit)
    }
}

/// Repositories linked to a project. Lookup is on the Control Plane; contents,
/// history and merges go through the Data Plane.
public struct RepositoriesAPI: Sendable {
    let controlPlane: HTTPClient
    let dataPlane: HTTPClient

    public init(controlPlane: HTTPClient, dataPlane: HTTPClient) {
        self.controlPlane = controlPlane
        self.dataPlane = dataPlane
    }

    /// File and directory reads.
    public var contents: RepositoryContentsAPI { RepositoryContentsAPI(http: dataPlane) }

    /// Every repository in the project (the route answers one array, not a page).
    public func list(project: String? = nil, slug: String? = nil) async throws -> [Repository] {
        var query = cpProjectQuery(project)
        query.add("slug", slug)
        return try await controlPlane.json("GET", "/v1/repositories", query: query)
    }

    /// Fetch one repository.
    public func get(_ repositoryId: String, project: String? = nil) async throws -> Repository {
        try await controlPlane.json("GET", "/v1/repositories/\(pathSegment(repositoryId))", query: cpProjectQuery(project))
    }

    /// Create a repository hosted on the project's Data Plane.
    public func create(_ body: HostedRepositoryCreate, project: String? = nil) async throws -> Repository {
        try await controlPlane.json("POST", "/v1/repositories", query: cpProjectQuery(project), body: .encode(body))
    }

    /// Unregister a repository. A recipe still pinned in it is a conflict (`repository_in_use`).
    public func delete(_ repositoryId: String, project: String? = nil) async throws {
        try await controlPlane.empty("DELETE", "/v1/repositories/\(pathSegment(repositoryId))", query: cpProjectQuery(project))
    }

    /// The commit history from `params.sha`, across pages.
    public func commits(
        _ repositoryId: String, _ params: RepositoryCommitsParams = RepositoryCommitsParams()
    ) -> Paginator<RepositoryCommit> {
        var query = Query()
        query.add("sha", params.sha)
        query.add("path", params.path)
        query.add("limit", params.limit)
        return cursorPages(repositoryId, "commits", query: query, start: params.cursor)
    }

    /// The repository's branches, across pages.
    public func branches(
        _ repositoryId: String, _ params: RepositoryBranchesParams = RepositoryBranchesParams()
    ) -> Paginator<RepositoryBranch> {
        var query = Query()
        query.add("q", params.query)
        query.add("sort", params.sort)
        query.add("limit", params.limit)
        return cursorPages(repositoryId, "branches", query: query, start: params.cursor)
    }

    /// A Data Plane list under the repository that pages on `cursor`.
    private func cursorPages<Item: Decodable & Sendable>(
        _ repositoryId: String, _ name: String, query: Query, start: String?
    ) -> Paginator<Item> {
        let path = "/v1/repositories/\(pathSegment(repositoryId))/\(name)"
        let http = dataPlane
        return Paginator(start: start) { cursor in
            var pageQuery = query
            pageQuery.set("cursor", cursor)
            return try await http.json("GET", path, query: pageQuery, as: Page<Item>.self)
        }
    }

    /// One commit with its changed files and diff.
    public func commit(_ repositoryId: String, sha: String) async throws -> RepositoryCommitDetail {
        try await dataPlane.json("GET", "/v1/repositories/\(pathSegment(repositoryId))/commits/\(pathSegment(sha))")
    }

    /// Merge `head` into `base`, like GitHub's merges API. Returns nil when `base` already contains `head`.
    /// A conflict throws `.conflict`; a 504 means it is still running and resending attaches to it.
    public func merge(_ repositoryId: String, _ body: RepositoryMergeCreate) async throws -> RepositoryMerge? {
        let response = try await dataPlane.send(
            "POST", "/v1/repositories/\(pathSegment(repositoryId))/merges", body: .encode(body)
        )
        if response.status == 204 || response.body.isEmpty { return nil }
        return try HTTPClient.decode(RepositoryMerge.self, from: response)
    }
}

extension IntrospectionClient {
    /// Repositories (Control Plane) with contents, history and merges (Data Plane).
    public var repositories: RepositoriesAPI { RepositoriesAPI(controlPlane: controlPlane, dataPlane: dataPlane) }
}
