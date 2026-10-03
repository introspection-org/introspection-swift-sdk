import Foundation
import Synchronization

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One HTTP request as the transport sees it.
public struct HTTPRequest: Sendable {
    public var method: String
    public var url: URL
    public var headers: [String: String]
    public var body: Data?
    public var timeout: TimeInterval?

    public init(method: String, url: URL, headers: [String: String] = [:], body: Data? = nil, timeout: TimeInterval? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }
}

/// A buffered response. Header names are lowercased.
public struct HTTPResponse: Sendable {
    public let status: Int
    public let headers: [String: String]
    public let body: Data

    public init(status: Int, headers: [String: String], body: Data) {
        self.status = status
        self.headers = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { _, last in last })
        self.body = body
    }

    public var isSuccess: Bool { (200..<300).contains(status) }
}

/// A response whose body arrives incrementally. Header names are lowercased.
public struct HTTPStreamResponse: Sendable {
    public let status: Int
    public let headers: [String: String]
    public let bytes: AsyncThrowingStream<Data, any Error>

    public init(status: Int, headers: [String: String], bytes: AsyncThrowingStream<Data, any Error>) {
        self.status = status
        self.headers = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { _, last in last })
        self.bytes = bytes
    }

    /// Read the whole body.
    public func collect() async throws -> Data {
        var data = Data()
        for try await chunk in bytes { data.append(chunk) }
        return data
    }
}

/// How requests reach the network. Replace it in tests, or to route through
/// a custom networking stack.
public protocol HTTPTransport: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
    func stream(_ request: HTTPRequest) async throws -> HTTPStreamResponse
}

/// The default transport, on `URLSession`. Streaming uses a delegate so it
/// works on every platform Foundation supports, including Linux.
public final class URLSessionTransport: HTTPTransport, Sendable {
    private let session: URLSession

    public init(configuration: URLSessionConfiguration = .default) {
        session = URLSession(configuration: configuration)
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: Self.urlRequest(request))
        } catch {
            throw Self.networkError(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw IntrospectionError(kind: .network, message: "No HTTP response")
        }
        return HTTPResponse(status: http.statusCode, headers: Self.headers(http), body: data)
    }

    public func stream(_ request: HTTPRequest) async throws -> HTTPStreamResponse {
        let delegate = StreamDelegate()
        let streamSession = URLSession(configuration: session.configuration, delegate: delegate, delegateQueue: nil)
        let task = streamSession.dataTask(with: Self.urlRequest(request))
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HTTPStreamResponse, any Error>) in
                delegate.start(task: task, continuation: continuation)
            }
        } onCancel: {
            task.cancel()
        }
    }

    static func urlRequest(_ request: HTTPRequest) -> URLRequest {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
        urlRequest.httpBody = request.body
        if let timeout = request.timeout { urlRequest.timeoutInterval = timeout }
        return urlRequest
    }

    static func headers(_ response: HTTPURLResponse) -> [String: String] {
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            headers[String(describing: key).lowercased()] = String(describing: value)
        }
        return headers
    }

    static func networkError(_ error: any Error) -> any Error {
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return CancellationError()
        }
        return IntrospectionError(kind: .network, message: error.localizedDescription, underlying: error)
    }
}

private final class StreamDelegate: NSObject, URLSessionDataDelegate, Sendable {
    private struct State {
        var head: CheckedContinuation<HTTPStreamResponse, any Error>?
        var body: AsyncThrowingStream<Data, any Error>.Continuation?
    }

    private let state = Mutex(State())

    func start(task: URLSessionDataTask, continuation: CheckedContinuation<HTTPStreamResponse, any Error>) {
        state.withLock { $0.head = continuation }
        task.resume()
    }

    func urlSession(
        _: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            return
        }
        let (stream, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
        continuation.onTermination = { termination in
            if case .cancelled = termination { dataTask.cancel() }
        }
        let head = state.withLock { state in
            state.body = continuation
            defer { state.head = nil }
            return state.head
        }
        head?.resume(
            returning: HTTPStreamResponse(
                status: http.statusCode, headers: URLSessionTransport.headers(http), bytes: stream
            ))
        completionHandler(.allow)
    }

    func urlSession(_: URLSession, dataTask _: URLSessionDataTask, didReceive data: Data) {
        _ = state.withLock { $0.body }?.yield(data)
    }

    func urlSession(_ session: URLSession, task _: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let (head, body) = state.withLock { state in
            defer { state = State() }
            return (state.head, state.body)
        }
        if let head {
            head.resume(
                throwing: error.map(URLSessionTransport.networkError)
                    ?? IntrospectionError(kind: .network, message: "Connection closed before a response"))
        }
        if let error {
            body?.finish(throwing: URLSessionTransport.networkError(error))
        } else {
            body?.finish()
        }
        session.finishTasksAndInvalidate()
    }
}
