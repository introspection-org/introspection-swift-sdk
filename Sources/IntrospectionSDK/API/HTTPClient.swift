import Foundation

/// The HTTP core every resource client uses: URL building, auth headers,
/// error mapping, `429` and idempotent `502/503/504` retries with
/// `Retry-After`, and one refresh-and-retry after a `401`.
public final class HTTPClient: Sendable {
    public struct Options: Sendable {
        /// Automatic retries for a retryable status. 0 disables them. Streams have their own budget.
        public var maxRetries: Int
        /// Base step (seconds) of the capped exponential retry backoff.
        public var retryBase: TimeInterval
        /// Per-request timeout for unary requests.
        public var timeout: TimeInterval?
        /// Headers merged into every request.
        public var additionalHeaders: [String: String]

        public init(
            maxRetries: Int = 2, retryBase: TimeInterval = 0.5, timeout: TimeInterval? = 60, additionalHeaders: [String: String] = [:]
        ) {
            self.maxRetries = maxRetries
            self.retryBase = retryBase
            self.timeout = timeout
            self.additionalHeaders = additionalHeaders
        }
    }

    public let baseURL: URL
    public let credentials: (any CredentialProvider)?
    public let transport: any HTTPTransport
    public let options: Options

    public init(
        baseURL: URL,
        credentials: (any CredentialProvider)? = nil,
        transport: any HTTPTransport = URLSessionTransport(),
        options: Options = Options()
    ) {
        self.baseURL = baseURL
        self.credentials = credentials
        self.transport = transport
        self.options = options
    }

    /// A copy with different credentials (for example a runner's token on the same plane).
    public func with(credentials: (any CredentialProvider)?) -> HTTPClient {
        HTTPClient(baseURL: baseURL, credentials: credentials, transport: transport, options: options)
    }

    /// A copy pointed at another base URL.
    public func with(baseURL: URL, credentials: (any CredentialProvider)?) -> HTTPClient {
        HTTPClient(baseURL: baseURL, credentials: credentials, transport: transport, options: options)
    }

    // MARK: URLs

    public func url(_ path: String, query: Query = Query()) -> URL {
        var base = baseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        let suffix = path.hasPrefix("/") ? path : "/\(path)"
        var components = URLComponents(string: base + suffix)!
        if !query.items.isEmpty {
            components.percentEncodedQueryItems = query.items.map {
                URLQueryItem(name: Self.queryEncode($0.name), value: $0.value.map(Self.queryEncode))
            }
        }
        return components.url!
    }

    private static func queryEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    // MARK: Unary requests

    /// Send a request and return the raw response, throwing on a non-2xx status.
    @discardableResult
    public func send(
        _ method: String,
        _ path: String,
        query: Query = Query(),
        body: RequestBody = .none,
        headers: [String: String] = [:],
        authenticated: Bool = true
    ) async throws -> HTTPResponse {
        let url = url(path, query: query)
        let (data, contentType) = body.encoded()
        let maxRetries = body.isMultipart ? 0 : options.maxRetries
        var attempt = 0
        while true {
            do {
                return try await sendOnce(
                    method: method, url: url, data: data, contentType: contentType,
                    headers: headers, authenticated: authenticated
                )
            } catch let error as IntrospectionError {
                let retryable =
                    error.kind == .rateLimited
                    || (method == "GET" && [502, 503, 504].contains(error.status))
                guard retryable, attempt < maxRetries else { throw error }
                try await Backoff.sleep(Backoff.delay(attempt: attempt, retryAfter: error.retryAfter, base: options.retryBase))
                attempt += 1
            }
        }
    }

    private func sendOnce(
        method: String, url: URL, data: Data?, contentType: String?,
        headers: [String: String], authenticated: Bool
    ) async throws -> HTTPResponse {
        var (response, sent) = try await perform(
            method: method, url: url, data: data, contentType: contentType, headers: headers, authenticated: authenticated)
        if response.status == 401, authenticated, let credentials,
            try await credentials.refreshAfterUnauthorized(rejected: sent)
        {
            (response, sent) = try await perform(
                method: method, url: url, data: data, contentType: contentType, headers: headers, authenticated: authenticated)
        }
        guard response.isSuccess else {
            throw IntrospectionError.fromResponse(status: response.status, headers: response.headers, body: response.body)
        }
        return response
    }

    private func perform(
        method: String, url: URL, data: Data?, contentType: String?,
        headers: [String: String], authenticated: Bool
    ) async throws -> (HTTPResponse, String?) {
        // Rebuilt per attempt: a refresh exists precisely to change the header.
        let request = HTTPRequest(
            method: method, url: url,
            headers: try await buildHeaders(extra: headers, contentType: contentType, authenticated: authenticated),
            body: data, timeout: options.timeout
        )
        do {
            return (try await transport.send(request), request.headers["Authorization"])
        } catch let error as IntrospectionError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw IntrospectionError(kind: .network, message: error.localizedDescription, underlying: error)
        }
    }

    private func buildHeaders(extra: [String: String], contentType: String?, authenticated: Bool) async throws -> [String: String] {
        var headers = options.additionalHeaders
        headers["Accept"] = headers["Accept"] ?? "application/json"
        if authenticated, let authorization = try await credentials?.authorization() {
            headers["Authorization"] = authorization
        }
        if let contentType { headers["Content-Type"] = contentType }
        for (name, value) in extra { headers[name] = value }
        return headers
    }

    /// Send a request and decode the JSON response.
    public func json<T: Decodable>(
        _ method: String,
        _ path: String,
        query: Query = Query(),
        body: RequestBody = .none,
        headers: [String: String] = [:],
        authenticated: Bool = true,
        as _: T.Type = T.self
    ) async throws -> T {
        let response = try await send(method, path, query: query, body: body, headers: headers, authenticated: authenticated)
        return try Self.decode(T.self, from: response)
    }

    /// Send a request whose response body is ignored (`204` and similar).
    public func empty(
        _ method: String,
        _ path: String,
        query: Query = Query(),
        body: RequestBody = .none,
        headers: [String: String] = [:]
    ) async throws {
        try await send(method, path, query: query, body: body, headers: headers)
    }

    /// Send a request and return the raw body bytes.
    public func data(
        _ method: String,
        _ path: String,
        query: Query = Query(),
        headers: [String: String] = [:]
    ) async throws -> Data {
        try await send(method, path, query: query, headers: headers).body
    }

    public static func decode<T: Decodable>(_ type: T.Type, from response: HTTPResponse) throws -> T {
        do {
            return try JSONCoding.decoder.decode(T.self, from: response.body.isEmpty ? Data("null".utf8) : response.body)
        } catch {
            throw IntrospectionError(
                kind: .decoding,
                message: "Could not decode \(T.self): \(error)",
                status: response.status,
                requestId: response.headers["x-request-id"],
                underlying: error
            )
        }
    }

    // MARK: Streaming

    /// Open a streaming response (Server-Sent Events, or a large download),
    /// throwing on a non-2xx status. A 401 refreshes and retries once.
    public func stream(
        _ method: String = "GET",
        _ path: String,
        query: Query = Query(),
        body: RequestBody = .none,
        headers: [String: String] = [:]
    ) async throws -> HTTPStreamResponse {
        let url = url(path, query: query)
        let (data, contentType) = body.encoded()
        var (response, sent) = try await openStream(
            method: method, url: url, data: data, contentType: contentType, headers: headers)
        if response.status == 401, let credentials, try await credentials.refreshAfterUnauthorized(rejected: sent) {
            (response, sent) = try await openStream(
                method: method, url: url, data: data, contentType: contentType, headers: headers)
        }
        guard (200..<300).contains(response.status) else {
            let body = (try? await response.collect()) ?? Data()
            throw IntrospectionError.fromResponse(status: response.status, headers: response.headers, body: body)
        }
        return response
    }

    private func openStream(
        method: String, url: URL, data: Data?, contentType: String?, headers: [String: String]
    ) async throws -> (HTTPStreamResponse, String?) {
        var merged = try await buildHeaders(extra: [:], contentType: contentType, authenticated: true)
        merged["Accept"] = "text/event-stream"
        for (name, value) in headers { merged[name] = value }
        let request = HTTPRequest(method: method, url: url, headers: merged, body: data, timeout: nil)
        do {
            return (try await transport.stream(request), request.headers["Authorization"])
        } catch let error as IntrospectionError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw IntrospectionError(kind: .network, message: error.localizedDescription, underlying: error)
        }
    }
}
