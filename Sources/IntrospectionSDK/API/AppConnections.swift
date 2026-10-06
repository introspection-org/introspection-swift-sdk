import Foundation

/// One app a member connected for themself (`/v1/connections`). Named apart from the Control Plane's
/// ``Connection``, which is a connector's authorized subject.
public struct AppConnection: Codable, Sendable, Hashable {
    public var id: String
    /// The member who connected the app.
    public var memberId: String
    /// Provider application slug, such as `gmail`.
    public var app: String
    /// The provider account the app is connected as, when the provider names one.
    public var accountName: String?
    /// False when the provider no longer accepts the connection; connect the app again.
    public var healthy: Bool
    public var createdAt: Date

    public init(id: String, memberId: String, app: String, healthy: Bool, createdAt: Date, accountName: String? = nil) {
        self.id = id
        self.app = app
        self.memberId = memberId
        self.accountName = accountName
        self.healthy = healthy
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, app, healthy
        case memberId = "member_id"
        case accountName = "account_name"
        case createdAt = "created_at"
    }
}

/// A single-use connect page for one app. Open it in a browser and never cache it; it ends on a page saying
/// the app is connected.
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
}

/// The apps members connected for themselves (`/v1/connections`), as `client.connections` or
/// `runner.connections`. Scopes `connections:read`, `connections:write` and `connections:delete`; a member who is
/// not an administrator only ever sees and changes their own.
public struct AppConnectionsAPI: Sendable {
    let http: HTTPClient
    /// The runtime ``create(app:runtime:)`` connects for when none is passed: a runner's runtime group.
    public let defaultRuntime: String?

    public init(http: HTTPClient, defaultRuntime: String? = nil) {
        self.http = http
        self.defaultRuntime = defaultRuntime
    }

    /// List connections: the caller's own, unless an administrator names another member.
    public func list(
        memberId: String? = nil, app: String? = nil, limit: Int? = nil, next: String? = nil
    ) -> Paginator<AppConnection> {
        var query = Query()
        query.add("member_id", memberId)
        query.add("app", app)
        query.add("limit", limit)
        return http.paginate("/v1/connections", query: query, start: next)
    }

    /// A connect page for one app, for the caller themself.
    /// - Parameters:
    ///   - app: Provider application slug, such as `gmail`.
    ///   - runtime: Runtime slug or runtime group id whose sessions use the connection. Defaults to
    ///     ``defaultRuntime``, which a runner sets to its runtime group; required on the client.
    public func create(app: String, runtime: String? = nil) async throws -> ConnectPage {
        guard let runtime = runtime ?? defaultRuntime else {
            throw IntrospectionError(
                kind: .invalidRequest,
                message: "connections.create needs a runtime: pass `runtime`, or call it on a runner whose context names its runtime group"
            )
        }
        return try await http.json("POST", "/v1/connections", body: .encode(AppConnectionCreate(app: app, runtime: runtime)))
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
