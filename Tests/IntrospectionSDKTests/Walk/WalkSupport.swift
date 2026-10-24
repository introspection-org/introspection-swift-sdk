import Foundation
import IntrospectionSDK

/// Support for the SDK end-to-end walk (introspection-cloud `docs/design/sdk-end-to-end-walk.md`), ported from
/// the JS SDK's `tests/walk/support.ts`: the fixed names, the target's settings, the normaliser the inline
/// snapshots go through, and the one way polling reads are recorded.
enum WALK {
    static let siblingSuffix = "-walk"
    static let applicationName = "sdk-coverage-walk"
    static let tagName = "walk"
    static let apiKeyName = "walk"
    static let automationName = "The walk's automation"
    static let experimentNames = ["The walk's experiment", "The walk's cancelled experiment"]
    static let credentialName = "WALK_SECRET"
    static let credentialSecret = "walk-secret-value-0001"
    static let secondTurn = "Reply with the single word done."
    static let variableName = "WALK_MARKER"
    static let variableValue = "walk-marker-7f3a"
    static let connectorName = "hello-mcp"
    static let mcpServerId = "hello-mcp"
    static let mcpIssuer = "https://example-server.modelcontextprotocol.io/"
    static let mcpEndpoint = "https://example-server.modelcontextprotocol.io/mcp"
    static let recipeSlug = "hello-mcp"
    static let runtimeSlug = "hello-mcp"
    static let inputFileName = "walk-input.txt"
    static let inputFileText = "the walk's input file"
    static let outputFileName = "greeting.txt"
    /// The access step's people, in the order the JS walk makes them: customer members keyed `user:walk-<name>`.
    static let personas: [(name: String, tags: [String])] = [
        ("avery", ["group:platform"]), ("blake", []), ("casey", ["group:platform"]), ("emery", []),
    ]
    static let groupTag = "group:platform"
    static let adminName = "Drew"
    static let personaFileName = "walk-avery-notes.txt"
    static let echoMessage = "hello from the public MCP"
    static let echoResult = "Echo: hello from the public MCP"
    static let instruction =
        "Call the `echo` tool from the declared `hello-mcp` MCP server with the message "
        + "`hello from the public MCP`. Write the echoed value exactly, with no quotes or "
        + "additional formatting, to `/workspace/outputs/greeting.txt`. Then run `echo $WALK_MARKER` "
        + "in the shell and reply in one short sentence."

    /// Every scope a service-account application may hold that the walk uses.
    static let applicationScopes = [
        "projects:read", "repositories:read", "repositories:write", "repositories:delete", "recipes:read",
        "recipes:write", "runtimes:read", "runtimes:write", "experiments:read", "experiments:write", "tasks:read",
        "tasks:write", "tasks:delete", "tasks:eval", "tasks:exec", "files:read", "files:write", "files:delete",
        "conversations:read", "events:read", "metrics:read", "shares:read", "shares:write", "shares:delete",
        "connectors:read", "connectors:write", "connections:read", "connections:write", "connections:delete",
        "automations:read", "automations:write", "annotations:read", "approvals:read", "approvals:write",
        "images:read", "images:write", "api_keys:read", "api_keys:write", "api_keys:delete", "applications:read",
        "applications:write", "applications:delete", "credentials:read", "credentials:write", "credentials:delete",
        "endpoints:read", "endpoints:write", "endpoints:delete", "variables:read", "variables:write",
        "variables:delete", "judges:read", "judges:write", "telemetry:write",
    ]

    /// The scripted model's directive, byte for byte the JSON the JS walk sends (`JSON.stringify` key order).
    static let scriptedDirective =
        #"<<SCRIPT {"reply":"Echoed the message through hello-mcp and wrote it to the outputs file.","#
        + #""tools":[{"name":"hello-mcp_echo","arguments":{"message":"hello from the public MCP"}},"#
        + #"{"name":"write","arguments":{"path":"/workspace/outputs/greeting.txt","content":"Echo: hello from the public MCP"}},"#
        + #"{"name":"bash","arguments":{"command":"echo $WALK_MARKER"}}]}>>"#

    static func prompt(_ settings: WalkSettings) -> String {
        settings.agent == "scripted" ? "\(instruction)\n\n\(scriptedDirective)" : instruction
    }

    static func secondTurn(_ settings: WalkSettings) -> String {
        settings.agent == "scripted" ? #"\#(secondTurn) <<SCRIPT {"reply":"done"}>>"# : secondTurn
    }
}

/// `WALK_MODE` (or `POLLY_MODE`, as the JS walk names it): `replay` by default, `record` to write this SDK's
/// own recording against a live stack, `passthrough` to run live and record nothing.
enum WalkMode {
    static var current: HARTransport.Mode {
        let env = ProcessInfo.processInfo.environment
        return (env["WALK_MODE"] ?? env["POLLY_MODE"]).flatMap(HARTransport.Mode.init(rawValue:)) ?? .replay
    }
}

/// Where the recording lives: `Tests/recordings/walk/`, synced from the JS SDK by
/// `scripts/sync-walk-recording.sh`. `WALK_RECORDINGS_DIR` redirects a record run.
enum WalkPaths {
    static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static var recordingDir: URL {
        if let dir = ProcessInfo.processInfo.environment["WALK_RECORDINGS_DIR"] { return URL(fileURLWithPath: dir) }
        return repository.appendingPathComponent("Tests/recordings/walk")
    }

    static var har: URL { recordingDir.appendingPathComponent("recording.har") }
    static var bootstrap: URL { recordingDir.appendingPathComponent("bootstrap.json") }

    static var report: URL {
        if let path = ProcessInfo.processInfo.environment["WALK_REPORT_PATH"] { return URL(fileURLWithPath: path) }
        return repository.appendingPathComponent("generated/walk-report.json")
    }

    /// The committed recording, when it reaches the walk's teardown: the application it removed read back
    /// (404), then the login's project. A record run that stopped short leaves a partial HAR replay must skip.
    static func completeRecording() -> HAR? {
        guard let data = try? Data(contentsOf: har), let har = try? JSONDecoder().decode(HAR.self, from: data) else {
            return nil
        }
        let tail = har.log.entries.suffix(2)
        guard tail.count == 2, let app = tail.first, let last = tail.last else { return nil }
        let complete =
            app.response.status == 404 && app.request.url.contains("/v1/applications/")
            && last.request.method == "GET" && last.request.url.range(of: #"/v1/projects/[^/?]+$"#, options: .regularExpression) != nil
        return complete ? har : nil
    }
}

/// The target's settings. Replay gets the fixed values the JS walk recorded with; a live run reads
/// `~/.introspection/credentials.json` (what `introspection login` writes) with the environment over it.
struct WalkSettings: Sendable {
    var baseApiUrl: URL
    var cpSession: String
    var bootstrapProjectId: String
    var dpUrl: URL?
    var recipeRepositoryUrl: String
    var recipeGitRef: String
    var agent: String
    var target: String

    static func load(_ mode: HARTransport.Mode) throws -> WalkSettings {
        if mode == .replay {
            let bootstrap = (try? Data(contentsOf: WalkPaths.bootstrap)).flatMap {
                try? JSONDecoder().decode([String: String].self, from: $0)
            }
            return WalkSettings(
                baseApiUrl: URL(string: "http://localhost:8000")!, cpSession: "replay-session",
                bootstrapProjectId: bootstrap?["project_id"] ?? "", dpUrl: URL(string: "http://localhost:8002"),
                recipeRepositoryUrl: "https://github.com/introspection-org/recipe-harbor-mcp-agent", recipeGitRef: "main",
                agent: "scripted", target: "compose")
        }
        let env = ProcessInfo.processInfo.environment
        let path = env["INTROSPECTION_CREDENTIALS"] ?? "\(NSHomeDirectory())/.introspection/credentials.json"
        let file = (try? Data(contentsOf: URL(fileURLWithPath: path))).flatMap {
            try? JSONDecoder().decode([String: String?].self, from: $0)
        }
        func setting(_ name: String, _ key: String) -> String? { env[name] ?? (file?[key] ?? nil) }
        guard let cpURL = setting("INTROSPECTION_BASE_API_URL", "cp_url").flatMap(URL.init(string:)),
            let cpSession = setting("INTROSPECTION_CP_SESSION", "cp_session")
        else {
            throw WalkError(
                "the walk is in \(mode) mode and has no Control Plane session: run `introspection login` "
                    + "or set INTROSPECTION_BASE_API_URL and INTROSPECTION_CP_SESSION")
        }
        guard let project = setting("INTROSPECTION_PROJECT_ID", "project_id") else {
            throw WalkError("the walk runs in the login's project and the login names none: set INTROSPECTION_PROJECT_ID")
        }
        return WalkSettings(
            baseApiUrl: cpURL, cpSession: cpSession, bootstrapProjectId: project,
            dpUrl: setting("INTROSPECTION_DP_URL", "dp_url").flatMap(URL.init(string:)),
            recipeRepositoryUrl: env["RECIPE_DIR"] ?? env["RECIPE_REPOSITORY_URL"]
                ?? "https://github.com/introspection-org/recipe-harbor-mcp-agent",
            recipeGitRef: env["RECIPE_GIT_REF"] ?? "main", agent: env["WALK_AGENT"] ?? "scripted",
            target: env["WALK_TARGET"] ?? "compose")
    }
}

struct WalkError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

// MARK: Normalisation

/// Everything stable, nothing volatile: a port of the JS walk's `stable()`. Ids, timestamps, hashes, tokens,
/// secrets and URLs become a placeholder naming their kind, by key and by shape, so an inline snapshot pins
/// every other field. Measured numbers (durations, counts, token totals) become `[number]`; their bounds are
/// asserted beside the snapshot.
enum Stable {
    private static func regex(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        do { return try NSRegularExpression(pattern: pattern, options: options) } catch { fatalError("\(error)") }
    }

    private static let uuid = regex(#"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#, .caseInsensitive)
    private static let timestamp = regex(#"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$"#)
    private static let sha = regex(#"^[0-9a-f]{40}$"#, .caseInsensitive)
    private static let uuidAnywhere = regex(#"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"#, .caseInsensitive)
    private static let shaAnywhere = regex(#"\b[0-9a-f]{40}\b"#, .caseInsensitive)
    private static let digestAnywhere = regex(#"\b[0-9a-f]{64}\b"#, .caseInsensitive)
    private static let jwt = regex(#"^eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$"#)
    private static let url = regex(#"^https?://"#)
    private static let idKey = regex(#"_id$"#)
    private static let digit = regex(#"\d"#)
    private static let measuredKey = regex(#"(_ms$|_count$|_tokens$|^max_turn$)"#)
    private static let volatileKey = regex(
        #"(^id$|_at$|_sha$|token$|secret$|^key$|_key$|cookie$|^url$|_url$|^expires_in$|^client_id$|_prefix$|_suffix$|^prefix$|^key_display$|image_tag$|_image_name$|_bytes$)"#
    )

    private static func test(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func replace(_ regex: NSRegularExpression, _ text: String, _ template: String) -> String {
        regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    static func value(_ value: JSONValue, key: String = "") -> JSONValue {
        switch value {
        case let .array(items): return .array(items.map { Self.value($0) })
        case let .object(object): return .object(object.reduce(into: [:]) { $0[$1.key] = Self.value($1.value, key: $1.key) })
        case let .string(text): return .string(string(text, key: key))
        case .number where test(volatileKey, key) || test(measuredKey, key): return "[number]"
        default: return value
        }
    }

    private static func string(_ text: String, key: String) -> String {
        if test(uuid, text) { return "[uuid]" }
        if test(timestamp, text) { return "[timestamp]" }
        if test(sha, text) { return "[sha]" }
        if test(jwt, text) { return "[jwt]" }
        if test(url, text) { return "[url]" }
        if test(volatileKey, key) { return "[redacted]" }
        if test(idKey, key), test(digit, text) { return "[id]" }
        return replace(shaAnywhere, replace(digestAnywhere, replace(uuidAnywhere, text, "[uuid]"), "[digest]"), "[sha]")
    }
}

/// The SDK's decoded value, encoded back to JSON and normalised: what each step's inline snapshot pins.
/// A field the server sent that the SDK's model drops is absent here, which is the finding.
func stable<T: Encodable>(_ value: T, removing keys: [String] = []) throws -> JSONValue {
    var json = try JSONValue.from(value)
    if case var .object(object) = json {
        for key in keys { object[key] = nil }
        json = .object(object)
    }
    return Stable.value(json)
}

// MARK: Steps

/// The per-run report the SDK matrix reads: the same JSON shape in every SDK.
struct WalkReport: Encodable {
    struct Step: Encodable {
        let n: Int
        let name: String
        var status: String
    }

    struct Entries: Encodable {
        var total: Int
        var consumed: Int
    }

    struct Request: Encodable, Hashable {
        let method: String
        let url: String?
        let path: String?
    }

    let sdk = "swift"
    var steps: [Step] = []
    var entries = Entries(total: 0, consumed: 0)
    var unconsumed: [Request] = []
    var rawCalls: [Request] = []

    private enum CodingKeys: String, CodingKey {
        case sdk, steps, entries, unconsumed
        case rawCalls = "raw_calls"
    }
}

/// A route the SDK has no public method for, called through its own HTTP client so it is recorded and
/// counted like every other (the JS walk's `raw()`); every call is a gap the report lists.
struct Raw {
    let http: HTTPClient
    let log: @Sendable (String, String) -> Void

    func json<T: Decodable>(
        _ method: String, _ path: String, query: [(String, String)] = [], body: JSONValue? = nil, as _: T.Type = T.self
    ) async throws -> T {
        log(method, path)
        return try await http.json(method, path, query: Self.query(query), body: body.map { try RequestBody.encode($0) } ?? .none)
    }

    func empty(_ method: String, _ path: String, query: [(String, String)] = []) async throws {
        log(method, path)
        try await http.empty(method, path, query: Self.query(query))
    }

    func data(_ path: String, query: [(String, String)] = [], accept: String) async throws -> Data {
        log("GET", path)
        return try await http.data("GET", path, query: Self.query(query), headers: ["Accept": accept])
    }

    private static func query(_ items: [(String, String)]) -> Query {
        var query = Query()
        for (name, value) in items { query.add(name, value) }
        return query
    }
}

/// The path with each id (a UUID, a 40-hex sha) as `{id}`, so the report names routes, not resources.
func routeTemplate(_ path: String) -> String {
    path.split(separator: "/", omittingEmptySubsequences: false).map { segment -> String in
        let text = String(segment)
        let isId =
            UUID(uuidString: text) != nil
            || (text.count == 40 && text.allSatisfy(\.isHexDigit))
        return isId ? "{id}" : text
    }
    .joined(separator: "/")
}

/// Poll `poll` (a client the recording never sees) until `done`, then `read` once through the recorded
/// client: that one read, in the resource's terminal state, is what the recording carries. In replay the
/// single recorded read is all there is.
func settled<T>(
    _ label: String, mode: HARTransport.Mode, timeout: Duration = .seconds(180), interval: Duration = .seconds(3),
    read: () async throws -> T, poll: () async throws -> T, done: (T) -> Bool
) async throws -> T {
    if mode != .replay {
        let deadline = ContinuousClock.now + timeout
        while true {
            if done(try await poll()) { break }
            guard ContinuousClock.now < deadline else { throw WalkError("\(label): not done after \(timeout)") }
            try await Task.sleep(for: interval)
        }
    }
    let final = try await read()
    guard done(final) else { throw WalkError("\(label): the recorded read is not in its terminal state") }
    return final
}

/// Whether `operation` answers 404: the SDK's `notFound` error.
func isNotFound(_ operation: () async throws -> some Any) async throws -> Bool {
    do {
        _ = try await operation()
        return false
    } catch let error as IntrospectionError where error.kind == .notFound {
        return true
    }
}

/// Run `operation`, treating a 404 as done: a teardown removing what may already be gone.
func ignoringNotFound(_ operation: () async throws -> Void) async throws {
    _ = try await isNotFound(operation)
}

extension Paginator {
    /// Every item, as `[Item]`.
    func all() async throws -> [Item] { try await collect() }
}

/// The whole value as JSON text, for a containment check.
func jsonText(_ value: some Encodable) -> String {
    (try? JSONCoding.encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? ""
}
