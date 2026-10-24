import Foundation

// MARK: Enums

/// What produced an image.
public struct ImageKind: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    /// A Recipe bake.
    public static let runtime: ImageKind = "runtime"
    /// A caller's `POST /v1/images`.
    public static let service: ImageKind = "service"
}

/// Build state of an image.
public struct ImageStatus: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let queued: ImageStatus = "queued"
    public static let building: ImageStatus = "building"
    public static let ready: ImageStatus = "ready"
    public static let failed: ImageStatus = "failed"
    public static let cancelled: ImageStatus = "cancelled"
    public static let evicted: ImageStatus = "evicted"
}

/// Outcome of an image's vulnerability scan.
public struct ImageScanStatus: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let pending: ImageScanStatus = "pending"
    public static let passed: ImageScanStatus = "passed"
    public static let findings: ImageScanStatus = "findings"
    public static let failed: ImageScanStatus = "failed"
    public static let skipped: ImageScanStatus = "skipped"
}

/// Where an image's bytes came from.
public struct ImageSourceKind: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let context: ImageSourceKind = "context"
    public static let mirror: ImageSourceKind = "mirror"
    public static let bake: ImageSourceKind = "bake"
}

// MARK: Models

/// An image in the plane's registry, which is what an eval task's compose services run as.
public struct IntrospectionImage: Codable, Sendable, Hashable {
    public var id: String
    public var kind: ImageKind?
    /// Lowercase path segments, for example `hello-mcp/mcp-server`.
    public var name: String?
    /// What a create dedupes on: a repeat create of the same content returns this row.
    public var contentId: String?
    public var sourceKind: ImageSourceKind?
    /// The source as the API normalized it.
    public var source: JSONObject?
    public var buildPlatform: String?
    public var service: String?
    public var repositoryId: String?
    public var gitSha: String?
    public var gitRef: String?
    public var path: String?
    public var runtimeId: String?
    public var taskId: String?
    public var trigger: String?
    public var baseImageDigest: String?
    public var baseImageTag: String?
    public var externalArtifacts: [String: String]?
    public var externalImageName: String?
    public var status: ImageStatus?
    public var imageRef: String?
    public var imageDigest: String?
    public var sizeBytes: Int?
    public var warnings: [String]?
    public var error: String?
    public var scanStatus: ImageScanStatus?
    public var scanStartedAt: Date?
    public var scannedAt: Date?
    public var scanDbBuiltAt: Date?
    public var scanSummary: JSONObject?
    public var scanReportFileId: String?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var startedAt: Date?
    public var finishedAt: Date?
    public var lastUsedAt: Date?
    public var evictedAt: Date?
    public var retiredAt: Date?

    /// A value with only its id set; decoding fills the rest.
    public init(id: String) { self.id = id }

    /// The digest-pinned reference a compose service names, once the image is ready.
    public var pullReference: String? {
        guard let imageRef, let imageDigest else { return nil }
        return "\(imageRef)@\(imageDigest)"
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, name, source, service, path, trigger, status, warnings, error
        case contentId = "content_id"
        case sourceKind = "source_kind"
        case buildPlatform = "build_platform"
        case repositoryId = "repository_id"
        case gitSha = "git_sha"
        case gitRef = "git_ref"
        case runtimeId = "runtime_id"
        case taskId = "task_id"
        case baseImageDigest = "base_image_digest"
        case baseImageTag = "base_image_tag"
        case externalArtifacts = "external_artifacts"
        case externalImageName = "external_image_name"
        case imageRef = "image_ref"
        case imageDigest = "image_digest"
        case sizeBytes = "size_bytes"
        case scanStatus = "scan_status"
        case scanStartedAt = "scan_started_at"
        case scannedAt = "scanned_at"
        case scanDbBuiltAt = "scan_db_built_at"
        case scanSummary = "scan_summary"
        case scanReportFileId = "scan_report_file_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case startedAt = "started_at"
        case finishedAt = "finished_at"
        case lastUsedAt = "last_used_at"
        case evictedAt = "evicted_at"
        case retiredAt = "retired_at"
    }
}

/// Filters for `GET /v1/images`.
public struct ImageListParams: Sendable, Hashable {
    public var kind: ImageKind?
    public var status: ImageStatus?
    public var name: String?
    public var runtimeId: String?
    public var limit: Int?
    public var next: String?

    public init(
        kind: ImageKind? = nil, status: ImageStatus? = nil, name: String? = nil, runtimeId: String? = nil, limit: Int? = nil,
        next: String? = nil
    ) {
        self.kind = kind
        self.status = status
        self.name = name
        self.runtimeId = runtimeId
        self.limit = limit
        self.next = next
    }
}

/// Where a new image's bytes come from, tagged on the wire by `kind`.
public enum ImageSource: Encodable, Sendable, Hashable {
    /// Build from a Dockerfile inside a `.tar.gz` uploaded through the Files API. `dockerfile` is a path inside
    /// the archive (default `Dockerfile`); `platform` is `linux/amd64` or `linux/arm64` (default: the plane's).
    case context(fileId: String, dockerfile: String? = nil, platform: String? = nil)
    /// Copy an upstream image, pinned by digest (`...@sha256:...`), into the plane's registry.
    case mirror(reference: String)

    private enum CodingKeys: String, CodingKey {
        case kind, dockerfile, platform, reference
        case fileId = "file_id"
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .context(fileId, dockerfile, platform):
            try container.encode(ImageSourceKind.context, forKey: .kind)
            try container.encode(fileId, forKey: .fileId)
            try container.encodeIfPresent(dockerfile, forKey: .dockerfile)
            try container.encodeIfPresent(platform, forKey: .platform)
        case let .mirror(reference):
            try container.encode(ImageSourceKind.mirror, forKey: .kind)
            try container.encode(reference, forKey: .reference)
        }
    }
}

/// Where a Recipe publish built an image from, and the compose service it runs as.
public struct ImageProvenance: Encodable, Sendable, Hashable {
    /// The compose service name, a DNS label.
    public var service: String
    public var repositoryId: String?
    public var gitSha: String?
    public var path: String?

    public init(service: String, repositoryId: String? = nil, gitSha: String? = nil, path: String? = nil) {
        self.service = service
        self.repositoryId = repositoryId
        self.gitSha = gitSha
        self.path = path
    }

    private enum CodingKeys: String, CodingKey {
        case service, path
        case repositoryId = "repository_id"
        case gitSha = "git_sha"
    }
}

/// Body of `POST /v1/images`.
public struct ImageCreate: Encodable, Sendable, Hashable {
    /// Lowercase path segments, for example `hello-mcp/mcp-server`.
    public var name: String
    public var source: ImageSource
    public var provenance: ImageProvenance?
    /// Ask for (`true`) or opt out of (`false`) a vulnerability scan within the plane's policy; nil takes the policy.
    public var scan: Bool?

    public init(name: String, source: ImageSource, provenance: ImageProvenance? = nil, scan: Bool? = nil) {
        self.name = name
        self.source = source
        self.provenance = provenance
        self.scan = scan
    }
}

// MARK: API

/// Images an eval task's compose services run as (`/v1/images`). A create is idempotent on content (resending
/// it retries a failed build) and `status` is the only progress report, so poll ``get(_:)`` until it is
/// `ready` or `failed`. Needs `images:read` / `images:write` on a plane with evals enabled.
public struct ImagesAPI: Sendable {
    let http: HTTPClient

    public init(http: HTTPClient) { self.http = http }

    /// List the project's images.
    public func list(_ params: ImageListParams = ImageListParams()) -> Paginator<IntrospectionImage> {
        var query = Query()
        query.add("kind", params.kind)
        query.add("status", params.status)
        query.add("name", params.name)
        query.add("runtime_id", params.runtimeId)
        query.add("limit", params.limit)
        return http.paginate("/v1/images", query: query, start: params.next)
    }

    /// Fetch one image.
    public func get(_ imageId: String) async throws -> IntrospectionImage {
        try await http.json("GET", "/v1/images/\(pathSegment(imageId))")
    }

    /// Record an image and send its build.
    public func create(_ body: ImageCreate) async throws -> IntrospectionImage {
        try await http.json("POST", "/v1/images", body: .encode(body))
    }

    /// Delete an image. Deleting a runtime image rebakes it; one still baking answers 409.
    public func delete(_ imageId: String) async throws {
        try await http.empty("DELETE", "/v1/images/\(pathSegment(imageId))")
    }
}

extension DataPlaneConnection {
    /// Images an eval task's compose services run as (`/v1/images`).
    public var images: ImagesAPI { ImagesAPI(http: dataPlane) }
}
