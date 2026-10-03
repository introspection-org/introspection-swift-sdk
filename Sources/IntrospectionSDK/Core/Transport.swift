import Foundation
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
    public let bytes: AsyncThrowingStream<Data, Error>

    public init(status: Int, headers: [String: String], bytes: AsyncThrowingStream<Data, Error>) {
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
public final class URLSessionTransport: HTTPTransport, @unchecked Sendable {
    private let session: URLSession
    private let configuration: URLSessionConfiguration

    public init(configuration: URLSessionConfiguration = .default) {
        self.configuration = configuration
        session = URLSession(configuration: configuration)
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let urlRequest = Self.urlRequest(request)
        let box = TaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HTTPResponse, Error>) in
                let task = session.dataTask(with: urlRequest) { data, response, error in
                    if let error {
                        continuation.resume(throwing: Self.networkError(error))
                        return
                    }
                    guard let http = response as? HTTPURLResponse else {
                        continuation.resume(throwing: IntrospectionError(kind: .network, message: "No HTTP response"))
                        return
                    }
                    continuation.resume(returning: HTTPResponse(
                        status: http.statusCode, headers: Self.headers(http), body: data ?? Data()
                    ))
                }
                box.set(task)
                task.resume()
            }
        } onCancel: {
            box.cancel()
        }
    }

    public func stream(_ request: HTTPRequest) async throws -> HTTPStreamResponse {
        let delegate = StreamDelegate()
        let streamSession = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        let task = streamSession.dataTask(with: Self.urlRequest(request))
        delegate.session = streamSession
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HTTPStreamResponse, Error>) in
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

    static func networkError(_ error: Error) -> Error {
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return CancellationError()
        }
        return IntrospectionError(kind: .network, message: error.localizedDescription, underlying: error)
    }
}

private final class TaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionTask?
    private var cancelled = false

    func set(_ task: URLSessionTask) {
        lock.lock()
        self.task = task
        let shouldCancel = cancelled
        lock.unlock()
        if shouldCancel { task.cancel() }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let task = self.task
        lock.unlock()
        task?.cancel()
    }
}

private final class StreamDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var headContinuation: CheckedContinuation<HTTPStreamResponse, Error>?
    private var bodyContinuation: AsyncThrowingStream<Data, Error>.Continuation?
    var session: URLSession?

    func start(task: URLSessionDataTask, continuation: CheckedContinuation<HTTPStreamResponse, Error>) {
        lock.lock()
        headContinuation = continuation
        lock.unlock()
        task.resume()
    }

    func urlSession(
        _: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            return
        }
        let (stream, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
        continuation.onTermination = { termination in
            if case .cancelled = termination { dataTask.cancel() }
        }
        lock.lock()
        bodyContinuation = continuation
        let head = headContinuation
        headContinuation = nil
        lock.unlock()
        head?.resume(returning: HTTPStreamResponse(
            status: http.statusCode, headers: URLSessionTransport.headers(http), bytes: stream
        ))
        completionHandler(.allow)
    }

    func urlSession(_: URLSession, dataTask _: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        let body = bodyContinuation
        lock.unlock()
        body?.yield(data)
    }

    func urlSession(_ session: URLSession, task _: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let head = headContinuation
        let body = bodyContinuation
        headContinuation = nil
        bodyContinuation = nil
        self.session = nil
        lock.unlock()
        if let head {
            head.resume(throwing: error.map(URLSessionTransport.networkError)
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
