import Foundation

// MARK: Enums

/// What a project API key may do beyond the runner set.
public struct ApiKeyCapability: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    /// Manage the project's runtimes.
    public static let runtimes: ApiKeyCapability = "runtimes"
    /// Run eval tasks and their commands.
    public static let evals: ApiKeyCapability = "evals"
}

/// Lifecycle of an API key.
public struct ApiKeyStatus: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let active: ApiKeyStatus = "active"
    /// Deleted with a grace period: still valid until `expiresAt`.
    public static let rotating: ApiKeyStatus = "rotating"
    public static let expired: ApiKeyStatus = "expired"
    public static let revoked: ApiKeyStatus = "revoked"
}

// MARK: Models

/// A project API key. The plaintext is never readable after create; see ``ApiKeyCreated``.
public struct ApiKey: Codable, Sendable, Hashable {
    public var id: String
    public var orgId: String?
    public var projectId: String?
    public var name: String?
    public var environment: RuntimeEnvironment?
    public var allow: [ApiKeyCapability]?
    public var scope: String?
    /// The agent member the key acts as, when it is not the default one.
    public var memberId: String?
    public var keyPrefix: String?
    public var keySuffix: String?
    public var redactedKey: String?
    public var keyDisplay: String?
    public var prefix: String?
    public var status: ApiKeyStatus?
    public var expiresAt: Date?
    public var lastUsedAt: Date?
    /// Set once ``ApiKeysAPI/acknowledge(_:project:)`` records the key as saved.
    public var acknowledgedAt: Date?
    public var createdAt: Date?

    /// A value with only its id set; decoding fills the rest.
    public init(id: String) { self.id = id }

    private enum CodingKeys: String, CodingKey {
        case id, name, environment, allow, scope, prefix, status
        case orgId = "org_id"
        case projectId = "project_id"
        case memberId = "member_id"
        case keyPrefix = "key_prefix"
        case keySuffix = "key_suffix"
        case redactedKey = "redacted_key"
        case keyDisplay = "key_display"
        case expiresAt = "expires_at"
        case lastUsedAt = "last_used_at"
        case acknowledgedAt = "acknowledged_at"
        case createdAt = "created_at"
    }
}

/// Response of `POST /v1/api-keys`: the key, plus its plaintext, the only time the API returns it.
public struct ApiKeyCreated: Codable, Sendable, Hashable {
    /// The key's row, as later reads return it.
    public var key: ApiKey
    /// The plaintext key. Save it, then call ``ApiKeysAPI/acknowledge(_:project:)``.
    public var apiKey: Secret?

    public init(key: ApiKey, apiKey: Secret? = nil) {
        self.key = key
        self.apiKey = apiKey
    }

    private enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"
    }

    /// Decode the flat wire object: the key's fields beside `api_key`.
    public init(from decoder: any Decoder) throws {
        key = try ApiKey(from: decoder)
        apiKey = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(Secret.self, forKey: .apiKey)
    }

    /// Encode the flat wire object.
    public func encode(to encoder: any Encoder) throws {
        try key.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(apiKey, forKey: .apiKey)
    }
}

/// Filters for `GET /v1/api-keys`, which is not paginated.
public struct ApiKeyListParams: Sendable, Hashable {
    /// The project's slug or id, when the credential does not name one.
    public var project: String?
    /// Only keys close to expiry.
    public var expiring: Bool?

    public init(project: String? = nil, expiring: Bool? = nil) {
        self.project = project
        self.expiring = expiring
    }
}

/// Body of `POST /v1/api-keys`.
public struct ApiKeyCreate: Encodable, Sendable, Hashable {
    public var name: String?
    /// Defaults to `production`.
    public var environment: RuntimeEnvironment?
    public var allow: [ApiKeyCapability]?
    /// Act as this external-credential agent rather than the default one.
    public var memberId: String?
    public var expiresAt: Date?

    public init(
        name: String? = nil, environment: RuntimeEnvironment? = nil, allow: [ApiKeyCapability]? = nil, memberId: String? = nil,
        expiresAt: Date? = nil
    ) {
        self.name = name
        self.environment = environment
        self.allow = allow
        self.memberId = memberId
        self.expiresAt = expiresAt
    }

    private enum CodingKeys: String, CodingKey {
        case name, environment, allow
        case memberId = "member_id"
        case expiresAt = "expires_at"
    }
}

/// Body of `PATCH /v1/api-keys/{id}`. The lane, key material and lifetime cannot change.
public struct ApiKeyUpdate: Encodable, Sendable, Hashable {
    public var name: String?
    /// Replaces the capability list.
    public var allow: [ApiKeyCapability]?
    public var memberId: String?

    public init(name: String? = nil, allow: [ApiKeyCapability]? = nil, memberId: String? = nil) {
        self.name = name
        self.allow = allow
        self.memberId = memberId
    }

    private enum CodingKeys: String, CodingKey {
        case name, allow
        case memberId = "member_id"
    }
}

/// Response of `POST /v1/api-keys/{id}/acknowledge`.
public struct ApiKeyAcknowledgement: Codable, Sendable, Hashable {
    public var acknowledged: Bool?

    public init(acknowledged: Bool? = nil) { self.acknowledged = acknowledged }
}

// MARK: API

/// A project's API keys (`/v1/api-keys`). Needs an org credential carrying `api_keys:*`; a project API key
/// cannot manage keys.
public struct ApiKeysAPI: Sendable {
    let collection: ProjectScopedCollection

    public init(http: HTTPClient) { collection = ProjectScopedCollection(http: http, path: "/v1/api-keys") }

    private struct ListEnvelope: Decodable {
        let apiKeys: [ApiKey]

        enum CodingKeys: String, CodingKey {
            case apiKeys = "api_keys"
        }
    }

    /// Every key of the project, unpaginated.
    public func list(_ params: ApiKeyListParams = ApiKeyListParams()) async throws -> [ApiKey] {
        var query = cpProjectQuery(params.project)
        query.add("expiring", params.expiring)
        return try await collection.http.json("GET", collection.path, query: query, as: ListEnvelope.self).apiKeys
    }

    /// Mint a key. The plaintext is in ``ApiKeyCreated/apiKey`` and is never returned again.
    public func create(_ body: ApiKeyCreate = ApiKeyCreate(), project: String? = nil) async throws -> ApiKeyCreated {
        try await collection.create(body, project: project)
    }

    /// Rename a key or change what it may do.
    public func update(_ apiKeyId: String, _ body: ApiKeyUpdate, project: String? = nil) async throws -> ApiKey {
        try await collection.update(apiKeyId, body, project: project)
    }

    /// Revoke a key now, or keep it working `expiresIn` more seconds for a rotation.
    public func delete(_ apiKeyId: String, expiresIn: Int? = nil, project: String? = nil) async throws {
        try await collection.delete(apiKeyId, project: project, expiresIn: expiresIn)
    }

    /// Record that the plaintext from ``create(_:project:)`` was saved. A second acknowledge answers 404.
    public func acknowledge(_ apiKeyId: String, project: String? = nil) async throws -> ApiKeyAcknowledgement {
        try await collection.http.json("POST", "\(collection.itemPath(apiKeyId))/acknowledge", query: cpProjectQuery(project))
    }
}

extension IntrospectionClient {
    /// The project's API keys.
    public var apiKeys: ApiKeysAPI { ApiKeysAPI(http: controlPlane) }
}
