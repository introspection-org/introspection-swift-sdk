import Foundation

/// How a file entered the project. Unknown server values are preserved.
public struct FileType: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }

    public static let upload: FileType = "upload"
    public static let filesystem: FileType = "filesystem"
    public static let other: FileType = "other"
}

/// Semantic file category, used as a list filter (`memory/...`, `tasks/.../outputs/...`, or anything else).
public struct FileCategory: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }

    public static let memory: FileCategory = "memory"
    public static let output: FileCategory = "output"
    public static let file: FileCategory = "file"
}

/// Allow-listed sort fields for the file list.
public struct FileSortField: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }

    public static let createdAt: FileSortField = "created_at"
    public static let updatedAt: FileSortField = "updated_at"
}

/// Friendly content format, used as a list filter.
public struct FileContentFormat: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }

    public static let markdown: FileContentFormat = "markdown"
    public static let json: FileContentFormat = "json"
    public static let yaml: FileContentFormat = "yaml"
    public static let pdf: FileContentFormat = "pdf"
    public static let image: FileContentFormat = "image"
    public static let audio: FileContentFormat = "audio"
    public static let video: FileContentFormat = "video"
    public static let csv: FileContentFormat = "csv"
    public static let text: FileContentFormat = "text"
    public static let archive: FileContentFormat = "archive"
}

/// A project file stored in blob storage. Each version of a file is its own row.
public struct File: Codable, Sendable, Hashable {
    public var id: String
    public var orgId: String?
    public var projectId: String?
    public var createdAt: Date?
    public var updatedAt: Date?
    /// Logical file path or name.
    public var name: String
    public var fileType: FileType?
    public var storagePath: String?
    public var mimeType: String?
    public var metadata: JSONObject?
    /// Access-bearing tags, conventionally `key:value`. They belong to the file and carry across versions.
    public var tags: [String]?
    public var memberId: String?
    /// Originating task, for accounting only.
    public var taskId: String?
    public var generatedOutputTaskId: String?
    public var sizeBytes: Int64?
    public var version: Int?
    /// The previous version's id.
    public var parentId: String?
    public var storageVersionId: String?
    /// When the file expires (set from `ttl_seconds`); nil means it never expires.
    public var expiresAt: Date?

    public init(
        id: String, name: String, orgId: String? = nil, projectId: String? = nil, createdAt: Date? = nil,
        updatedAt: Date? = nil, fileType: FileType? = nil, storagePath: String? = nil, mimeType: String? = nil,
        metadata: JSONObject? = nil, tags: [String]? = nil, memberId: String? = nil, taskId: String? = nil,
        generatedOutputTaskId: String? = nil, sizeBytes: Int64? = nil, version: Int? = nil, parentId: String? = nil,
        storageVersionId: String? = nil, expiresAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.orgId = orgId
        self.projectId = projectId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.fileType = fileType
        self.storagePath = storagePath
        self.mimeType = mimeType
        self.metadata = metadata
        self.tags = tags
        self.memberId = memberId
        self.taskId = taskId
        self.generatedOutputTaskId = generatedOutputTaskId
        self.sizeBytes = sizeBytes
        self.version = version
        self.parentId = parentId
        self.storageVersionId = storageVersionId
        self.expiresAt = expiresAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, metadata, tags, version
        case orgId = "org_id"
        case projectId = "project_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case fileType = "file_type"
        case storagePath = "storage_path"
        case mimeType = "mime_type"
        case memberId = "member_id"
        case taskId = "task_id"
        case generatedOutputTaskId = "generated_output_task_id"
        case sizeBytes = "size_bytes"
        case parentId = "parent_id"
        case storageVersionId = "storage_version_id"
        case expiresAt = "expires_at"
    }
}

/// Filters for `GET /v1/files`. All are optional and combine with AND.
///
/// ```swift
/// // Active goals, most recently changed first; the paginator keeps the same query on every page.
/// let goals = try await client.files.list(
///     FileListParams(tag: "ark:goal", metadata: ["status": "active"], sort: .updatedAt)
/// ).collect()
/// ```
public struct FileListParams: Sendable, Hashable {
    /// Page size (1-1000, server default 100).
    public var limit: Int?
    /// Starting cursor.
    public var next: String?
    public var includeTotal: Bool?
    /// Include superseded versions (default: latest versions only).
    public var includeVersions: Bool?
    /// Also include files granted by these `/v1/shares` ids.
    public var shareIds: [String]?
    public var name: String?
    /// Case-insensitive name search.
    public var nameContains: String?
    public var fileType: FileType?
    public var category: FileCategory?
    public var contentFormat: FileContentFormat?
    /// Only files with (true) or without (false) version history.
    public var versioned: Bool?
    public var storagePath: String?
    public var taskId: String?
    /// Linked conversation or task id.
    public var conversationId: String?
    /// Owning member (privileged credentials only).
    public var memberId: String?
    /// One `key:value` tag.
    public var tag: String?
    /// Files whose metadata holds every pair as an exact string value (at most 16 keys; a number or boolean
    /// is not matched by its spelling). Sent as repeated `metadata=key:value`.
    public var metadata: [String: String]?
    /// `createdAt` (server default) or `updatedAt`. A `next` cursor only continues the sort and direction it came from.
    public var sort: FileSortField?
    /// `desc` (server default, newest first) or `asc`; ties break on `id` in the same direction.
    public var direction: ReadOrder?
    public var createdAfter: Date?
    public var createdBefore: Date?
    public var updatedAfter: Date?
    public var updatedBefore: Date?

    public init(
        limit: Int? = nil, next: String? = nil, includeTotal: Bool? = nil, includeVersions: Bool? = nil,
        shareIds: [String]? = nil, name: String? = nil, nameContains: String? = nil, fileType: FileType? = nil,
        category: FileCategory? = nil, contentFormat: FileContentFormat? = nil, versioned: Bool? = nil,
        storagePath: String? = nil, taskId: String? = nil, conversationId: String? = nil, memberId: String? = nil,
        tag: String? = nil, createdAfter: Date? = nil, createdBefore: Date? = nil, updatedAfter: Date? = nil,
        updatedBefore: Date? = nil, metadata: [String: String]? = nil, sort: FileSortField? = nil,
        direction: ReadOrder? = nil
    ) {
        self.limit = limit
        self.next = next
        self.includeTotal = includeTotal
        self.includeVersions = includeVersions
        self.shareIds = shareIds
        self.name = name
        self.nameContains = nameContains
        self.fileType = fileType
        self.category = category
        self.contentFormat = contentFormat
        self.versioned = versioned
        self.storagePath = storagePath
        self.taskId = taskId
        self.conversationId = conversationId
        self.memberId = memberId
        self.tag = tag
        self.createdAfter = createdAfter
        self.createdBefore = createdBefore
        self.updatedAfter = updatedAfter
        self.updatedBefore = updatedBefore
        self.metadata = metadata
        self.sort = sort
        self.direction = direction
    }

    var query: Query {
        var q = Query()
        q.add("limit", limit)
        q.add("include_total", includeTotal)
        q.add("include_versions", includeVersions)
        q.add("share_id", shareIds)
        q.add("name", name)
        q.add("name_contains", nameContains)
        q.add("file_type", fileType)
        q.add("category", category)
        q.add("content_format", contentFormat)
        q.add("versioned", versioned)
        q.add("storage_path", storagePath)
        q.add("task_id", taskId)
        q.add("conversation_id", conversationId)
        q.add("member_id", memberId)
        q.add("tag", tag)
        q.add("metadata", metadata.map { pairs in pairs.keys.sorted().compactMap { key in pairs[key].map { "\(key):\($0)" } } })
        q.add("sort", sort)
        q.add("direction", direction)
        q.add("created_after", createdAfter)
        q.add("created_before", createdBefore)
        q.add("updated_after", updatedAfter)
        q.add("updated_before", updatedBefore)
        return q
    }
}

/// Paging for `GET /v1/files/{id}/versions`.
public struct FileVersionListParams: Sendable, Hashable {
    public var limit: Int?
    public var next: String?
    public var includeTotal: Bool?

    public init(limit: Int? = nil, next: String? = nil, includeTotal: Bool? = nil) {
        self.limit = limit
        self.next = next
        self.includeTotal = includeTotal
    }
}

/// A binary upload, sent as `multipart/form-data`. Content is limited to 50 MB.
public struct FileUpload: Sendable {
    public var data: Data
    /// Filename sent with the part; also the display name when `name` is nil.
    public var filename: String
    /// Logical file name or path.
    public var name: String?
    /// Ignored when creating a version.
    public var fileType: FileType?
    /// Defaults to a type guessed from `filename`.
    public var contentType: String?
    public var metadata: JSONObject?
    /// Tags stamped on the file when this request creates it; a new version keeps the file's tags (change them with `update`).
    public var tags: [String]?
    /// Lifetime in seconds (1 to 30 days); omit for a file that never expires.
    public var ttlSeconds: Int?

    public init(
        data: Data, filename: String, name: String? = nil, fileType: FileType? = nil, contentType: String? = nil,
        metadata: JSONObject? = nil, tags: [String]? = nil, ttlSeconds: Int? = nil
    ) {
        self.data = data
        self.filename = filename
        self.name = name
        self.fileType = fileType
        self.contentType = contentType
        self.metadata = metadata
        self.tags = tags
        self.ttlSeconds = ttlSeconds
    }

    func form(includeFileType: Bool) throws -> MultipartFormData {
        var form = MultipartFormData()
        form.append(name: "file", filename: filename, contentType: contentType ?? mimeType(forFilename: filename), data: data)
        if let name { form.append(name: "name", value: name) }
        if includeFileType, let fileType { form.append(name: "file_type", value: fileType.rawValue) }
        if let metadata {
            let encoded: Data
            do {
                encoded = try JSONCoding.encoder.encode(JSONValue.object(metadata))
            } catch {
                throw IntrospectionError(kind: .invalidRequest, message: "Could not encode metadata: \(error)", underlying: error)
            }
            form.append(name: "metadata", value: String(decoding: encoded, as: UTF8.self))
        }
        for tag in tags ?? [] { form.append(name: "tags", value: tag) }
        if let ttlSeconds { form.append(name: "ttl_seconds", value: String(ttlSeconds)) }
        return form
    }
}

/// A text file (or a new text version), sent as JSON. Name it by `name` or target an existing `fileId`.
public struct FileCreateText: Encodable, Sendable, Hashable {
    public var content: String
    /// Logical path; an existing file with this name gets a new version.
    public var name: String?
    /// Existing file to version.
    public var fileId: String?
    /// Server default `text/markdown`.
    public var mimeType: String?
    public var metadata: JSONObject?
    /// Tags stamped on the file when this request creates it; a new version keeps the file's tags (change them with `update`).
    public var tags: [String]?
    /// Conditional save: the current version's SHA-256 must match, or the server answers 409.
    public var expectedSha256: String?
    public var ttlSeconds: Int?

    public init(
        content: String, name: String? = nil, fileId: String? = nil, mimeType: String? = nil,
        metadata: JSONObject? = nil, tags: [String]? = nil, expectedSha256: String? = nil, ttlSeconds: Int? = nil
    ) {
        self.content = content
        self.name = name
        self.fileId = fileId
        self.mimeType = mimeType
        self.metadata = metadata
        self.tags = tags
        self.expectedSha256 = expectedSha256
        self.ttlSeconds = ttlSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case content, name, metadata, tags
        case fileId = "file_id"
        case mimeType = "mime_type"
        case expectedSha256 = "expected_sha256"
        case ttlSeconds = "ttl_seconds"
    }
}

/// Changes for `PATCH /v1/files/{id}`.
public struct FileUpdate: Encodable, Sendable, Hashable {
    public var name: String?
    public var metadata: JSONObject?
    /// Replaces the tag list wholesale; `[]` clears it, nil leaves it untouched.
    public var tags: [String]?

    public init(name: String? = nil, metadata: JSONObject? = nil, tags: [String]? = nil) {
        self.name = name
        self.metadata = metadata
        self.tags = tags
    }
}

/// The Files API (`/v1/files`).
public struct FilesAPI: Sendable {
    let http: HTTPClient

    public init(http: HTTPClient) { self.http = http }

    /// Version history of a file.
    public var versions: FileVersionsAPI { FileVersionsAPI(http: http) }

    /// List files, latest versions only unless `includeVersions` is set.
    public func list(_ params: FileListParams = FileListParams()) -> Paginator<File> {
        http.paginate("/v1/files", query: params.query, start: params.next)
    }

    /// Upload a binary file.
    public func upload(_ upload: FileUpload) async throws -> File {
        try await http.json("POST", "/v1/files", body: .multipart(upload.form(includeFileType: true)))
    }

    /// Create a text file, or a new version of the file with the same name or id.
    public func createText(_ body: FileCreateText) async throws -> File {
        guard body.name != nil || body.fileId != nil else {
            throw IntrospectionError(kind: .invalidRequest, message: "createText requires a name or a fileId")
        }
        return try await http.json("POST", "/v1/files", body: .encode(body))
    }

    /// Read a file's metadata, optionally through a share grant.
    public func get(_ fileId: String, shareId: String? = nil) async throws -> File {
        var query = Query()
        query.add("share_id", shareId)
        return try await http.json("GET", "/v1/files/\(pathSegment(fileId))", query: query)
    }

    /// Update a file's name, metadata or tags.
    public func update(_ fileId: String, _ body: FileUpdate) async throws -> File {
        try await http.json("PATCH", "/v1/files/\(pathSegment(fileId))", body: .encode(body))
    }

    /// Soft delete a file.
    public func delete(_ fileId: String) async throws {
        try await http.empty("DELETE", "/v1/files/\(pathSegment(fileId))")
    }

    /// Download a file's content into memory.
    public func download(_ fileId: String, shareId: String? = nil) async throws -> Data {
        var query = Query()
        query.add("share_id", shareId)
        return try await http.data("GET", "/v1/files/\(pathSegment(fileId))/content", query: query, headers: ["Accept": "*/*"])
    }

    /// Stream a file's content. Headers carry `x-version` and, when versioned, `x-storage-version-id`.
    public func downloadStream(_ fileId: String, shareId: String? = nil) async throws -> HTTPStreamResponse {
        var query = Query()
        query.add("share_id", shareId)
        return try await http.stream("GET", "/v1/files/\(pathSegment(fileId))/content", query: query, headers: ["Accept": "*/*"])
    }
}

/// File versions (`/v1/files/{id}/versions`).
public struct FileVersionsAPI: Sendable {
    let http: HTTPClient

    public init(http: HTTPClient) { self.http = http }

    /// List every version of a file, newest first.
    public func list(_ fileId: String, _ params: FileVersionListParams = FileVersionListParams()) -> Paginator<File> {
        var query = Query()
        query.add("limit", params.limit)
        query.add("include_total", params.includeTotal)
        return http.paginate("/v1/files/\(pathSegment(fileId))/versions", query: query, start: params.next)
    }

    /// Read one version row from a file's version chain.
    public func get(_ fileId: String, _ versionId: String) async throws -> File {
        try await http.json("GET", "/v1/files/\(pathSegment(fileId))/versions/\(pathSegment(versionId))")
    }

    /// Upload new binary content as the next version (owner only).
    public func create(_ fileId: String, _ upload: FileUpload) async throws -> File {
        try await http.json("POST", "/v1/files/\(pathSegment(fileId))/versions", body: .multipart(upload.form(includeFileType: false)))
    }

    /// Save new text content as the next version (owner only).
    public func createText(_ fileId: String, _ body: FileCreateText) async throws -> File {
        var body = body
        body.fileId = fileId
        return try await http.json("POST", "/v1/files/\(pathSegment(fileId))/versions", body: .encode(body))
    }
}

extension DataPlaneConnection {
    /// Project files.
    public var files: FilesAPI { FilesAPI(http: dataPlane) }
}
