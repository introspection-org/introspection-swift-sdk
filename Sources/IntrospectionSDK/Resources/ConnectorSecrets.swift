import Foundation

/// How a caller proves it holds a `webhook` connector's secret.
public struct ConnectorSigningSecretType: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    /// A Standard Webhooks signature over the body, with a `whsec_` secret.
    public static let standardWebhooks: ConnectorSigningSecretType = "standard_webhooks"
    /// A `whtok_` secret sent as an `Authorization: Bearer` token.
    public static let bearer: ConnectorSigningSecretType = "bearer"
}

/// Whether a `webhook` connector's secret is the newest live one or the older one a rotation kept verifying.
public struct ConnectorSigningSecretStatus: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let current: ConnectorSigningSecretStatus = "current"
    public static let previous: ConnectorSigningSecretStatus = "previous"
}

/// One secret a `webhook` connector accepts, described without its material.
public struct WebhookSecret: Codable, Sendable, Hashable {
    /// The secret's key id: the first 8 hex digits of its SHA-256. Delete it by this id.
    public var id: String
    public var type: ConnectorSigningSecretType
    public var status: ConnectorSigningSecretStatus
    public var createdAt: Date

    public init(id: String, type: ConnectorSigningSecretType, status: ConnectorSigningSecretStatus, createdAt: Date) {
        self.id = id
        self.type = type
        self.status = status
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, type, status
        case createdAt = "created_at"
    }
}

/// A `webhook` connector's secret the one time it is issued, with its plaintext.
public struct WebhookSecretCreated: Codable, Sendable, Hashable {
    /// The secret's key id: the first 8 hex digits of its SHA-256.
    public var id: String
    public var type: ConnectorSigningSecretType
    public var status: ConnectorSigningSecretStatus
    public var createdAt: Date
    /// The secret itself (`whsec_...` or `whtok_...`). Shown once: store it, since no read returns it.
    public var secret: Secret

    public init(id: String, type: ConnectorSigningSecretType, status: ConnectorSigningSecretStatus, createdAt: Date, secret: Secret) {
        self.id = id
        self.type = type
        self.status = status
        self.createdAt = createdAt
        self.secret = secret
    }

    private enum CodingKeys: String, CodingKey {
        case id, secret, type, status
        case createdAt = "created_at"
    }
}

private struct WebhookSecretCreateBody: Encodable {
    let type: ConnectorSigningSecretType?
}

/// `/v1/connectors/{id}/secrets`: the secrets a `webhook` connector accepts. At most two are live, both of one type;
/// the newest is current and the older one, previous, still verifies so senders can switch over. Any other
/// connector answers 404.
public struct ConnectorSecretsAPI: Sendable {
    let http: HTTPClient

    public init(http: HTTPClient) { self.http = http }

    private func path(_ connectorId: String) -> String { "/v1/connectors/\(pathSegment(connectorId))/secrets" }

    /// List a `webhook` connector's live secrets, current first, without their material.
    ///
    /// - Parameters:
    ///   - connectorId: The `webhook` connector's id.
    ///   - params: The project, page size and cursor.
    /// - Returns: A paginator over the connector's secrets.
    public func list(_ connectorId: String, _ params: ConnectorListParams = ConnectorListParams()) -> Paginator<WebhookSecret> {
        var query = cpProjectQuery(params.project)
        query.add("limit", params.limit)
        return http.paginate(path(connectorId), query: query, start: params.next)
    }

    /// Issue a new current secret. Its plaintext is in ``WebhookSecretCreated/secret`` on this response only.
    ///
    /// Without `type` this rotates: the new secret takes the live secrets' type, and the one it replaces stays valid
    /// as the previous secret until deleted. The server answers 422 when no secret is live and `type` is omitted, and
    /// 409 with two already live or for a `type` other than the live secrets'. To change type, delete every secret.
    ///
    /// - Parameters:
    ///   - connectorId: The `webhook` connector's id.
    ///   - type: How callers authenticate. Required for the first secret.
    ///   - project: Project slug or id; defaults to the credential's project.
    /// - Returns: The new secret, with its plaintext.
    public func create(
        _ connectorId: String, type: ConnectorSigningSecretType? = nil, project: String? = nil
    ) async throws -> WebhookSecretCreated {
        try await http.json("POST", path(connectorId), query: cpProjectQuery(project), body: .encode(WebhookSecretCreateBody(type: type)))
    }

    /// Stop accepting a secret now. The server answers 409 for the current secret while a previous one is live, and
    /// 404 when no live secret has this id. Deleting the last one leaves the connector refusing every call.
    ///
    /// - Parameters:
    ///   - connectorId: The `webhook` connector's id.
    ///   - secretId: The secret's key id, ``WebhookSecret/id``.
    ///   - project: Project slug or id; defaults to the credential's project.
    public func delete(_ connectorId: String, secretId: String, project: String? = nil) async throws {
        if ["", ".", ".."].contains(secretId) {
            throw IntrospectionError(kind: .invalidRequest, message: "\(secretId.debugDescription) is not a secret id")
        }
        try await http.empty("DELETE", "\(path(connectorId))/\(pathSegment(secretId))", query: cpProjectQuery(project))
    }
}
