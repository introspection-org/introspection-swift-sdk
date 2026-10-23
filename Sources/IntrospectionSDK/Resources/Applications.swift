import Foundation

// MARK: Enums

/// What kind of OAuth client an Application is.
public struct ApplicationType: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let native: ApplicationType = "native"
    public static let spa: ApplicationType = "spa"
    /// A backend that signs its own assertions with keys registered under ``ApplicationsAPI/keys``.
    public static let jwks: ApplicationType = "jwks"
    public static let serviceAccount: ApplicationType = "service_account"
}

/// An OAuth grant an Application may use.
public struct ApplicationGrant: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let authorizationCode: ApplicationGrant = "authorization_code"
    public static let refreshToken: ApplicationGrant = "refresh_token"
    public static let clientCredentials: ApplicationGrant = "client_credentials"
    public static let deviceCode: ApplicationGrant = "device_code"
    public static let emailCode: ApplicationGrant = "email_code"
}

/// The vendor of an identity provider an Application brokers.
public struct ApplicationIdpProvider: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let auth0: ApplicationIdpProvider = "auth0"
    public static let okta: ApplicationIdpProvider = "okta"
    public static let supabase: ApplicationIdpProvider = "supabase"
    public static let neon: ApplicationIdpProvider = "neon"
    /// Any OIDC issuer.
    public static let generic: ApplicationIdpProvider = "generic"
    public static let zitadel: ApplicationIdpProvider = "zitadel"
}

/// Provisioning state of a brokered identity provider.
public struct ApplicationIdpStatus: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let pending: ApplicationIdpStatus = "pending"
    public static let active: ApplicationIdpStatus = "active"
    public static let failed: ApplicationIdpStatus = "failed"
}

/// Lifecycle of an Application's client secret.
public struct ApplicationSecretStatus: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let active: ApplicationSecretStatus = "active"
    public static let disabled: ApplicationSecretStatus = "disabled"
    public static let expired: ApplicationSecretStatus = "expired"
}

// MARK: Applications

/// An OAuth client registered in a project. Its secrets are under ``ApplicationsAPI/secrets``.
public struct Application: Codable, Sendable, Hashable {
    public var id: String
    public var orgId: String?
    public var projectId: String?
    public var name: String?
    public var applicationType: ApplicationType?
    public var environment: RuntimeEnvironment?
    public var clientId: String?
    public var redirectUris: [String]?
    public var allowedOrigins: [String]?
    public var allowedScopes: [String]?
    public var allowedGrants: [ApplicationGrant]?
    public var agentMemberId: String?
    public var lastUsedAt: Date?
    public var revokedAt: Date?
    public var createdByMemberId: String?
    public var createdAt: Date?
    public var updatedAt: Date?

    /// A value with only its id set; decoding fills the rest.
    public init(id: String) { self.id = id }

    private enum CodingKeys: String, CodingKey {
        case id, name, environment
        case orgId = "org_id"
        case projectId = "project_id"
        case applicationType = "application_type"
        case clientId = "client_id"
        case redirectUris = "redirect_uris"
        case allowedOrigins = "allowed_origins"
        case allowedScopes = "allowed_scopes"
        case allowedGrants = "allowed_grants"
        case agentMemberId = "agent_member_id"
        case lastUsedAt = "last_used_at"
        case revokedAt = "revoked_at"
        case createdByMemberId = "created_by_member_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Paging and the project selector for `GET /v1/applications`.
public struct ApplicationListParams: Sendable, Hashable {
    /// The project's slug or id, when the credential does not name one.
    public var project: String?
    public var limit: Int?
    public var next: String?

    public init(project: String? = nil, limit: Int? = nil, next: String? = nil) {
        self.project = project
        self.limit = limit
        self.next = next
    }
}

/// Body of `POST /v1/applications`.
public struct ApplicationCreate: Encodable, Sendable, Hashable {
    public var name: String
    public var applicationType: ApplicationType
    /// Defaults to `production`.
    public var environment: RuntimeEnvironment?
    public var redirectUris: [String]?
    public var allowedOrigins: [String]?
    public var allowedScopes: [String]?
    /// The agent member a `service_account` Application acts as.
    public var agentMemberId: String?

    public init(
        name: String, applicationType: ApplicationType, environment: RuntimeEnvironment? = nil, redirectUris: [String]? = nil,
        allowedOrigins: [String]? = nil, allowedScopes: [String]? = nil, agentMemberId: String? = nil
    ) {
        self.name = name
        self.applicationType = applicationType
        self.environment = environment
        self.redirectUris = redirectUris
        self.allowedOrigins = allowedOrigins
        self.allowedScopes = allowedScopes
        self.agentMemberId = agentMemberId
    }

    private enum CodingKeys: String, CodingKey {
        case name, environment
        case applicationType = "application_type"
        case redirectUris = "redirect_uris"
        case allowedOrigins = "allowed_origins"
        case allowedScopes = "allowed_scopes"
        case agentMemberId = "agent_member_id"
    }
}

/// Body of `PATCH /v1/applications/{id}`. A list replaces the whole value; `clientId` cannot change.
public struct ApplicationUpdate: Encodable, Sendable, Hashable {
    public var name: String?
    public var redirectUris: [String]?
    public var allowedOrigins: [String]?
    public var allowedScopes: [String]?
    public var agentMemberId: String?

    public init(
        name: String? = nil, redirectUris: [String]? = nil, allowedOrigins: [String]? = nil, allowedScopes: [String]? = nil,
        agentMemberId: String? = nil
    ) {
        self.name = name
        self.redirectUris = redirectUris
        self.allowedOrigins = allowedOrigins
        self.allowedScopes = allowedScopes
        self.agentMemberId = agentMemberId
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case redirectUris = "redirect_uris"
        case allowedOrigins = "allowed_origins"
        case allowedScopes = "allowed_scopes"
        case agentMemberId = "agent_member_id"
    }
}

// MARK: Identity providers

/// An identity provider brokered into an Application, whose users sign in as customer members.
public struct ApplicationIdp: Codable, Sendable, Hashable {
    public var id: String
    public var orgId: String?
    public var applicationId: String?
    public var idpProvider: ApplicationIdpProvider?
    public var issuer: String?
    public var clientId: String?
    /// The upstream client secret, when the provider has one.
    public var clientSecret: Secret?
    public var scopes: [String]?
    public var externalOrgId: String?
    public var externalIdpId: String?
    public var audienceClientId: String?
    public var status: ApplicationIdpStatus?
    public var errorMessage: String?
    public var isActive: Bool?
    public var disabledAt: Date?
    public var createdAt: Date?
    public var updatedAt: Date?

    /// A value with only its id set; decoding fills the rest.
    public init(id: String) { self.id = id }

    private enum CodingKeys: String, CodingKey {
        case id, issuer, scopes, status
        case orgId = "org_id"
        case applicationId = "application_id"
        case idpProvider = "idp_provider"
        case clientId = "client_id"
        case clientSecret = "client_secret"
        case externalOrgId = "external_org_id"
        case externalIdpId = "external_idp_id"
        case audienceClientId = "audience_client_id"
        case errorMessage = "error_message"
        case isActive = "is_active"
        case disabledAt = "disabled_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Body of `POST /v1/applications/{id}/idps`, for a `jwks` or `spa` Application.
public struct ApplicationIdpCreate: Encodable, Sendable, Hashable {
    /// Defaults to `generic`.
    public var idpProvider: ApplicationIdpProvider?
    public var issuer: String?
    public var clientId: String?
    public var clientSecret: Secret?
    public var scopes: [String]?
    public var audienceClientId: String?

    public init(
        idpProvider: ApplicationIdpProvider? = nil, issuer: String? = nil, clientId: String? = nil, clientSecret: Secret? = nil,
        scopes: [String]? = nil, audienceClientId: String? = nil
    ) {
        self.idpProvider = idpProvider
        self.issuer = issuer
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.scopes = scopes
        self.audienceClientId = audienceClientId
    }

    private enum CodingKeys: String, CodingKey {
        case issuer, scopes
        case idpProvider = "idp_provider"
        case clientId = "client_id"
        case clientSecret = "client_secret"
        case audienceClientId = "audience_client_id"
    }
}

// MARK: Secrets and keys

/// A client secret of a confidential Application. ``secret`` is set on the create response only.
public struct ApplicationSecret: Codable, Sendable, Hashable {
    public var id: String
    public var orgId: String?
    public var applicationId: String?
    public var name: String?
    public var secretPrefix: String?
    public var secretSuffix: String?
    /// The plaintext, returned once by ``ApplicationSecretsAPI/create(_:name:)``.
    public var secret: Secret?
    public var status: ApplicationSecretStatus?
    public var expiresAt: Date?
    public var disabledAt: Date?
    public var lastUsedAt: Date?
    public var createdByMemberId: String?
    public var createdAt: Date?
    public var updatedAt: Date?

    /// A value with only its id set; decoding fills the rest.
    public init(id: String) { self.id = id }

    private enum CodingKeys: String, CodingKey {
        case id, name, secret, status
        case orgId = "org_id"
        case applicationId = "application_id"
        case secretPrefix = "secret_prefix"
        case secretSuffix = "secret_suffix"
        case expiresAt = "expires_at"
        case disabledAt = "disabled_at"
        case lastUsedAt = "last_used_at"
        case createdByMemberId = "created_by_member_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// A signing key of a `jwks` Application: the public half, published at the Application's JWKS URL.
public struct ApplicationKey: Codable, Sendable, Hashable {
    public var id: String
    public var orgId: String?
    public var applicationId: String?
    public var kid: String?
    public var algorithm: String?
    /// PEM-encoded public key.
    public var publicKey: String?
    public var createdByMemberId: String?
    public var createdAt: Date?
    public var updatedAt: Date?

    /// A value with only its id set; decoding fills the rest.
    public init(id: String) { self.id = id }

    private enum CodingKeys: String, CodingKey {
        case id, kid, algorithm
        case orgId = "org_id"
        case applicationId = "application_id"
        case publicKey = "public_key"
        case createdByMemberId = "created_by_member_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Paging for an Application's nested lists.
public struct ApplicationChildListParams: Sendable, Hashable {
    public var limit: Int?
    public var next: String?

    public init(limit: Int? = nil, next: String? = nil) {
        self.limit = limit
        self.next = next
    }
}

private struct ApplicationSecretBody: Encodable {
    let name: String?
}

// MARK: APIs

/// A project's OAuth clients (`/v1/applications`). Needs an org credential carrying `applications:*`.
public struct ApplicationsAPI: Sendable {
    let collection: ProjectScopedCollection

    public init(http: HTTPClient) { collection = ProjectScopedCollection(http: http, path: "/v1/applications") }

    /// The identity providers each Application brokers.
    public var idps: ApplicationIdpsAPI { ApplicationIdpsAPI(collection: collection) }

    /// Each confidential Application's client secrets.
    public var secrets: ApplicationSecretsAPI { ApplicationSecretsAPI(collection: collection) }

    /// Each `jwks` Application's signing keys.
    public var keys: ApplicationKeysAPI { ApplicationKeysAPI(collection: collection) }

    /// List the project's Applications.
    public func list(_ params: ApplicationListParams = ApplicationListParams()) -> Paginator<Application> {
        collection.list(project: params.project, limit: params.limit, next: params.next)
    }

    /// Fetch one Application.
    public func get(_ applicationId: String, project: String? = nil) async throws -> Application {
        try await collection.get(applicationId, project: project)
    }

    /// Register an Application.
    public func create(_ body: ApplicationCreate, project: String? = nil) async throws -> Application {
        try await collection.create(body, project: project)
    }

    /// Update an Application.
    public func update(_ applicationId: String, _ body: ApplicationUpdate, project: String? = nil) async throws -> Application {
        try await collection.update(applicationId, body, project: project)
    }

    /// Revoke an Application.
    public func delete(_ applicationId: String, project: String? = nil) async throws {
        try await collection.delete(applicationId, project: project)
    }
}

/// `/v1/applications/{id}/idps`.
public struct ApplicationIdpsAPI: Sendable {
    let collection: ProjectScopedCollection

    private func base(_ applicationId: String) -> ProjectScopedCollection { collection.child(applicationId, "idps") }

    /// List an Application's identity providers.
    public func list(
        _ applicationId: String, _ params: ApplicationChildListParams = ApplicationChildListParams()
    )
        -> Paginator<ApplicationIdp>
    {
        base(applicationId).list(project: nil, limit: params.limit, next: params.next)
    }

    /// Broker an identity provider into an Application.
    public func create(_ applicationId: String, _ body: ApplicationIdpCreate) async throws -> ApplicationIdp {
        try await base(applicationId).create(body, project: nil)
    }

    /// Remove a brokered identity provider.
    public func delete(_ applicationId: String, _ idpId: String) async throws {
        try await base(applicationId).delete(idpId, project: nil)
    }
}

/// `/v1/applications/{id}/secrets`.
public struct ApplicationSecretsAPI: Sendable {
    let collection: ProjectScopedCollection

    private func base(_ applicationId: String) -> ProjectScopedCollection { collection.child(applicationId, "secrets") }

    /// List an Application's secrets, without their plaintext.
    public func list(
        _ applicationId: String, _ params: ApplicationChildListParams = ApplicationChildListParams()
    )
        -> Paginator<ApplicationSecret>
    {
        base(applicationId).list(project: nil, limit: params.limit, next: params.next)
    }

    /// Mint a secret. Its plaintext is in ``ApplicationSecret/secret`` on this response only.
    public func create(_ applicationId: String, name: String? = nil) async throws -> ApplicationSecret {
        try await base(applicationId).create(ApplicationSecretBody(name: name), project: nil)
    }

    /// Disable a secret now, or after `expiresIn` seconds for a rotation.
    public func delete(_ applicationId: String, _ secretId: String, expiresIn: Int? = nil) async throws {
        try await base(applicationId).delete(secretId, project: nil, expiresIn: expiresIn)
    }
}

/// `/v1/applications/{id}/keys`.
public struct ApplicationKeysAPI: Sendable {
    let collection: ProjectScopedCollection

    private func base(_ applicationId: String) -> ProjectScopedCollection { collection.child(applicationId, "keys") }

    /// Every signing key of an Application, unpaginated.
    public func list(_ applicationId: String) async throws -> [ApplicationKey] {
        let keys = base(applicationId)
        return try await keys.http.json("GET", keys.path)
    }

    /// Mint a key pair; the API keeps the private half.
    public func create(_ applicationId: String) async throws -> ApplicationKey {
        let keys = base(applicationId)
        return try await keys.http.json("POST", keys.path)
    }

    /// Delete a signing key.
    public func delete(_ applicationId: String, _ keyId: String) async throws {
        try await base(applicationId).delete(keyId, project: nil)
    }
}

extension IntrospectionClient {
    /// The project's OAuth clients, their brokered identity providers, secrets and signing keys.
    public var applications: ApplicationsAPI { ApplicationsAPI(http: controlPlane) }
}
