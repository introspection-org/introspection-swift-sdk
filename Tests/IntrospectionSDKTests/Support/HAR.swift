import Foundation

/// The subset of HAR 1.2 the walk's recording uses: what Polly.js writes, and what
/// ``HARTransport`` writes in record mode.
struct HAR: Codable {
    struct Log: Codable {
        var version = "1.2"
        var creator = Creator()
        var entries: [Entry]
    }

    struct Creator: Codable {
        var name = "introspection-swift-sdk walk"
        var version = "1.0"
    }

    struct Header: Codable {
        var name: String
        var value: String
    }

    struct PostData: Codable {
        var mimeType: String?
        var text: String?
    }

    struct Request: Codable {
        var method: String
        var url: String
        var httpVersion = "HTTP/1.1"
        var headers: [Header] = []
        var queryString: [Header] = []
        var postData: PostData?
    }

    struct Content: Codable {
        var mimeType: String?
        var size: Int?
        var text: String?
        var encoding: String?
    }

    struct Response: Codable {
        var status: Int
        var statusText = ""
        var httpVersion = "HTTP/1.1"
        var headers: [Header] = []
        var content: Content
        var redirectURL = ""
    }

    struct Entry: Codable {
        var startedDateTime: String
        var time: Double = 0
        var request: Request
        var response: Response
    }

    var log: Log
}

extension HAR.Content {
    /// The body bytes, base64-decoded when the recording says so.
    var data: Data {
        guard let text else { return Data() }
        if encoding == "base64" { return Data(base64Encoded: text) ?? Data() }
        return Data(text.utf8)
    }
}

extension HAR.Response {
    /// Header names lowercased, the last of a repeated name winning.
    var headerMap: [String: String] {
        Dictionary(headers.map { ($0.name.lowercased(), $0.value) }, uniquingKeysWith: { _, last in last })
    }
}

/// Credentials scrubbed from a recording before it is written, identical to the JS SDK's
/// `tests/polly-setup.ts` (and the Python SDK's `SECRET_PATTERNS`): the same regexes and the
/// same `REDACTED_*` placeholders, so a secret reads the same in every SDK's recording.
enum Scrub {
    private static let sensitiveHeaders: Set<String> = [
        "authorization", "api-key", "api_key", "x-api-key", "x-bt-api-key", "x-stainless-api-key",
        "anthropic-api-key", "anthropic-organization-id", "x-goog-api-key", "x-goog-user-project", "space_id",
        "cookie", "set-cookie", "openai-organization", "openai-project",
    ]

    private static let sensitiveHeaderPattern = try! NSRegularExpression(
        pattern:
            #"(authorization|api[-_]?key|access[-_]?token|refresh[-_]?token|\btoken\b|secret|password|credential|cookie|x-goog-user-project|session)"#,
        options: [.caseInsensitive])

    private static let secretPatterns: [(NSRegularExpression, String)] = [
        (#"sk-proj-[A-Za-z0-9_-]{20,}"#, "REDACTED_OPENAI_KEY"),
        (#"AIza[A-Za-z0-9_-]{35}"#, "REDACTED_GOOGLE_KEY"),
        (#"sk-ant-api\d+-[A-Za-z0-9_-]{20,}"#, "REDACTED_ANTHROPIC_KEY"),
        (#"intro_dev_[A-Za-z0-9_-]{20,}"#, "REDACTED_INTROSPECTION_TOKEN"),
        (#"eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"#, "REDACTED_JWT"),
        (#"intro_[a-z]+_[A-Za-z0-9_-]{20,}"#, "REDACTED_INTROSPECTION_KEY"),
        (#"("(?:client_secret|secret|api_key)"\s*:\s*")[^"]+(")"#, "$1REDACTED_SECRET$2"),
        (#"(client_secret=)[^&\s]+"#, "$1REDACTED_SECRET"),
    ].map { pattern, template in
        (try! NSRegularExpression(pattern: pattern), template)
    }

    static func isSensitiveHeader(_ name: String) -> Bool {
        let lower = name.lowercased()
        let range = NSRange(lower.startIndex..., in: lower)
        return sensitiveHeaders.contains(lower) || sensitiveHeaderPattern.firstMatch(in: lower, range: range) != nil
    }

    static func secrets(_ text: String) -> String {
        var out = text
        for (regex, template) in secretPatterns {
            out = regex.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: template)
        }
        return out
    }

    static func headers(_ headers: [HAR.Header]) -> [HAR.Header] {
        headers.map { isSensitiveHeader($0.name) ? HAR.Header(name: $0.name, value: "REDACTED") : $0 }
    }

    /// A whole entry, as Polly's `beforePersist` hook scrubs it.
    static func entry(_ entry: HAR.Entry) -> HAR.Entry {
        var entry = entry
        entry.request.headers = headers(entry.request.headers)
        entry.response.headers = headers(entry.response.headers)
        entry.request.url = secrets(entry.request.url)
        entry.request.queryString = entry.request.queryString.map { HAR.Header(name: $0.name, value: secrets($0.value)) }
        let postText = entry.request.postData?.text
        entry.request.postData?.text = postText.map(secrets)
        if entry.response.content.encoding == nil {
            let text = entry.response.content.text
            entry.response.content.text = text.map(secrets)
        }
        return entry
    }
}
