import Foundation

/// The provider an integration installs.
public struct IntegrationType: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let github: IntegrationType = "github"
    public static let slack: IntegrationType = "slack"
    public static let linear: IntegrationType = "linear"
    public static let jira: IntegrationType = "jira"
    public static let notion: IntegrationType = "notion"
    public static let vercel: IntegrationType = "vercel"
    public static let custom: IntegrationType = "custom"
}

/// Lifecycle of an integration.
public struct IntegrationStatus: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let pending: IntegrationStatus = "pending"
    public static let active: IntegrationStatus = "active"
    public static let error: IntegrationStatus = "error"
    public static let disabled: IntegrationStatus = "disabled"
}

/// The org's own install of a provider (a GitHub App installation, a Slack workspace). At most one live
/// integration per type per org.
public struct Integration: Codable, Sendable, Hashable {
    public var id: String
    public var orgId: String?
    /// The wire's `type`.
    public var integrationType: IntegrationType?
    public var name: String?
    /// The provider's id for the install, set once it is activated.
    public var externalId: String?
    public var status: IntegrationStatus?
    public var tokenExpiresAt: Date?
    public var data: JSONObject?
    public var metadata: JSONObject?
    public var createdByMemberId: String?
    public var createdAt: Date?
    public var updatedAt: Date?

    /// A value with only its id set; decoding fills the rest.
    public init(id: String) { self.id = id }

    private enum CodingKeys: String, CodingKey {
        case id, name, status, data, metadata
        case orgId = "org_id"
        case integrationType = "type"
        case externalId = "external_id"
        case tokenExpiresAt = "token_expires_at"
        case createdByMemberId = "created_by_member_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Paging for `GET /v1/integrations`.
public struct IntegrationListParams: Sendable, Hashable {
    public var limit: Int?
    public var next: String?

    public init(limit: Int? = nil, next: String? = nil) {
        self.limit = limit
        self.next = next
    }
}

/// Body of `POST /v1/integrations`. The row is created `pending`; the provider's activation flow then sets
/// `externalId` with an update.
public struct IntegrationCreate: Encodable, Sendable, Hashable {
    /// The wire's `type`.
    public var integrationType: IntegrationType
    public var name: String?
    public var externalId: String?

    public init(integrationType: IntegrationType, name: String? = nil, externalId: String? = nil) {
        self.integrationType = integrationType
        self.name = name
        self.externalId = externalId
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case integrationType = "type"
        case externalId = "external_id"
    }
}

/// Body of `PATCH /v1/integrations/{id}`. `code` and `redirectUri` complete a provider's OAuth activation.
public struct IntegrationUpdate: Encodable, Sendable, Hashable {
    public var name: String?
    public var status: IntegrationStatus?
    /// Setting it on a pending integration makes the server verify the install with the provider.
    public var externalId: String?
    public var code: Secret?
    public var redirectUri: String?
    /// Only `false` is accepted: turns Slack interactivity off.
    public var slackInteractivityEnabled: Bool?

    public init(
        name: String? = nil, status: IntegrationStatus? = nil, externalId: String? = nil, code: Secret? = nil,
        redirectUri: String? = nil, slackInteractivityEnabled: Bool? = nil
    ) {
        self.name = name
        self.status = status
        self.externalId = externalId
        self.code = code
        self.redirectUri = redirectUri
        self.slackInteractivityEnabled = slackInteractivityEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case name, status, code
        case externalId = "external_id"
        case redirectUri = "redirect_uri"
        case slackInteractivityEnabled = "slack_interactivity_enabled"
    }
}

/// The org's provider installs (`/v1/integrations`). Org-wide, so there is no project selector. Needs an org
/// credential carrying `integrations:*`.
public struct IntegrationsAPI: Sendable {
    let collection: ProjectScopedCollection

    public init(http: HTTPClient) { collection = ProjectScopedCollection(http: http, path: "/v1/integrations") }

    /// List the org's integrations.
    public func list(_ params: IntegrationListParams = IntegrationListParams()) -> Paginator<Integration> {
        collection.list(project: nil, limit: params.limit, next: params.next)
    }

    /// Fetch one integration.
    public func get(_ integrationId: String) async throws -> Integration {
        try await collection.get(integrationId, project: nil)
    }

    /// Start an integration. Returns the live pending one of that type if there is one, and answers 409
    /// when an active or disabled one exists.
    public func create(_ body: IntegrationCreate) async throws -> Integration {
        try await collection.create(body, project: nil)
    }

    /// Update or activate an integration.
    public func update(_ integrationId: String, _ body: IntegrationUpdate) async throws -> Integration {
        try await collection.update(integrationId, body, project: nil)
    }

    /// Delete an integration.
    public func delete(_ integrationId: String) async throws {
        try await collection.delete(integrationId, project: nil)
    }
}

extension IntrospectionClient {
    /// The org's provider installs.
    public var integrations: IntegrationsAPI { IntegrationsAPI(http: controlPlane) }
}
