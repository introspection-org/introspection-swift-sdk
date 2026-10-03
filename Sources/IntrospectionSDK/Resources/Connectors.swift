import Foundation

// MARK: Enums

/// How a connector authenticates against its provider.
public struct ConnectorAuthMode: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let `static`: ConnectorAuthMode = "static"
    public static let oauthStored: ConnectorAuthMode = "oauth_stored"
    public static let clientCredentials: ConnectorAuthMode = "client_credentials"
    public static let identityAssertion: ConnectorAuthMode = "identity_assertion"
    public static let federatedExchange: ConnectorAuthMode = "federated_exchange"
    public static let personAuthorized: ConnectorAuthMode = "person_authorized"
}

/// Connector configuration status.
public struct ConnectorStatus: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let pending: ConnectorStatus = "pending"
    public static let active: ConnectorStatus = "active"
    public static let error: ConnectorStatus = "error"
}

/// Where a `person_authorized` connector's Person Server is hosted.
public struct ConnectorPersonServerMode: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let managed: ConnectorPersonServerMode = "managed"
    public static let byo: ConnectorPersonServerMode = "byo"
    public static let discovered: ConnectorPersonServerMode = "discovered"
}

/// How `person_authorized` missions are decided.
public struct ConnectorApprovalPolicy: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let human: ConnectorApprovalPolicy = "human"
    public static let judgeAdvisesHuman: ConnectorApprovalPolicy = "judge_advises_human"
    public static let judgeAutoWithinEnvelope: ConnectorApprovalPolicy = "judge_auto_within_envelope"
}

/// Lifecycle of a connection.
public struct ConnectionStatus: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let pendingAuthorization: ConnectionStatus = "pending_authorization"
    public static let active: ConnectionStatus = "active"
    public static let refreshFailed: ConnectionStatus = "refresh_failed"
    public static let revoked: ConnectionStatus = "revoked"
}

/// Who a connection acts as against the provider.
public struct ConnectionSubjectType: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let app: ConnectionSubjectType = "app"
    public static let user: ConnectionSubjectType = "user"
    public static let federated: ConnectionSubjectType = "federated"
    public static let person: ConnectionSubjectType = "person"
    public static let workspace: ConnectionSubjectType = "workspace"
}

// MARK: Connectors

/// A project-scoped integration to an external provider that connections are minted under.
/// `client_secret` and `signing_secret` are write-only and never returned.
public struct Connector: Codable, Sendable, Hashable {
    public var id: String
    public var orgId: String?
    public var projectId: String?
    /// Stable per-project identifier; create upserts on it.
    public var slug: String?
    public var name: String?
    /// Provider slug, for example `slack` or `gmail`.
    public var provider: String?
    public var authMode: ConnectorAuthMode?
    /// Create-time fact; not updatable.
    public var environment: RuntimeEnvironment?
    public var agentMemberId: String?
    public var authorizationEndpoint: String?
    public var tokenEndpoint: String?
    public var scopes: [String]?
    public var apiHosts: [String]?
    public var clientId: String?
    public var personServerMode: ConnectorPersonServerMode?
    public var personServerUrl: String?
    public var approvalPolicy: ConnectorApprovalPolicy?
    public var applicationId: String?
    public var assertionAudience: String?
    public var webhookUrl: String?
    public var status: ConnectorStatus?
    public var createdByMemberId: String?
    public var metadata: JSONObject?
    /// Whether `authorize` must name a `runtime` (chat providers). Read this rather than hardcoding providers.
    public var requiresRuntime: Bool?
    public var createdAt: Date?
    public var updatedAt: Date?

    public init(
        id: String, orgId: String? = nil, projectId: String? = nil, slug: String? = nil, name: String? = nil,
        provider: String? = nil, authMode: ConnectorAuthMode? = nil, environment: RuntimeEnvironment? = nil,
        agentMemberId: String? = nil, authorizationEndpoint: String? = nil, tokenEndpoint: String? = nil,
        scopes: [String]? = nil, apiHosts: [String]? = nil, clientId: String? = nil,
        personServerMode: ConnectorPersonServerMode? = nil, personServerUrl: String? = nil,
        approvalPolicy: ConnectorApprovalPolicy? = nil, applicationId: String? = nil, assertionAudience: String? = nil,
        webhookUrl: String? = nil, status: ConnectorStatus? = nil, createdByMemberId: String? = nil,
        metadata: JSONObject? = nil, requiresRuntime: Bool? = nil, createdAt: Date? = nil, updatedAt: Date? = nil
    ) {
        self.id = id
        self.orgId = orgId
        self.projectId = projectId
        self.slug = slug
        self.name = name
        self.provider = provider
        self.authMode = authMode
        self.environment = environment
        self.agentMemberId = agentMemberId
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.scopes = scopes
        self.apiHosts = apiHosts
        self.clientId = clientId
        self.personServerMode = personServerMode
        self.personServerUrl = personServerUrl
        self.approvalPolicy = approvalPolicy
        self.applicationId = applicationId
        self.assertionAudience = assertionAudience
        self.webhookUrl = webhookUrl
        self.status = status
        self.createdByMemberId = createdByMemberId
        self.metadata = metadata
        self.requiresRuntime = requiresRuntime
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, slug, name, provider, environment, scopes, status, metadata
        case orgId = "org_id"
        case projectId = "project_id"
        case authMode = "auth_mode"
        case agentMemberId = "agent_member_id"
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case apiHosts = "api_hosts"
        case clientId = "client_id"
        case personServerMode = "person_server_mode"
        case personServerUrl = "person_server_url"
        case approvalPolicy = "approval_policy"
        case applicationId = "application_id"
        case assertionAudience = "assertion_audience"
        case webhookUrl = "webhook_url"
        case createdByMemberId = "created_by_member_id"
        case requiresRuntime = "requires_runtime"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Body of `POST /v1/connectors`.
public struct ConnectorCreate: Encodable, Sendable, Hashable {
    public var name: String
    public var provider: String
    public var authMode: ConnectorAuthMode
    /// Derived from `name` when omitted.
    public var slug: String?
    /// Lane the connector serves (server default `production`).
    public var environment: RuntimeEnvironment?
    public var agentMemberId: String?
    public var authorizationEndpoint: String?
    public var tokenEndpoint: String?
    public var scopes: [String]?
    public var apiHosts: [String]?
    public var clientId: String?
    /// Write-only.
    public var clientSecret: String?
    /// Write-only.
    public var signingSecret: String?
    /// Provider settings; a `pipedream` connector requires `provider_workspace_id`.
    public var metadata: JSONObject?
    /// OAuth discovery: the server resolves endpoints (and may register a client) from this issuer. Not persisted.
    public var issuer: String?
    public var personServerMode: ConnectorPersonServerMode?
    public var personServerUrl: String?
    public var approvalPolicy: ConnectorApprovalPolicy?
    public var applicationId: String?
    public var assertionAudience: String?
    public var webhookUrl: String?

    public init(
        name: String, provider: String, authMode: ConnectorAuthMode, slug: String? = nil,
        environment: RuntimeEnvironment? = nil, agentMemberId: String? = nil, authorizationEndpoint: String? = nil,
        tokenEndpoint: String? = nil, scopes: [String]? = nil, apiHosts: [String]? = nil, clientId: String? = nil,
        clientSecret: String? = nil, signingSecret: String? = nil, metadata: JSONObject? = nil, issuer: String? = nil,
        personServerMode: ConnectorPersonServerMode? = nil, personServerUrl: String? = nil,
        approvalPolicy: ConnectorApprovalPolicy? = nil, applicationId: String? = nil,
        assertionAudience: String? = nil, webhookUrl: String? = nil
    ) {
        self.name = name
        self.provider = provider
        self.authMode = authMode
        self.slug = slug
        self.environment = environment
        self.agentMemberId = agentMemberId
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.scopes = scopes
        self.apiHosts = apiHosts
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.signingSecret = signingSecret
        self.metadata = metadata
        self.issuer = issuer
        self.personServerMode = personServerMode
        self.personServerUrl = personServerUrl
        self.approvalPolicy = approvalPolicy
        self.applicationId = applicationId
        self.assertionAudience = assertionAudience
        self.webhookUrl = webhookUrl
    }

    private enum CodingKeys: String, CodingKey {
        case name, provider, slug, environment, scopes, metadata, issuer
        case authMode = "auth_mode"
        case agentMemberId = "agent_member_id"
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case apiHosts = "api_hosts"
        case clientId = "client_id"
        case clientSecret = "client_secret"
        case signingSecret = "signing_secret"
        case personServerMode = "person_server_mode"
        case personServerUrl = "person_server_url"
        case approvalPolicy = "approval_policy"
        case applicationId = "application_id"
        case assertionAudience = "assertion_audience"
        case webhookUrl = "webhook_url"
    }
}

/// Body of `PATCH /v1/connectors/{id}`. Only provided fields change; an omitted secret is left unchanged.
public struct ConnectorUpdate: Encodable, Sendable, Hashable {
    public var name: String?
    public var agentMemberId: String?
    public var scopes: [String]?
    public var apiHosts: [String]?
    public var status: ConnectorStatus?
    public var metadata: JSONObject?
    public var webhookUrl: String?
    public var clientSecret: String?
    public var signingSecret: String?

    public init(
        name: String? = nil, agentMemberId: String? = nil, scopes: [String]? = nil, apiHosts: [String]? = nil,
        status: ConnectorStatus? = nil, metadata: JSONObject? = nil, webhookUrl: String? = nil,
        clientSecret: String? = nil, signingSecret: String? = nil
    ) {
        self.name = name
        self.agentMemberId = agentMemberId
        self.scopes = scopes
        self.apiHosts = apiHosts
        self.status = status
        self.metadata = metadata
        self.webhookUrl = webhookUrl
        self.clientSecret = clientSecret
        self.signingSecret = signingSecret
    }

    private enum CodingKeys: String, CodingKey {
        case name, scopes, status, metadata
        case agentMemberId = "agent_member_id"
        case apiHosts = "api_hosts"
        case webhookUrl = "webhook_url"
        case clientSecret = "client_secret"
        case signingSecret = "signing_secret"
    }
}

/// Paging for `GET /v1/connectors`.
public struct ConnectorListParams: Sendable, Hashable {
    /// Project slug or id; defaults to the credential's project.
    public var project: String?
    public var limit: Int?
    public var next: String?

    public init(project: String? = nil, limit: Int? = nil, next: String? = nil) {
        self.project = project
        self.limit = limit
        self.next = next
    }
}

/// An application in a provider's (or the open MCP registry's) catalogue.
public struct ConnectorApp: Codable, Sendable, Hashable {
    /// The slug `authorize(app:)` accepts.
    public var slug: String
    public var name: String?
    public var iconUrl: String?
    public var description: String?
    public var authType: String?
    /// The listing's MCP server URL, where it has one.
    public var mcpUrl: String?
    public var docsUrl: String?

    public init(
        slug: String, name: String? = nil, iconUrl: String? = nil, description: String? = nil, authType: String? = nil,
        mcpUrl: String? = nil, docsUrl: String? = nil
    ) {
        self.slug = slug
        self.name = name
        self.iconUrl = iconUrl
        self.description = description
        self.authType = authType
        self.mcpUrl = mcpUrl
        self.docsUrl = docsUrl
    }

    private enum CodingKeys: String, CodingKey {
        case slug, name, description
        case iconUrl = "icon_url"
        case authType = "auth_type"
        case mcpUrl = "mcp_url"
        case docsUrl = "docs_url"
    }
}

/// How the platform identified itself to a custom OAuth provider.
public struct ConnectorClientRegistration: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let clientIdMetadataDocument: ConnectorClientRegistration = "client_id_metadata_document"
    public static let dynamic: ConnectorClientRegistration = "dynamic"
    public static let preRegistered: ConnectorClientRegistration = "pre_registered"
}

/// What OAuth discovery learned about a provider, plus any client it registered.
public struct ConnectorOAuthDiscovery: Codable, Sendable, Hashable {
    public var issuer: String?
    public var authorizationEndpoint: String?
    public var tokenEndpoint: String?
    public var registrationEndpoint: String?
    public var tokenEndpointAuthMethodsSupported: [String]?
    public var codeChallengeMethodsSupported: [String]?
    public var scopesSupported: [String]?
    public var clientIdMetadataDocumentSupported: Bool?
    /// RFC 9728 resource identifier when discovery started at an MCP server.
    public var resource: String?
    /// The callback this deployment sends; register it exactly on a hand-made client.
    public var redirectUri: String?
    /// Set when discovery registered a client: pass it to `create` so a second one is not registered.
    public var clientId: String?
    public var clientSecret: String?
    public var clientRegistration: ConnectorClientRegistration?

    public init(
        issuer: String? = nil, authorizationEndpoint: String? = nil, tokenEndpoint: String? = nil,
        registrationEndpoint: String? = nil, tokenEndpointAuthMethodsSupported: [String]? = nil,
        codeChallengeMethodsSupported: [String]? = nil, scopesSupported: [String]? = nil,
        clientIdMetadataDocumentSupported: Bool? = nil, resource: String? = nil, redirectUri: String? = nil,
        clientId: String? = nil, clientSecret: String? = nil, clientRegistration: ConnectorClientRegistration? = nil
    ) {
        self.issuer = issuer
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.registrationEndpoint = registrationEndpoint
        self.tokenEndpointAuthMethodsSupported = tokenEndpointAuthMethodsSupported
        self.codeChallengeMethodsSupported = codeChallengeMethodsSupported
        self.scopesSupported = scopesSupported
        self.clientIdMetadataDocumentSupported = clientIdMetadataDocumentSupported
        self.resource = resource
        self.redirectUri = redirectUri
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.clientRegistration = clientRegistration
    }

    private enum CodingKeys: String, CodingKey {
        case issuer, resource
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case registrationEndpoint = "registration_endpoint"
        case tokenEndpointAuthMethodsSupported = "token_endpoint_auth_methods_supported"
        case codeChallengeMethodsSupported = "code_challenge_methods_supported"
        case scopesSupported = "scopes_supported"
        case clientIdMetadataDocumentSupported = "client_id_metadata_document_supported"
        case redirectUri = "redirect_uri"
        case clientId = "client_id"
        case clientSecret = "client_secret"
        case clientRegistration = "client_registration"
    }
}

/// The MCP endpoint binding a connect writes in the same transaction as the grant. Requires `runtime`.
public struct ConnectorAuthorizeBinding: Codable, Sendable, Hashable {
    public var environment: RuntimeEnvironment
    /// The recipe MCP server id this connector backs.
    public var mcpServerId: String
    /// Streamable-HTTP MCP resource URL (https).
    public var url: String
    public var name: String?
    /// Extra non-Authorization headers injected alongside the connection token.
    public var headers: [String: String]?

    public init(environment: RuntimeEnvironment, mcpServerId: String, url: String, name: String? = nil, headers: [String: String]? = nil) {
        self.environment = environment
        self.mcpServerId = mcpServerId
        self.url = url
        self.name = name
        self.headers = headers
    }

    private enum CodingKeys: String, CodingKey {
        case environment, url, name, headers
        case mcpServerId = "mcp_server_id"
    }
}

/// Options for minting a consent URL.
public struct ConnectorAuthorizeParams: Sendable, Hashable {
    /// Provider application slug; required for Pipedream (see `listApps`).
    public var app: String?
    /// Let the user grant a subset of the configured scopes (Pipedream).
    public var allowProgressiveScopes: Bool?
    /// The end customer the grant is for. Mints a `customer` member, so it can 409 at the member limit.
    public var identity: RunnerIdentity?
    /// Runtime group slug or id; required when `connector.requiresRuntime`.
    public var runtime: String?
    public var binding: ConnectorAuthorizeBinding?
    /// `app` (default), `user` or `person`.
    public var subject: ConnectionSubjectType?
    /// Where the browser lands after consent.
    public var returnUrl: String?
    /// Seconds the URL stays valid (60 to 86400, server default 600).
    public var expiresIn: Int?

    public init(
        app: String? = nil, allowProgressiveScopes: Bool? = nil, identity: RunnerIdentity? = nil,
        runtime: String? = nil, binding: ConnectorAuthorizeBinding? = nil, subject: ConnectionSubjectType? = nil,
        returnUrl: String? = nil, expiresIn: Int? = nil
    ) {
        self.app = app
        self.allowProgressiveScopes = allowProgressiveScopes
        self.identity = identity
        self.runtime = runtime
        self.binding = binding
        self.subject = subject
        self.returnUrl = returnUrl
        self.expiresIn = expiresIn
    }
}

struct ConnectorAuthorizeBody: Encodable {
    let connectorId: String
    let params: ConnectorAuthorizeParams

    private enum CodingKeys: String, CodingKey {
        case connectorId = "connector_id"
        case app, identity, runtime, binding, subject
        case allowProgressiveScopes = "allow_progressive_scopes"
        case returnUrl = "return_url"
        case expiresIn = "expires_in"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(connectorId, forKey: .connectorId)
        try container.encodeIfPresent(params.app, forKey: .app)
        try container.encodeIfPresent(params.allowProgressiveScopes, forKey: .allowProgressiveScopes)
        try container.encodeIfPresent(params.identity, forKey: .identity)
        try container.encodeIfPresent(params.runtime, forKey: .runtime)
        try container.encodeIfPresent(params.binding, forKey: .binding)
        try container.encodeIfPresent(params.subject, forKey: .subject)
        try container.encodeIfPresent(params.returnUrl, forKey: .returnUrl)
        try container.encodeIfPresent(params.expiresIn, forKey: .expiresIn)
    }
}

/// A freshly minted, single-use consent URL. Never cache it.
public struct ConnectorAuthorization: Codable, Sendable, Hashable {
    public var authorizeUrl: String
    public var expiresIn: Int?
    public var expiresAt: Date?

    public init(authorizeUrl: String, expiresIn: Int? = nil, expiresAt: Date? = nil) {
        self.authorizeUrl = authorizeUrl
        self.expiresIn = expiresIn
        self.expiresAt = expiresAt
    }

    private enum CodingKeys: String, CodingKey {
        case authorizeUrl = "authorize_url"
        case expiresIn = "expires_in"
        case expiresAt = "expires_at"
    }
}

// MARK: Connections

/// One authorized subject under a connector. Tokens are never returned.
public struct Connection: Codable, Sendable, Hashable {
    public var id: String
    public var orgId: String?
    public var connectorId: String?
    /// Nil for an org-owned (`app`) connection.
    public var memberId: String?
    /// The member who performed the grant, as distinct from `memberId`.
    public var createdByMemberId: String?
    /// Runtime group answering this connection's channels.
    public var runtimeGroupId: String?
    public var subjectType: ConnectionSubjectType?
    /// App slug within a multiplexing provider.
    public var providerApp: String?
    public var providerAccountId: String?
    public var scopesGranted: [String]?
    public var status: ConnectionStatus?
    public var tokenExpiresAt: Date?
    public var createdAt: Date?
    public var updatedAt: Date?

    public init(
        id: String, orgId: String? = nil, connectorId: String? = nil, memberId: String? = nil,
        createdByMemberId: String? = nil, runtimeGroupId: String? = nil, subjectType: ConnectionSubjectType? = nil,
        providerApp: String? = nil, providerAccountId: String? = nil, scopesGranted: [String]? = nil,
        status: ConnectionStatus? = nil, tokenExpiresAt: Date? = nil, createdAt: Date? = nil, updatedAt: Date? = nil
    ) {
        self.id = id
        self.orgId = orgId
        self.connectorId = connectorId
        self.memberId = memberId
        self.createdByMemberId = createdByMemberId
        self.runtimeGroupId = runtimeGroupId
        self.subjectType = subjectType
        self.providerApp = providerApp
        self.providerAccountId = providerAccountId
        self.scopesGranted = scopesGranted
        self.status = status
        self.tokenExpiresAt = tokenExpiresAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, status
        case orgId = "org_id"
        case connectorId = "connector_id"
        case memberId = "member_id"
        case createdByMemberId = "created_by_member_id"
        case runtimeGroupId = "runtime_group_id"
        case subjectType = "subject_type"
        case providerApp = "provider_app"
        case providerAccountId = "provider_account_id"
        case scopesGranted = "scopes_granted"
        case tokenExpiresAt = "token_expires_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Registered-mode create: register a provider token the caller already holds.
public struct ConnectionCreate: Encodable, Sendable, Hashable {
    public var accessToken: String
    /// `app` (default) or `user`.
    public var subjectType: ConnectionSubjectType?
    public var scopesGranted: [String]?
    public var refreshToken: String?
    public var tokenExpiresAt: Date?

    public init(
        accessToken: String, subjectType: ConnectionSubjectType? = nil, scopesGranted: [String]? = nil, refreshToken: String? = nil,
        tokenExpiresAt: Date? = nil
    ) {
        self.accessToken = accessToken
        self.subjectType = subjectType
        self.scopesGranted = scopesGranted
        self.refreshToken = refreshToken
        self.tokenExpiresAt = tokenExpiresAt
    }

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case subjectType = "subject_type"
        case scopesGranted = "scopes_granted"
        case refreshToken = "refresh_token"
        case tokenExpiresAt = "token_expires_at"
    }
}

/// Paging for a connector's connections.
public struct ConnectionListParams: Sendable, Hashable {
    public var limit: Int?
    public var next: String?

    public init(limit: Int? = nil, next: String? = nil) {
        self.limit = limit
        self.next = next
    }
}

/// Deterministic, non-PII envelope for a person-authorized action.
public struct ConnectionMissionConstraints: Codable, Sendable, Hashable {
    public var host: String?
    /// Opaque or hashed resource identifier; never raw PII.
    public var resource: String?
    public var limits: JSONObject?
    public var windowStart: Date?
    public var windowEnd: Date?
    /// SHA-256 of the approved artifact.
    public var payloadBinding: String?

    public init(
        host: String? = nil, resource: String? = nil, limits: JSONObject? = nil, windowStart: Date? = nil, windowEnd: Date? = nil,
        payloadBinding: String? = nil
    ) {
        self.host = host
        self.resource = resource
        self.limits = limits
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.payloadBinding = payloadBinding
    }

    private enum CodingKeys: String, CodingKey {
        case host, resource, limits
        case windowStart = "window_start"
        case windowEnd = "window_end"
        case payloadBinding = "payload_binding"
    }
}

/// Options for resolving a connection's provider token.
public struct ConnectionTokenParams: Sendable, Hashable {
    /// Pin one connection; defaults to the subject's.
    public var connectionId: String?
    /// `app` (default), `user` or `person`.
    public var subject: ConnectionSubjectType?
    /// Mission label shown to the human for person-authorized connectors.
    public var action: String?
    public var requestedPermissions: ConnectionMissionConstraints?

    public init(
        connectionId: String? = nil, subject: ConnectionSubjectType? = nil, action: String? = nil,
        requestedPermissions: ConnectionMissionConstraints? = nil
    ) {
        self.connectionId = connectionId
        self.subject = subject
        self.action = action
        self.requestedPermissions = requestedPermissions
    }
}

struct ConnectionTokenBody: Encodable {
    let connectorId: String
    let params: ConnectionTokenParams

    private enum CodingKeys: String, CodingKey {
        case connectorId = "connector_id"
        case connectionId = "connection_id"
        case subject, action
        case requestedPermissions = "requested_permissions"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(connectorId, forKey: .connectorId)
        try container.encodeIfPresent(params.connectionId, forKey: .connectionId)
        try container.encodeIfPresent(params.subject, forKey: .subject)
        try container.encodeIfPresent(params.action, forKey: .action)
        try container.encodeIfPresent(params.requestedPermissions, forKey: .requestedPermissions)
    }
}

/// A provider token released by the broker.
public struct ConnectionToken: Codable, Sendable, Hashable {
    public var token: String
    public var tokenType: String?
    public var expiresAt: Date?
    public var scopes: [String]?

    public init(token: String, tokenType: String? = nil, expiresAt: Date? = nil, scopes: [String]? = nil) {
        self.token = token
        self.tokenType = tokenType
        self.expiresAt = expiresAt
        self.scopes = scopes
    }

    private enum CodingKeys: String, CodingKey {
        case token, scopes
        case tokenType = "token_type"
        case expiresAt = "expires_at"
    }
}

/// The broker's answer: a token, or (for `person_authorized`) a mission awaiting human approval.
public enum ConnectionTokenResult: Codable, Sendable, Hashable {
    case token(ConnectionToken)
    case authorizationPending(missionId: String, approvalUrl: String)

    /// The token, when one was released.
    public var token: ConnectionToken? {
        if case let .token(token) = self { return token }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case status
        case missionId = "mission_id"
        case approvalUrl = "approval_url"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if try container.decodeIfPresent(String.self, forKey: .status) == "authorization_pending" {
            self = .authorizationPending(
                missionId: try container.decodeIfPresent(String.self, forKey: .missionId) ?? "",
                approvalUrl: try container.decodeIfPresent(String.self, forKey: .approvalUrl) ?? ""
            )
        } else {
            self = .token(try ConnectionToken(from: decoder))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case let .token(token):
            try token.encode(to: encoder)
        case let .authorizationPending(missionId, approvalUrl):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("authorization_pending", forKey: .status)
            try container.encode(missionId, forKey: .missionId)
            try container.encode(approvalUrl, forKey: .approvalUrl)
        }
    }
}

struct CPDataEnvelope<Item: Decodable>: Decodable {
    let data: [Item]
}

func cpProjectQuery(_ project: String?) -> Query {
    var query = Query()
    query.add("project", project)
    return query
}

// MARK: APIs

/// Connections nested under a connector (`/v1/connectors/{id}/connections`). There is no update.
public struct ConnectionsAPI: Sendable {
    let http: HTTPClient

    public init(http: HTTPClient) { self.http = http }

    private func base(_ connectorId: String) -> String {
        "/v1/connectors/\(pathSegment(connectorId))/connections"
    }

    /// List a connector's connections.
    public func list(_ connectorId: String, _ params: ConnectionListParams = ConnectionListParams()) -> Paginator<Connection> {
        var query = Query()
        query.add("limit", params.limit)
        return http.paginate(base(connectorId), query: query, start: params.next)
    }

    /// Register a connection from a token the caller already holds. For consent, use `connectors.authorize`.
    public func create(_ connectorId: String, _ body: ConnectionCreate, project: String? = nil) async throws -> Connection {
        try await http.json("POST", base(connectorId), query: cpProjectQuery(project), body: .encode(body))
    }

    /// Fetch one connection.
    public func get(_ connectorId: String, _ connectionId: String) async throws -> Connection {
        try await http.json("GET", "\(base(connectorId))/\(pathSegment(connectionId))")
    }

    /// Revoke a connection, destroying the provider token behind it; the subject must consent again.
    public func revoke(_ connectorId: String, _ connectionId: String) async throws {
        try await http.empty("DELETE", "\(base(connectorId))/\(pathSegment(connectionId))")
    }

    /// `POST /v1/oauth/connections/token`: resolve the subject's provider token, or a pending approval.
    public func getToken(
        _ connectorId: String, _ params: ConnectionTokenParams = ConnectionTokenParams(), project: String? = nil
    ) async throws -> ConnectionTokenResult {
        try await http.json(
            "POST", "/v1/oauth/connections/token", query: cpProjectQuery(project),
            body: .encode(ConnectionTokenBody(connectorId: connectorId, params: params))
        )
    }
}

/// CRUD on `/v1/connectors`, catalogue search, OAuth discovery and consent URLs.
/// Connector routes use the credential's project unless `project` is given.
public struct ConnectorsAPI: Sendable {
    let http: HTTPClient

    public init(http: HTTPClient) { self.http = http }

    /// Connections nested under a connector.
    public var connections: ConnectionsAPI { ConnectionsAPI(http: http) }

    /// List connectors.
    public func list(_ params: ConnectorListParams = ConnectorListParams()) -> Paginator<Connector> {
        var query = cpProjectQuery(params.project)
        query.add("limit", params.limit)
        return http.paginate("/v1/connectors", query: query, start: params.next)
    }

    /// Create a connector. Upserts on `slug`, keeping the live row's provider, auth mode and secrets.
    public func create(_ body: ConnectorCreate, project: String? = nil) async throws -> Connector {
        try await http.json("POST", "/v1/connectors", query: cpProjectQuery(project), body: .encode(body))
    }

    /// Fetch one connector.
    public func get(_ connectorId: String, project: String? = nil) async throws -> Connector {
        try await http.json("GET", "/v1/connectors/\(pathSegment(connectorId))", query: cpProjectQuery(project))
    }

    /// Update a connector.
    public func update(_ connectorId: String, _ body: ConnectorUpdate, project: String? = nil) async throws -> Connector {
        try await http.json("PATCH", "/v1/connectors/\(pathSegment(connectorId))", query: cpProjectQuery(project), body: .encode(body))
    }

    /// Soft-delete a connector; the server revokes its connections.
    public func delete(_ connectorId: String, project: String? = nil) async throws {
        try await http.empty("DELETE", "/v1/connectors/\(pathSegment(connectorId))", query: cpProjectQuery(project))
    }

    /// Search a connector's provider app catalogue (Pipedream today).
    public func listApps(
        _ connectorId: String, query search: String? = nil, limit: Int? = nil, project: String? = nil
    ) async throws -> [ConnectorApp] {
        var query = cpProjectQuery(project)
        query.add("q", search)
        query.add("limit", limit)
        let envelope = try await http.json(
            "GET", "/v1/connectors/\(pathSegment(connectorId))/apps", query: query, as: CPDataEnvelope<ConnectorApp>.self
        )
        return envelope.data
    }

    /// Search the open MCP registry a custom connector picks from (`query` is 2 to 100 characters).
    public func searchCustomApps(query search: String, limit: Int? = nil) async throws -> [ConnectorApp] {
        var query = Query()
        query.add("q", search)
        query.add("limit", limit)
        let envelope = try await http.json("GET", "/v1/connectors/custom/apps", query: query, as: CPDataEnvelope<ConnectorApp>.self)
        return envelope.data
    }

    /// Resolve a provider's OAuth metadata from an issuer or MCP server URL. May register an OAuth client:
    /// pass its `clientId`/`clientSecret` to `create`. Fails with a validation error when discovery fails.
    public func discoverOAuth(issuer: String, project: String? = nil) async throws -> ConnectorOAuthDiscovery {
        try await http.json(
            "POST", "/v1/connectors/discover-oauth", query: cpProjectQuery(project), body: .encode(["issuer": issuer])
        )
    }

    /// `POST /v1/oauth/connections/authorize`: mint a single-use consent URL a business hands its customer.
    public func authorize(
        _ connectorId: String, _ params: ConnectorAuthorizeParams = ConnectorAuthorizeParams(), project: String? = nil
    ) async throws -> ConnectorAuthorization {
        try await http.json(
            "POST", "/v1/oauth/connections/authorize", query: cpProjectQuery(project),
            body: .encode(ConnectorAuthorizeBody(connectorId: connectorId, params: params))
        )
    }
}

extension IntrospectionClient {
    /// Connectors, their connections, consent URLs and the connection token broker.
    public var connectors: ConnectorsAPI { ConnectorsAPI(http: controlPlane) }
}
