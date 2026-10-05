#if Telemetry
import Foundation
import IntrospectionSDK
import Logging

/// The environment variables the telemetry layer reads: the same names, and the same defaults, as the
/// JavaScript, Python and Rust SDKs.
public enum TelemetryEnvironment {
    /// The bearer token (an API key or an access token).
    public static let token = "INTROSPECTION_TOKEN"
    /// The OTLP base URL; `/v1/logs` and `/v1/traces` are appended.
    public static let baseOTelURL = "INTROSPECTION_BASE_OTEL_URL"
    /// The resource's `service.name`.
    public static let serviceName = "INTROSPECTION_SERVICE_NAME"
    /// Extra export headers, `key=value` pairs separated by commas (percent-encoded values allowed). An explicit
    /// ``TelemetryOptions/additionalHeaders`` entry wins, and the credentials always set `Authorization`.
    public static let otlpHeaders = "OTEL_EXPORTER_OTLP_HEADERS"
    /// `gzip` or `none` (the default, as in the other SDKs).
    public static let otlpCompression = "OTEL_EXPORTER_OTLP_COMPRESSION"
    /// OpenTelemetry batch log record processor settings, in milliseconds or counts.
    public static let logScheduleDelay = "OTEL_BLRP_SCHEDULE_DELAY"
    public static let logExportTimeout = "OTEL_BLRP_EXPORT_TIMEOUT"
    public static let logMaxQueueSize = "OTEL_BLRP_MAX_QUEUE_SIZE"
    public static let logMaxExportBatchSize = "OTEL_BLRP_MAX_EXPORT_BATCH_SIZE"
    /// OpenTelemetry batch span processor settings, in milliseconds or counts.
    public static let spanScheduleDelay = "OTEL_BSP_SCHEDULE_DELAY"
    public static let spanExportTimeout = "OTEL_BSP_EXPORT_TIMEOUT"
    public static let spanMaxQueueSize = "OTEL_BSP_MAX_QUEUE_SIZE"
    public static let spanMaxExportBatchSize = "OTEL_BSP_MAX_EXPORT_BATCH_SIZE"

    /// `https://otel.introspection.dev`.
    public static let defaultBaseOTelURL = URL(string: "https://otel.introspection.dev")!
    /// `introspection-client`.
    public static let defaultServiceName = "introspection-client"
}

/// Batching for one signal. A nil field falls back to its `OTEL_BLRP_*` / `OTEL_BSP_*` variable, then the default.
public struct TelemetryBatchOptions: Sendable, Hashable {
    public var scheduleDelay: Duration?
    public var exportTimeout: Duration?
    public var maxQueueSize: Int?
    public var maxExportBatchSize: Int?

    public init(scheduleDelay: Duration? = nil, exportTimeout: Duration? = nil, maxQueueSize: Int? = nil, maxExportBatchSize: Int? = nil) {
        self.scheduleDelay = scheduleDelay
        self.exportTimeout = exportTimeout
        self.maxQueueSize = maxQueueSize
        self.maxExportBatchSize = maxExportBatchSize
    }
}

/// Export body compression.
public enum TelemetryCompression: String, Sendable, Hashable {
    /// Gzip the protobuf body. The OpenTelemetry Swift exporter compresses only on Apple platforms; elsewhere the
    /// body is sent uncompressed.
    case gzip
    case none
}

/// Options shared by ``IntrospectionTelemetry``, ``IntrospectionLogs`` and ``IntrospectionSpanProcessor``.
public struct TelemetryOptions: Sendable {
    /// Log batching. Defaults: 5 s delay, 30 s timeout, 2048 queued, 100 per request (as the JavaScript SDK).
    public var logBatch: TelemetryBatchOptions
    /// Span batching. Defaults: 5 s delay, 30 s timeout, 2048 queued, 512 per request (the OpenTelemetry defaults).
    public var spanBatch: TelemetryBatchOptions
    /// How requests reach the collector; replace it in tests.
    public var transport: any HTTPTransport
    /// Export requests and failures are logged here; silent by default.
    public var logger: Logger
    /// Nil falls back to `OTEL_EXPORTER_OTLP_COMPRESSION`, then `none`.
    public var compression: TelemetryCompression?
    /// Headers merged into every export request, over `OTEL_EXPORTER_OTLP_HEADERS`.
    public var additionalHeaders: [String: String]
    /// Where unset settings are looked up. Defaults to the process environment.
    public var environment: [String: String]

    public init(
        logBatch: TelemetryBatchOptions = TelemetryBatchOptions(),
        spanBatch: TelemetryBatchOptions = TelemetryBatchOptions(),
        transport: any HTTPTransport = URLSessionTransport(),
        logger: Logger = IntrospectionSDK.silentLogger,
        additionalHeaders: [String: String] = [:],
        compression: TelemetryCompression? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.compression = compression
        self.logBatch = logBatch
        self.spanBatch = spanBatch
        self.transport = transport
        self.logger = logger
        self.additionalHeaders = additionalHeaders
        self.environment = environment
    }
}

/// Settings after `explicit > environment > default`.
struct ResolvedTelemetry: Sendable, Equatable {
    struct Batch: Sendable, Equatable {
        var scheduleDelay: Duration
        var exportTimeout: Duration
        var maxQueueSize: Int
        var maxExportBatchSize: Int
    }

    var baseURL: URL
    var serviceName: String
    var headers: [String: String]
    var compression: TelemetryCompression
    var logBatch: Batch
    var spanBatch: Batch

    init(baseURL: URL?, serviceName: String?, options: TelemetryOptions) throws {
        let env = options.environment
        if let baseURL {
            self.baseURL = Self.normalize(baseURL)
        } else if let value = env[TelemetryEnvironment.baseOTelURL] {
            guard !value.isEmpty, let url = URL(string: value) else {
                throw IntrospectionError(kind: .invalidRequest, message: "\(TelemetryEnvironment.baseOTelURL) is not a URL: '\(value)'")
            }
            self.baseURL = Self.normalize(url)
        } else {
            self.baseURL = TelemetryEnvironment.defaultBaseOTelURL
        }
        self.serviceName =
            serviceName ?? env[TelemetryEnvironment.serviceName].flatMap { $0.isEmpty ? nil : $0 }
            ?? TelemetryEnvironment.defaultServiceName
        compression =
            options.compression ?? env[TelemetryEnvironment.otlpCompression].flatMap { TelemetryCompression(rawValue: $0.lowercased()) }
            ?? .none
        headers = Self.headers(env[TelemetryEnvironment.otlpHeaders]).merging(options.additionalHeaders) { _, explicit in explicit }
        logBatch = Self.batch(
            options.logBatch, env: env,
            keys: (
                TelemetryEnvironment.logScheduleDelay, TelemetryEnvironment.logExportTimeout, TelemetryEnvironment.logMaxQueueSize,
                TelemetryEnvironment.logMaxExportBatchSize
            ), defaults: Batch(scheduleDelay: .seconds(5), exportTimeout: .seconds(30), maxQueueSize: 2048, maxExportBatchSize: 100))
        spanBatch = Self.batch(
            options.spanBatch, env: env,
            keys: (
                TelemetryEnvironment.spanScheduleDelay, TelemetryEnvironment.spanExportTimeout, TelemetryEnvironment.spanMaxQueueSize,
                TelemetryEnvironment.spanMaxExportBatchSize
            ), defaults: Batch(scheduleDelay: .seconds(5), exportTimeout: .seconds(30), maxQueueSize: 2048, maxExportBatchSize: 512))
    }

    private static func batch(
        _ explicit: TelemetryBatchOptions, env: [String: String], keys: (String, String, String, String), defaults: Batch
    ) -> Batch {
        func positive(_ key: String) -> Int? {
            env[key].flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }.flatMap { $0 > 0 ? $0 : nil }
        }
        return Batch(
            scheduleDelay: explicit.scheduleDelay ?? positive(keys.0).map { .milliseconds($0) } ?? defaults.scheduleDelay,
            exportTimeout: explicit.exportTimeout ?? positive(keys.1).map { .milliseconds($0) } ?? defaults.exportTimeout,
            maxQueueSize: explicit.maxQueueSize ?? positive(keys.2) ?? defaults.maxQueueSize,
            maxExportBatchSize: explicit.maxExportBatchSize ?? positive(keys.3) ?? defaults.maxExportBatchSize
        )
    }

    static func headers(_ value: String?) -> [String: String] {
        var headers: [String: String] = [:]
        for pair in (value ?? "").split(separator: ",") {
            let parts = pair.split(separator: "=", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, !parts[0].isEmpty else { continue }
            headers[parts[0].removingPercentEncoding ?? parts[0]] = parts[1].removingPercentEncoding ?? parts[1]
        }
        return headers
    }

    /// Accepts a base with or without a trailing `/`, `/v1/logs` or `/v1/traces`, as the other SDKs do.
    static func normalize(_ url: URL) -> URL {
        var text = url.absoluteString
        while text.hasSuffix("/") { text.removeLast() }
        for suffix in ["/v1/logs", "/v1/traces"] where text.hasSuffix(suffix) {
            text.removeLast(suffix.count)
        }
        return URL(string: text) ?? url
    }

    /// The token from the environment, for the `token: nil` initializers.
    static func token(_ explicit: String?, environment: [String: String]) throws -> String {
        if let explicit, !explicit.isEmpty { return explicit }
        if let value = environment[TelemetryEnvironment.token], !value.isEmpty { return value }
        throw IntrospectionError(kind: .invalidRequest, message: "\(TelemetryEnvironment.token) is not set and no token was passed")
    }
}

extension Duration {
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}

/// A credential read on every request, for example the current session token of an app.
struct ClosureCredentials: CredentialProvider {
    let token: @Sendable () async throws -> String?

    func authorization() async throws -> String? {
        try await token().map { "Bearer \($0)" }
    }
}
#endif
