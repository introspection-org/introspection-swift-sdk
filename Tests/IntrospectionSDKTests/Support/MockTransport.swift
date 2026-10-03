import Foundation

@testable import IntrospectionSDK

/// A scripted transport. Each request is recorded and answered by the
/// handler, which can inspect it.
final class MockTransport: HTTPTransport, @unchecked Sendable {
    struct Recorded {
        let request: HTTPRequest
        var path: String { request.url.path }
        var query: [String: [String]] {
            var result: [String: [String]] = [:]
            for item in URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
                result[item.name, default: []].append(item.value ?? "")
            }
            return result
        }
        var json: JSONValue? {
            request.body.flatMap { try? JSONCoding.decoder.decode(JSONValue.self, from: $0) }
        }
        var bodyString: String { request.body.map { String(decoding: $0, as: UTF8.self) } ?? "" }
    }

    enum Reply {
        case response(HTTPResponse)
        case stream(status: Int, headers: [String: String], chunks: [Data], error: any Error?)
        case failure(any Error)
    }

    private let lock = NSLock()
    private var _requests: [Recorded] = []
    private let handler: (HTTPRequest, Int) -> Reply

    init(_ handler: @escaping (HTTPRequest, Int) -> Reply) {
        self.handler = handler
    }

    /// Always answer with the same JSON body.
    convenience init(status: Int = 200, json: String, headers: [String: String] = [:]) {
        self.init { _, _ in
            .response(
                HTTPResponse(status: status, headers: ["content-type": "application/json"].merging(headers) { $1 }, body: Data(json.utf8)))
        }
    }

    var requests: [Recorded] {
        lock.lock()
        defer { lock.unlock() }
        return _requests
    }

    var last: Recorded? { requests.last }

    private func record(_ request: HTTPRequest) -> Int {
        lock.lock()
        defer { lock.unlock() }
        _requests.append(Recorded(request: request))
        return _requests.count - 1
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let index = record(request)
        switch handler(request, index) {
        case let .response(response): return response
        case let .stream(status, headers, chunks, _):
            return HTTPResponse(status: status, headers: headers, body: chunks.reduce(Data(), +))
        case let .failure(error): throw error
        }
    }

    func stream(_ request: HTTPRequest) async throws -> HTTPStreamResponse {
        let index = record(request)
        switch handler(request, index) {
        case let .response(response):
            return HTTPStreamResponse(
                status: response.status, headers: response.headers,
                bytes: AsyncThrowingStream { continuation in
                    continuation.yield(response.body)
                    continuation.finish()
                })
        case let .stream(status, headers, chunks, error):
            return HTTPStreamResponse(
                status: status, headers: headers,
                bytes: AsyncThrowingStream { continuation in
                    for chunk in chunks { continuation.yield(chunk) }
                    if let error { continuation.finish(throwing: error) } else { continuation.finish() }
                })
        case let .failure(error): throw error
        }
    }
}

extension HTTPResponse {
    static func json(_ text: String, status: Int = 200, headers: [String: String] = [:]) -> HTTPResponse {
        HTTPResponse(status: status, headers: ["content-type": "application/json"].merging(headers) { $1 }, body: Data(text.utf8))
    }
}

func makeClient(_ transport: MockTransport) -> IntrospectionClient {
    IntrospectionClient(
        configuration: .init(
            controlPlaneURL: URL(string: "https://cp.test")!,
            dataPlaneURL: URL(string: "https://dp.test")!,
            controlPlaneCredentials: BearerToken("cp-token"),
            dataPlaneCredentials: BearerToken("dp-token"),
            transport: transport,
            options: .init(maxRetries: 2, retryBase: 0.001)
        ))
}
