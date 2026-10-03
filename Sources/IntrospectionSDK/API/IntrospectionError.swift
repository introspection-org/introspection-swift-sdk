import Foundation

/// Every failure the SDK raises. HTTP failures carry the status, the error
/// envelope's `code`, the `x-request-id`, the decoded body and `Retry-After`.
public struct IntrospectionError: Error, Sendable, CustomStringConvertible {
    public enum Kind: Sendable, Equatable {
        /// 401: credentials missing, invalid or expired.
        case authentication
        /// 401 with `code: "runner_expired"`.
        case runnerExpired
        /// 403 with `code: "insufficient_scope"`; carries the missing capability when sent.
        case insufficientScope(missingCapability: String?)
        /// 403 for any other reason.
        case forbidden
        /// 404.
        case notFound
        /// 409.
        case conflict
        /// 400 or 422: the server rejected the request shape.
        case validation
        /// 429.
        case rateLimited
        /// 503 or 504: the sandbox or an upstream is unavailable.
        case unavailable
        /// Any other non-2xx status.
        case http
        /// No HTTP response: DNS, TLS, connection reset, timeout.
        case network
        /// A 2xx response whose body did not decode into the expected type.
        case decoding
        /// A request rejected by the SDK before it was sent.
        case invalidRequest
        /// The operation was cancelled.
        case cancelled
    }

    public let kind: Kind
    public let message: String
    /// HTTP status, or 0 when there was no response.
    public let status: Int
    public let code: String?
    public let requestId: String?
    public let body: JSONValue?
    /// The server's `Retry-After`, in seconds.
    public let retryAfter: TimeInterval?
    public let underlying: (any Error)?

    public init(
        kind: Kind,
        message: String,
        status: Int = 0,
        code: String? = nil,
        requestId: String? = nil,
        body: JSONValue? = nil,
        retryAfter: TimeInterval? = nil,
        underlying: (any Error)? = nil
    ) {
        self.kind = kind
        self.message = message
        self.status = status
        self.code = code
        self.requestId = requestId
        self.body = body
        self.retryAfter = retryAfter
        self.underlying = underlying
    }

    public var description: String {
        var parts = ["IntrospectionError(\(kind)): \(message)"]
        if status != 0 { parts.append("status=\(status)") }
        if let code { parts.append("code=\(code)") }
        if let requestId { parts.append("request_id=\(requestId)") }
        return parts.joined(separator: " ")
    }

    /// Whether this is an HTTP error with the given status.
    public func hasStatus(_ status: Int) -> Bool { self.status == status }

    /// Map a non-2xx response to the most specific error.
    public static func fromResponse(status: Int, headers: [String: String], body: Data) -> IntrospectionError {
        let decoded = try? JSONCoding.decoder.decode(JSONValue.self, from: body)
        var message = "HTTP \(status)"
        var code: String?
        if let decoded {
            if let detail = renderDetail(decoded["detail"]) { message = detail }
            code = decoded["code"]?.stringValue
            if message == "HTTP \(status)", let text = decoded["message"]?.stringValue { message = text }
            if message == "HTTP \(status)", let text = decoded["error"]?.stringValue { message = text }
        } else if let text = String(data: body, encoding: .utf8), !text.isEmpty {
            message = String(text.prefix(500))
        }
        let requestId = headers["x-request-id"]
        let retryAfter = parseRetryAfter(headers["retry-after"])
        let bodyValue = decoded ?? String(data: body, encoding: .utf8).map(JSONValue.string)
        let kind: Kind
        switch status {
        case 401: kind = code == "runner_expired" ? .runnerExpired : .authentication
        case 403:
            kind =
                code == "insufficient_scope"
                ? .insufficientScope(missingCapability: decoded?["missing_capability"]?.stringValue)
                : .forbidden
        case 404: kind = .notFound
        case 409: kind = .conflict
        case 400, 422: kind = .validation
        case 429: kind = .rateLimited
        case 503, 504: kind = .unavailable
        default: kind = .http
        }
        return IntrospectionError(
            kind: kind, message: message, status: status, code: code,
            requestId: requestId, body: bodyValue, retryAfter: retryAfter
        )
    }

    /// A validation failure's `detail` is a list of `{loc, msg}` objects.
    static func renderDetail(_ detail: JSONValue?) -> String? {
        switch detail {
        case let .string(text)?: return text
        case let .array(entries)? where !entries.isEmpty:
            return entries.map { entry -> String in
                if let text = entry.stringValue { return text }
                let location = entry["loc"]?.arrayValue?.map { item -> String in
                    item.stringValue ?? item.intValue.map(String.init) ?? ""
                }.joined(separator: ".")
                let what = entry["msg"]?.stringValue ?? "\(entry)"
                if let location, !location.isEmpty { return "\(location): \(what)" }
                return what
            }.joined(separator: "; ")
        default: return nil
        }
    }

    /// `Retry-After` as seconds, from either delta-seconds or an HTTP-date.
    static func parseRetryAfter(_ header: String?) -> TimeInterval? {
        guard let header = header?.trimmingCharacters(in: .whitespaces), !header.isEmpty else { return nil }
        if let seconds = Double(header) { return max(0, seconds) }
        for format in ["EEE, dd MMM yyyy HH:mm:ss zzz", "EEEE, dd-MMM-yy HH:mm:ss zzz", "EEE MMM d HH:mm:ss yyyy"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "GMT")
            formatter.dateFormat = format
            if let date = formatter.date(from: header) {
                return max(0, date.timeIntervalSinceNow.rounded(.up))
            }
        }
        return nil
    }
}
