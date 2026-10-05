#if Telemetry
import Foundation
import IntrospectionSDK
import Logging
import OpenTelemetryProtocolExporterHttp

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Sends the OpenTelemetry exporters' requests through the SDK's `HTTPClient`, so the bearer, its refresh after a
/// 401, the 429 retry, the transport and the logger are the core client's.
final class OTLPTransport: OpenTelemetryProtocolExporterHttp.HTTPClient, Sendable {
    let http: CoreHTTPClient
    private let base: String

    init(resolved: ResolvedTelemetry, credentials: any CredentialProvider, options: TelemetryOptions, timeout: Duration) {
        base = resolved.baseURL.absoluteString
        http = CoreHTTPClient(
            baseURL: resolved.baseURL, credentials: credentials, transport: options.transport,
            options: .init(timeout: timeout.timeInterval, additionalHeaders: resolved.headers, logger: options.logger))
    }

    func send(request: URLRequest) async throws -> HTTPURLResponse {
        guard let url = request.url, url.absoluteString.hasPrefix(base) else {
            throw IntrospectionError(kind: .invalidRequest, message: "OTLP request outside the configured base URL")
        }
        var headers: [String: String] = [:]
        if let encoding = request.value(forHTTPHeaderField: "Content-Encoding") { headers["Content-Encoding"] = encoding }
        let contentType = request.value(forHTTPHeaderField: "Content-Type") ?? "application/x-protobuf"
        let response = try await http.send(
            "POST", String(url.absoluteString.dropFirst(base.count)), body: .raw(request.httpBody ?? Data(), contentType: contentType),
            headers: headers)
        guard let reply = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: nil, headerFields: response.headers) else {
            throw IntrospectionError(kind: .network, message: "Could not build the collector response")
        }
        return reply
    }

    func send(request: URLRequest, completion: @escaping (Result<HTTPURLResponse, any Error>) -> Void) {
        // The upstream protocol's completion is not @Sendable; the exporter waits on a semaphore for this call.
        nonisolated(unsafe) let completion = completion
        let logger = http.options.logger
        Task {
            do {
                completion(.success(try await send(request: request)))
            } catch {
                logger.warning("Could not export telemetry; the batch was dropped", metadata: ["error": "\(error)"])
                completion(.failure(error))
            }
        }
    }
}

/// Run blocking OpenTelemetry work (flush, shutdown) off the cooperative pool, which the export it waits on needs.
func offPool(_ work: @escaping @Sendable () -> Void) async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        DispatchQueue.global().async {
            work()
            continuation.resume()
        }
    }
}
#endif
