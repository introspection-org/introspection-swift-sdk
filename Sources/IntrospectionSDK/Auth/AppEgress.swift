import Foundation

/// A member's app reaching its project's app-routed endpoints through the platform's
/// app egress entry, `egress.<dp>/<route>/…`.
///
/// The app holds only the member's short-lived access token. The egress verifies it,
/// injects the endpoint's own credential (an API key, or an identity assertion that tells
/// the backend who the member is) and forwards to the one host the runtime routes `route`
/// to. The token never reaches that host. Each request uses the session's current token,
/// renewed ahead of expiry by ``AuthClient``, and a `401` renews it once and retries.
public struct AppEgress: Sendable {
    /// The header naming the runtime group whose app-routed endpoints a request reaches.
    public static let runtimeHeader = "introspection-runtime"

    public let auth: AuthClient
    /// The egress origin, `https://egress.<dp>`.
    public let egressURL: URL
    /// The runtime group, by slug or id.
    public let runtime: String
    private let transport: any HTTPTransport

    public init(auth: AuthClient, egressURL: URL, runtime: String, transport: (any HTTPTransport)? = nil) {
        self.auth = auth
        self.egressURL = egressURL
        self.runtime = runtime
        self.transport = transport ?? auth.configuration.transport
    }

    /// The egress origin for a Data Plane API URL: `https://api.<dp>` becomes `https://egress.<dp>`.
    /// Nil for a URL that does not start with an `api.` host.
    public static func egressURL(forDataPlane dataPlaneURL: URL) -> URL? {
        guard var components = URLComponents(url: dataPlaneURL, resolvingAgainstBaseURL: false),
            let host = components.host, host.hasPrefix("api."), host.count > 4
        else { return nil }
        components.host = "egress." + host.dropFirst(4)
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url
    }

    /// Send a request to `route`'s endpoint. `path` is the endpoint's own path, with any query.
    ///
    /// Returns the endpoint's response whatever its status, except a `401` that survives one
    /// token renewal, which throws `.authentication`: the member's sign-in has ended or
    /// their token cannot reach this route.
    public func send(
        _ route: String,
        path: String = "/",
        method: String = "POST",
        headers: [String: String] = [:],
        body: Data? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> HTTPResponse {
        guard Self.isRoute(route) else {
            throw IntrospectionError(kind: .invalidRequest, message: "Invalid app route: \(route)")
        }
        guard let url = Self.url(egressURL, route: route, path: path) else {
            throw IntrospectionError(kind: .invalidRequest, message: "Invalid app egress path: \(path)")
        }
        guard let session = try await auth.session else {
            throw IntrospectionError(kind: .authentication, message: "Not signed in")
        }
        let first = try await transport.send(
            request(method: method, url: url, headers: headers, body: body, timeout: timeout, token: session.accessToken))
        guard first.status == 401 else { return first }
        let renewed = try await auth.refreshSession()
        let second = try await transport.send(
            request(method: method, url: url, headers: headers, body: body, timeout: timeout, token: renewed.accessToken))
        guard second.status == 401 else { return second }
        throw IntrospectionError(
            kind: .authentication, message: "The app egress refused the member's token", status: second.status)
    }

    private func request(
        method: String, url: URL, headers: [String: String], body: Data?, timeout: TimeInterval?, token: String
    ) -> HTTPRequest {
        var merged = headers.filter { key, _ in
            let name = key.lowercased()
            return name != "authorization" && name != Self.runtimeHeader
        }
        merged["Authorization"] = "Bearer \(token)"
        merged[Self.runtimeHeader] = runtime
        return HTTPRequest(method: method, url: url, headers: merged, body: body, timeout: timeout)
    }

    /// An `app_route` slug: lowercase letters, digits and inner hyphens, at most 63 characters.
    static func isRoute(_ route: String) -> Bool {
        guard (1...63).contains(route.count), route.first != "-", route.last != "-" else { return false }
        return route.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
    }

    static func url(_ base: URL, route: String, path: String) -> URL? {
        let rest = path.isEmpty ? "/" : (path.hasPrefix("/") || path.hasPrefix("?") ? path : "/" + path)
        let origin = base.absoluteString.hasSuffix("/") ? String(base.absoluteString.dropLast()) : base.absoluteString
        return URL(string: "\(origin)/\(route)\(rest.hasPrefix("?") ? "/" + rest : rest)")
    }
}

extension AuthClient {
    /// The app egress for `runtime`, at `egressURL` or else the session Data Plane's `egress.` host.
    public func appEgress(runtime: String, egressURL: URL? = nil) async throws -> AppEgress {
        if let egressURL { return AppEgress(auth: self, egressURL: egressURL, runtime: runtime) }
        guard let dataPlaneURL = try await session?.dataPlaneURL,
            let derived = AppEgress.egressURL(forDataPlane: dataPlaneURL)
        else {
            throw IntrospectionError(
                kind: .invalidRequest, message: "No app egress URL: the session names no api. Data Plane host")
        }
        return AppEgress(auth: self, egressURL: derived, runtime: runtime)
    }
}
