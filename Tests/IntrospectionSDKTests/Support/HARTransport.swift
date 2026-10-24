import Foundation
import Synchronization

@testable import IntrospectionSDK

/// A transport that replays a HAR recording, or records one through `URLSessionTransport`.
///
/// Replay matches a request on its method, its URL (scheme, host, port, path, and the query as a
/// set of name/value pairs) and its body compared as parsed JSON, form fields or multipart parts,
/// never on headers. Identical requests are answered in the order they were recorded. A request
/// with no recorded answer fails loudly, naming what was sent and how it differs from the closest
/// recorded requests: that is the signal the SDK changed what it sends.
final class HARTransport: HTTPTransport {
    enum Mode: String {
        case replay, record, passthrough
    }

    struct Miss: Error, CustomStringConvertible {
        let method: String
        let url: String
        let detail: String
        var description: String { "\(method) \(url): \(detail)" }
    }

    private struct State {
        var entries: [HAR.Entry?] = []
        var consumed: [Bool] = []
        var misses: [Miss] = []
    }

    let mode: Mode
    private let upstream: URLSessionTransport?
    /// For requests carrying ``ManualRedirect/header``: a session that returns redirects instead of following them.
    private let manualRedirects: (any HTTPTransport)?
    private let state: Mutex<State>

    /// Replay `har`.
    init(replaying har: HAR) {
        mode = .replay
        upstream = nil
        manualRedirects = nil
        state = Mutex(State(entries: har.log.entries, consumed: Array(repeating: false, count: har.log.entries.count)))
    }

    /// Send every request to the network, keeping a recording when `mode` is `.record`.
    init(live mode: Mode) {
        precondition(mode != .replay, "a live transport records or passes through")
        self.mode = mode
        upstream = URLSessionTransport()
        manualRedirects = ManualRedirect.transport()
        state = Mutex(State())
    }

    /// The requests no recorded entry answered.
    var misses: [Miss] { state.withLock { $0.misses } }

    /// Recorded entries in total, and how many replay answered.
    var consumption: (total: Int, consumed: Int) {
        state.withLock { ($0.entries.count, $0.consumed.filter { $0 }.count) }
    }

    /// The recorded entries replay never answered, in order.
    var unconsumed: [(method: String, url: String)] {
        state.withLock { state in
            state.entries.indices.compactMap { index in
                guard !state.consumed[index], let entry = state.entries[index] else { return nil }
                return (entry.request.method, entry.request.url)
            }
        }
    }

    // MARK: HTTPTransport

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        guard let upstream else {
            let entry = try replay(request)
            return HTTPResponse(status: entry.response.status, headers: entry.response.headerMap, body: entry.response.content.data)
        }
        let slot = reserve()
        let live: any HTTPTransport = request.headers[ManualRedirect.header] != nil ? (manualRedirects ?? upstream) : upstream
        let response = try await live.send(request)
        if let slot { fill(slot, request: request, status: response.status, headers: response.headers, body: response.body) }
        return response
    }

    func stream(_ request: HTTPRequest) async throws -> HTTPStreamResponse {
        guard let upstream else {
            let entry = try replay(request)
            let body = entry.response.content.data
            return HTTPStreamResponse(
                status: entry.response.status, headers: entry.response.headerMap,
                bytes: AsyncThrowingStream { continuation in
                    continuation.yield(body)
                    continuation.finish()
                })
        }
        let slot = reserve()
        let response = try await upstream.stream(request)
        guard let slot else { return response }
        let (bytes, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
        let pump = Task { [self] in
            var body = Data()
            do {
                for try await chunk in response.bytes {
                    body.append(chunk)
                    continuation.yield(chunk)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
            fill(slot, request: request, status: response.status, headers: response.headers, body: body)
        }
        continuation.onTermination = { _ in pump.cancel() }
        return HTTPStreamResponse(status: response.status, headers: response.headers, bytes: bytes)
    }

    // MARK: Replay

    private func replay(_ request: HTTPRequest) throws -> HAR.Entry {
        let sent = RecordedRequest(request)
        let outcome: Result<HAR.Entry, Miss> = state.withLock { state in
            for index in state.entries.indices where !state.consumed[index] {
                guard let entry = state.entries[index], sent.matches(RecordedRequest(entry.request)) else { continue }
                state.consumed[index] = true
                return .success(entry)
            }
            let candidates = state.entries.indices.compactMap { index -> RecordedRequest? in
                guard !state.consumed[index], let entry = state.entries[index] else { return nil }
                let recorded = RecordedRequest(entry.request)
                return recorded.method == sent.method && recorded.route == sent.route ? recorded : nil
            }
            let miss = Miss(method: sent.method, url: request.url.absoluteString, detail: sent.explainMiss(against: candidates))
            state.misses.append(miss)
            return .failure(miss)
        }
        switch outcome {
        case let .success(entry): return entry
        case let .failure(miss): throw ReplayMiss(miss: miss)
        }
    }

    // MARK: Record

    private func reserve() -> Int? {
        guard mode == .record else { return nil }
        return state.withLock { state in
            state.entries.append(nil)
            state.consumed.append(false)
            return state.entries.count - 1
        }
    }

    private func fill(_ slot: Int, request: HTTPRequest, status: Int, headers: [String: String], body: Data) {
        let contentType = headers["content-type"]
        let isText = contentType.map { $0.contains("json") || $0.hasPrefix("text/") || $0.contains("x-www-form-urlencoded") } ?? true
        let requestType = request.headers.first { $0.key.lowercased() == "content-type" }?.value
        let entry = HAR.Entry(
            startedDateTime: ISO8601.format(Date()),
            request: HAR.Request(
                method: request.method,
                url: request.url.absoluteString,
                headers: request.headers.sorted { $0.key < $1.key }.map { HAR.Header(name: $0.key.lowercased(), value: $0.value) },
                queryString: (URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map {
                    HAR.Header(name: $0.name, value: $0.value ?? "")
                },
                postData: request.body.map { HAR.PostData(mimeType: requestType, text: String(decoding: $0, as: UTF8.self)) }
            ),
            response: HAR.Response(
                status: status,
                headers: headers.sorted { $0.key < $1.key }.map { HAR.Header(name: $0.key, value: $0.value) },
                content: HAR.Content(
                    mimeType: contentType, size: body.count,
                    text: isText ? String(decoding: body, as: UTF8.self) : body.base64EncodedString(),
                    encoding: isText ? nil : "base64")
            )
        )
        state.withLock { $0.entries[slot] = Scrub.entry(entry) }
    }

    /// The recording so far, scrubbed, in request order.
    var recording: HAR {
        HAR(log: HAR.Log(entries: state.withLock { $0.entries.compactMap { $0 } }))
    }
}

/// A request with no recorded answer. HTTPClient reports it as a `.network` error whose message
/// is this description.
struct ReplayMiss: Error, LocalizedError, CustomStringConvertible {
    let miss: HARTransport.Miss
    var description: String { "No recorded response for \(miss)" }
    var errorDescription: String? { description }
}

// MARK: Matching

/// A request reduced to what replay compares.
struct RecordedRequest {
    enum Body: Equatable {
        case none
        /// Recorded with a body the HAR does not carry: Polly.js serializes no multipart text.
        case unrecorded
        case json(JSONValue)
        case form([[String]])
        case multipart([[String]])
        case text(String)
    }

    let method: String
    /// Scheme, host, port and path.
    let route: String
    /// Query name/value pairs, sorted: their order on the wire is not part of the contract.
    let query: [[String]]
    let body: Body

    init(_ request: HTTPRequest) {
        method = request.method.uppercased()
        (route, query) = Self.split(Scrub.secrets(request.url.absoluteString))
        let contentType = request.headers.first { $0.key.lowercased() == "content-type" }?.value
        let sent = request.body.map { Self.body(Scrub.secrets(String(decoding: $0, as: UTF8.self)), contentType: contentType) } ?? .none
        body = Self.normalised(sent, route: "\(method) \(request.url.path)")
    }

    /// Body keys the server reads under two names, one SDK sending one and another the other. Each is narrow
    /// (one route, one key) and documented server-side, so matching still pins everything else the SDK sends.
    private static let aliases: [String: [String: String]] = [
        // `ExperimentCreate.runtime_group_id` takes `validation_alias=AliasChoices("runtime", "runtime_group_id")`.
        "POST /v1/experiments": ["runtime": "runtime_group_id"]
    ]

    /// Body fields one SDK sends at the server's default and another omits. Equally narrow.
    private static let defaults: [String: JSONObject] = [
        // `MemberCreate.member_type` defaults to `business`.
        "POST /v1/members": ["member_type": "business"]
    ]

    private static func normalised(_ body: Body, route: String) -> Body {
        guard case var .json(.object(object)) = body else { return body }
        for (from, to) in aliases[route] ?? [:] {
            if let value = object.removeValue(forKey: from) { object[to] = value }
        }
        for (key, value) in defaults[route] ?? [:] where object[key] == value {
            object[key] = nil
        }
        return .json(.object(object))
    }

    init(_ request: HAR.Request) {
        method = request.method.uppercased()
        (route, query) = Self.split(request.url)
        switch request.postData {
        case nil: body = .none
        case let postData?:
            if let text = postData.text, !text.isEmpty {
                body = Self.normalised(
                    Self.body(text, contentType: postData.mimeType), route: "\(method) \(URLComponents(string: request.url)?.path ?? "")")
            } else {
                body = .unrecorded
            }
        }
    }

    func matches(_ recorded: RecordedRequest) -> Bool {
        guard method == recorded.method, route == recorded.route, query == recorded.query else { return false }
        switch (body, recorded.body) {
        case (_, .unrecorded): return true
        // The JS SDK posts `{}` to a body-less action route (`/start`, `/end`, `/cancel`); this SDK sends no body.
        case (.none, .json(.object([:]))): return true
        case let (.json(sent), .json(recorded)): return Self.equivalent(sent, recorded)
        default: return body == recorded.body
        }
    }

    /// Why nothing matched: the closest unconsumed recordings of the same route, and what differs.
    func explainMiss(against candidates: [RecordedRequest]) -> String {
        guard !candidates.isEmpty else {
            return "no unconsumed recording of \(method) \(route); sent query \(query), body \(body.summary)"
        }
        let lines = candidates.prefix(3).map { candidate -> String in
            var diffs: [String] = []
            if candidate.query != query { diffs.append("query recorded \(candidate.query), sent \(query)") }
            if candidate.body != body, candidate.body != .unrecorded {
                diffs.append("body " + Self.diff(recorded: candidate.body, sent: body).joined(separator: "; "))
            }
            return "  - " + diffs.joined(separator: " | ")
        }
        return "\(candidates.count) unconsumed recording(s) of this route differ:\n" + lines.joined(separator: "\n")
    }

    /// JSON equality, with one normalisation: two strings that are both ISO-8601 timestamps are equal when they
    /// name the same instant (the SDK sends `2026-01-01T00:00:00.000Z` where the JS SDK sent `...00Z`).
    static func equivalent(_ sent: JSONValue, _ recorded: JSONValue) -> Bool {
        switch (sent, recorded) {
        case let (.object(left), .object(right)):
            return left.count == right.count && left.allSatisfy { key, value in right[key].map { equivalent(value, $0) } ?? false }
        case let (.array(left), .array(right)):
            return left.count == right.count && zip(left, right).allSatisfy { equivalent($0, $1) }
        case let (.string(left), .string(right)) where left != right:
            guard left.contains("T"), let lhs = ISO8601.parse(left), let rhs = ISO8601.parse(right) else { return false }
            return lhs == rhs
        default:
            return sent == recorded
        }
    }

    private static func split(_ url: String) -> (String, [[String]]) {
        guard let components = URLComponents(string: url) else { return (url, []) }
        let port = components.port.map { ":\($0)" } ?? ""
        let route = "\(components.scheme ?? "")://\(components.host ?? "")\(port)\(components.path)"
        let query = (components.queryItems ?? []).map { [$0.name, $0.value ?? ""] }.sorted { $0.lexicographicallyPrecedes($1) }
        return (route, query)
    }

    private static func body(_ text: String, contentType: String?) -> Body {
        let type = contentType?.lowercased() ?? ""
        if type.contains("x-www-form-urlencoded") {
            let pairs = text.split(separator: "&").map { pair -> [String] in
                let parts = pair.split(separator: "=", maxSplits: 1).map {
                    String($0).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String($0)
                }
                return [parts.first ?? "", parts.count > 1 ? parts[1] : ""]
            }
            return .form(pairs.sorted { $0.lexicographicallyPrecedes($1) })
        }
        // The boundary is case-sensitive, so it is read from the header as sent, not the lowercased type.
        if type.hasPrefix("multipart/form-data"), let boundary = contentType?.components(separatedBy: "boundary=").last {
            return .multipart(multipartFields(text, boundary: boundary))
        }
        if let json = try? JSONCoding.decoder.decode(JSONValue.self, from: Data(text.utf8)) {
            return .json(json)
        }
        return .text(text)
    }

    /// Each part as `[name, filename, content type, content]`, sorted by name.
    private static func multipartFields(_ text: String, boundary: String) -> [[String]] {
        text.components(separatedBy: "--\(boundary)").compactMap { part -> [String]? in
            guard let split = part.range(of: "\r\n\r\n") else { return nil }
            let head = part[..<split.lowerBound]
            var content = String(part[split.upperBound...])
            if content.hasSuffix("\r\n") { content.removeLast(2) }
            func attribute(_ name: String) -> String {
                guard let range = head.range(of: "\(name)=\"") else { return "" }
                return String(head[range.upperBound...].prefix { $0 != "\"" })
            }
            let type = head.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix("content-type:") }
            return [attribute("name"), attribute("filename"), type?.dropFirst(13).trimmingCharacters(in: .whitespaces) ?? "", content]
        }
        .sorted { $0.lexicographicallyPrecedes($1) }
    }

    private static func diff(recorded: Body, sent: Body) -> [String] {
        guard case let .json(left) = recorded, case let .json(right) = sent else {
            return ["recorded \(recorded.summary), sent \(sent.summary)"]
        }
        return jsonDiff(left, right, path: "$").prefix(8).map { $0 }
    }

    private static func jsonDiff(_ recorded: JSONValue, _ sent: JSONValue, path: String) -> [String] {
        switch (recorded, sent) {
        case let (.object(left), .object(right)):
            return Set(left.keys).union(right.keys).sorted().flatMap { key -> [String] in
                switch (left[key], right[key]) {
                case let (lhs?, rhs?): return jsonDiff(lhs, rhs, path: "\(path).\(key)")
                case let (lhs?, nil): return ["\(path).\(key): recorded \(lhs.compact), not sent"]
                case let (nil, rhs?): return ["\(path).\(key): not recorded, sent \(rhs.compact)"]
                case (nil, nil): return []
                }
            }
        case let (.array(left), .array(right)) where left.count == right.count:
            return zip(left, right).enumerated().flatMap { jsonDiff($1.0, $1.1, path: "\(path)[\($0)]") }
        default:
            return recorded == sent ? [] : ["\(path): recorded \(recorded.compact), sent \(sent.compact)"]
        }
    }
}

extension RecordedRequest.Body {
    var summary: String {
        switch self {
        case .none: return "none"
        case .unrecorded: return "unrecorded"
        case let .json(value): return value.compact
        case let .form(pairs): return "form \(pairs)"
        case let .multipart(parts): return "multipart \(parts.map { $0.prefix(3) })"
        case let .text(text): return "text \(text.prefix(200))"
        }
    }
}

extension JSONValue {
    /// One-line JSON, cut at 300 characters.
    var compact: String {
        let data = (try? JSONCoding.encoder.encode(self)) ?? Data()
        return String(String(decoding: data, as: UTF8.self).prefix(300))
    }
}
