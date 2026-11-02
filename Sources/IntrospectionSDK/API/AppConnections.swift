import Foundation

/// Who holds an app connection.
public struct AppConnectionOwner: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let member: AppConnectionOwner = "member"
    public static let project: AppConnectionOwner = "project"
}

/// The connector an app connection is on, as the project sees it.
public struct AppConnectionConnector: Codable, Sendable, Hashable {
    public var id: String
    public var slug: String
    public var provider: String
    /// The peering the project reaches the connector through, if any.
    public var peering: String?

    public init(id: String, slug: String, provider: String, peering: String? = nil) {
        self.id = id
        self.slug = slug
        self.provider = provider
        self.peering = peering
    }
}

/// Filters for `GET /v1/connections`.
public struct AppConnectionListParams: Sendable, Hashable {
    /// An administrator's view of another member's connections.
    public var memberId: String?
    public var app: String?
    public var connectorId: String?
    public var subjectType: ConnectionSubjectType?
    public var peering: String?
    public var limit: Int?
    public var next: String?

    public init(
        memberId: String? = nil, app: String? = nil, connectorId: String? = nil, subjectType: ConnectionSubjectType? = nil,
        peering: String? = nil, limit: Int? = nil, next: String? = nil
    ) {
        self.memberId = memberId
        self.app = app
        self.connectorId = connectorId
        self.subjectType = subjectType
        self.peering = peering
        self.limit = limit
        self.next = next
    }
}

/// One connection a project's members can see (`/v1/connections`): an app a member connected for themself, or a grant
/// the project holds. Named apart from the Control Plane's
/// ``Connection``, which is a connector's authorized subject.
public struct AppConnection: Codable, Sendable, Hashable {
    public var id: String
    /// The member who connected the app; nil for a connection the project owns.
    public var memberId: String?
    /// Provider application slug, such as `gmail`.
    public var app: String
    /// The provider account the app is connected as, when the provider names one.
    public var accountName: String?
    /// False when the provider no longer accepts the connection; connect the app again.
    public var healthy: Bool
    public var createdAt: Date
    public var owner: AppConnectionOwner?
    public var connector: AppConnectionConnector?
    public var subjectType: ConnectionSubjectType?
    public var providerAccountId: String?
    public var status: ConnectionStatus?
    public var lastVerifiedAt: Date?
    public var createdByMemberId: String?
    public var updatedAt: Date?

    public init(id: String, memberId: String?, app: String, healthy: Bool, createdAt: Date, accountName: String? = nil) {
        self.id = id
        self.app = app
        self.memberId = memberId
        self.accountName = accountName
        self.healthy = healthy
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, app, healthy, owner, connector, status
        case memberId = "member_id"
        case accountName = "account_name"
        case createdAt = "created_at"
        case subjectType = "subject_type"
        case providerAccountId = "provider_account_id"
        case lastVerifiedAt = "last_verified_at"
        case createdByMemberId = "created_by_member_id"
        case updatedAt = "updated_at"
    }
}

/// A single-use connect page for one app. Open it in a browser and never cache it; it ends on the `returnURL`
/// it was created with, or on a page saying the app is connected.
public struct ConnectPage: Codable, Sendable, Hashable {
    public var authorizeUrl: String
    /// Seconds until the page stops working.
    public var expiresIn: Int
    public var expiresAt: Date?

    public init(authorizeUrl: String, expiresIn: Int, expiresAt: Date? = nil) {
        self.authorizeUrl = authorizeUrl
        self.expiresIn = expiresIn
        self.expiresAt = expiresAt
    }

    enum CodingKeys: String, CodingKey {
        case authorizeUrl = "authorize_url"
        case expiresIn = "expires_in"
        case expiresAt = "expires_at"
    }
}

/// Body of `POST /v1/connections`.
struct AppConnectionCreate: Encodable, Sendable, Hashable {
    var app: String
    var runtime: String
    var returnUrl: String?

    enum CodingKeys: String, CodingKey {
        case app, runtime
        case returnUrl = "return_url"
    }
}

/// The apps members connected for themselves (`/v1/connections`), as `client.connections` or
/// `runner.connections`. Scopes `connections:read`, `connections:write` and `connections:delete`; a member who is
/// not an administrator only ever sees and changes their own.
public struct AppConnectionsAPI: Sendable {
    let http: HTTPClient
    /// The runtime ``create(app:runtime:returnURL:)`` connects for when none is passed: a runner's runtime group.
    public let defaultRuntime: String?

    public init(http: HTTPClient, defaultRuntime: String? = nil) {
        self.http = http
        self.defaultRuntime = defaultRuntime
    }

    /// List connections: the caller's own, unless an administrator names another member.
    public func list(
        memberId: String? = nil, app: String? = nil, limit: Int? = nil, next: String? = nil
    ) -> Paginator<AppConnection> {
        list(AppConnectionListParams(memberId: memberId, app: app, limit: limit, next: next))
    }

    /// List connections matching `params`.
    public func list(_ params: AppConnectionListParams) -> Paginator<AppConnection> {
        var query = Query()
        query.add("member_id", params.memberId)
        query.add("app", params.app)
        query.add("connector_id", params.connectorId)
        query.add("subject_type", params.subjectType)
        query.add("peering", params.peering)
        query.add("limit", params.limit)
        return http.paginate("/v1/connections", query: query, start: params.next)
    }

    /// A connect page for one app, for the caller themself.
    /// - Parameters:
    ///   - app: Provider application slug, such as `gmail`.
    ///   - runtime: Runtime slug or runtime group id whose sessions use the connection. Defaults to
    ///     ``defaultRuntime``, which a runner sets to its runtime group; required on the client.
    ///   - returnURL: The app's own link the page ends on, such as `ark://connected`, so a web authentication
    ///     session listening for that scheme closes itself; it arrives with `status`, `connector_id` and
    ///     `connection_id`. Web URLs are refused.
    public func create(app: String, runtime: String? = nil, returnURL: URL? = nil) async throws -> ConnectPage {
        guard let runtime = runtime ?? defaultRuntime else {
            throw IntrospectionError(
                kind: .invalidRequest,
                message: "connections.create needs a runtime: pass `runtime`, or call it on a runner whose context names its runtime group"
            )
        }
        return try await http.json(
            "POST", "/v1/connections", body: .encode(AppConnectionCreate(app: app, runtime: runtime, returnUrl: returnURL?.absoluteString)))
    }

    /// Read one connection.
    public func get(_ connectionId: String) async throws -> AppConnection {
        try await http.json("GET", "/v1/connections/\(pathSegment(connectionId))")
    }

    /// Delete one connection by id.
    public func delete(_ connectionId: String) async throws {
        try await http.empty("DELETE", "/v1/connections/\(pathSegment(connectionId))")
    }
}
