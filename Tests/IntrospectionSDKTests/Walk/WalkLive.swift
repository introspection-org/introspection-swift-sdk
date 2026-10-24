import Foundation
import IntrospectionSDK

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Complete an OAuth grant the way the JS walk does: follow the provider's redirects by hand, sending nothing
/// to the provider but the redirect itself, and route the registered callback host (a public name that does
/// not reach a local stack) to the Control Plane the walk talks to. Each hop goes through `transport`, so the
/// recording carries the hops and replay answers them.
func followAuthorization(
    _ authorizeURL: String, transport: any HTTPTransport, baseApiUrl: URL, cookie: String, returnURL: String
) async throws -> URLComponents {
    let base = baseApiUrl.absoluteString
    var next = authorizeURL
    for _ in 0..<12 {
        guard var url = URLComponents(string: next) else { throw WalkError("authorization: not a URL: \(next)") }
        if url.path == "/v1/oauth/connections/callback" {
            next = "\(base)\(url.path)\(url.percentEncodedQuery.map { "?\($0)" } ?? "")"
            url = URLComponents(string: next) ?? url
        }
        if next.hasPrefix(returnURL) { return url }
        var headers = [ManualRedirect.header: "1"]
        if next.hasPrefix(base) { headers["Cookie"] = "intro_cp_session=\(cookie)" }
        guard let target = URL(string: next) else { throw WalkError("authorization: not a URL: \(next)") }
        let response = try await transport.send(HTTPRequest(method: "GET", url: target, headers: headers))
        if let location = response.headers["location"] {
            next = URL(string: location, relativeTo: target)?.absoluteString ?? location
            continue
        }
        guard response.status == 200 else {
            throw WalkError("authorization stopped at \(target.host ?? "")\(target.path) with \(response.status) and no redirect")
        }
        next = try consentLink(String(decoding: response.body, as: UTF8.self), page: target)
    }
    throw WalkError("authorization did not reach the return URL within 12 redirects")
}

/// The MCP reference server's consent page is one "Continue" link to its mock upstream IdP, which completes
/// from a script that navigates to its callback with a fixed code and the browser's user id; the walk's user
/// id is fixed too, so the grant is the same subject every run.
private func consentLink(_ page: String, page url: URL) throws -> String {
    if let range = page.range(of: #"<a\s+href="([^"]+)"[^>]*class="btn-primary""#, options: .regularExpression) {
        let tag = page[range]
        if let start = tag.range(of: "href=\"") {
            let href = tag[start.upperBound...].prefix { $0 != "\"" }
            let decoded = String(href).replacingOccurrences(of: "&amp;", with: "&")
            return URL(string: decoded, relativeTo: url)?.absoluteString ?? decoded
        }
    }
    if page.contains("/mock-upstream-idp/callback"),
        let range = page.range(of: #"searchParams\.set\('state',\s*'([^']+)'\)"#, options: .regularExpression)
    {
        let call = page[range]
        let parts = call.split(separator: "'")
        guard parts.count >= 4 else { throw WalkError("authorization: unreadable state in the upstream page") }
        var callback = URLComponents(url: URL(string: "/mock-upstream-idp/callback", relativeTo: url)!, resolvingAgainstBaseURL: true)!
        callback.queryItems = [
            URLQueryItem(name: "state", value: String(parts[3])), URLQueryItem(name: "code", value: "mock-auth-code"),
            URLQueryItem(name: "userId", value: "sdk-walk-user"),
        ]
        return callback.url!.absoluteString
    }
    throw WalkError("authorization stopped at \(url.host ?? "")\(url.path): a page with no continue link")
}

/// A live hop of ``followAuthorization`` must see the redirect, not follow it: requests carrying
/// ``header`` go through a session that never follows redirects. Replay ignores headers.
enum ManualRedirect {
    static let header = "X-Walk-Manual-Redirect"

    static func transport() -> any HTTPTransport { NoRedirectTransport() }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _: URLSession, task _: URLSessionTask, willPerformHTTPRedirection _: HTTPURLResponse, newRequest _: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

private final class NoRedirectTransport: HTTPTransport {
    private let session = URLSession(configuration: .ephemeral, delegate: NoRedirectDelegate(), delegateQueue: nil)

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        for (name, value) in request.headers where name != ManualRedirect.header { urlRequest.setValue(value, forHTTPHeaderField: name) }
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw WalkError("no HTTP response from \(request.url)") }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields { headers[String(describing: key).lowercased()] = String(describing: value) }
        return HTTPResponse(status: http.statusCode, headers: headers, body: data)
    }

    func stream(_ request: HTTPRequest) async throws -> HTTPStreamResponse {
        let response = try await send(request)
        return HTTPStreamResponse(
            status: response.status, headers: response.headers,
            bytes: AsyncThrowingStream { continuation in
                continuation.yield(response.body)
                continuation.finish()
            })
    }
}

/// The recipe the walk pushes, cloned at `ref` and checked before the walk creates anything: the walk's agent
/// is there and `introspection check` passes. Live only; the git transport is a subprocess the recording
/// cannot see.
func prepareRecipe(url: String, ref: String, agent: String) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sdk-walk-recipe-\(UUID().uuidString)")
    do {
        try run("git", ["clone", "--quiet", "--depth", "1", "--branch", ref, url, dir.path])
    } catch {
        throw WalkError(
            "cloning \(url) failed: \(error); set RECIPE_DIR to a recipe-harbor-mcp-agent checkout, or keep one beside this repository"
        )
    }
    guard FileManager.default.fileExists(atPath: dir.appendingPathComponent("agents/\(agent).yaml").path) else {
        throw WalkError("\(url) has no agents/\(agent).yaml committed on \(ref)")
    }
    try run(
        "npx",
        ["-y", "-p", "@introspection-ai/cli@latest", "introspection", "check", "--work-dir", dir.path, "--non-interactive", "-o", "table"])
    return dir
}

/// Push a recipe prepared by ``prepareRecipe(url:ref:agent:)`` to the walk's hosted `main`, then remove the
/// clone. The bearer travels in the environment as a git config, never in argv.
func pushRecipe(_ dir: URL, url: String, bearer: String) async throws {
    let env = [
        "GIT_TERMINAL_PROMPT": "0", "GIT_CONFIG_COUNT": "2",
        "GIT_CONFIG_KEY_0": "http.extraHeader", "GIT_CONFIG_VALUE_0": "Authorization: Bearer \(bearer)",
        "GIT_CONFIG_KEY_1": "credential.helper", "GIT_CONFIG_VALUE_1": "",
    ]
    // The Data Plane provisions the hosted copy on its own schedule, so the first push may land before it exists.
    let deadline = ContinuousClock.now + .seconds(120)
    while true {
        do {
            try run("git", ["-C", dir.path, "push", "--quiet", "--force", url, "HEAD:refs/heads/main"], environment: env)
            break
        } catch let error as WalkError where error.description.lowercased().contains("not found") && ContinuousClock.now < deadline {
            try await Task.sleep(for: .seconds(3))
        }
    }
    try? FileManager.default.removeItem(at: dir)
}

private func run(_ tool: String, _ arguments: [String], environment: [String: String] = [:]) throws {
    #if os(macOS) || os(Linux)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [tool] + arguments
    process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
    let errors = Pipe()
    process.standardError = errors
    process.standardOutput = errors
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let output = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        throw WalkError("\(tool) \(arguments.first ?? "") failed: \(output.prefix(2000))")
    }
    #else
    throw WalkError("a live walk runs on macOS or Linux")
    #endif
}
