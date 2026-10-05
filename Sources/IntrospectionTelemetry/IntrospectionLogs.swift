#if Telemetry
import Foundation
import IntrospectionSDK
import Logging
import OpenTelemetryApi
import OpenTelemetryProtocolExporterCommon
import OpenTelemetryProtocolExporterHttp
import OpenTelemetrySdk

/// Severity of a custom event.
public enum LogEventSeverity: String, Sendable, Hashable, CaseIterable {
    case debug = "DEBUG"
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"

    var otel: Severity {
        switch self {
        case .debug: .debug
        case .info: .info
        case .warn: .warn
        case .error: .error
        }
    }
}

/// The end user an event is about. Each field set replaces the one scoped on ``TelemetryContext``. The platform
/// replaces both with the verified identity of the sending token when it carries one.
public struct EventIdentity: Sendable, Hashable {
    public var userId: String?
    public var anonymousId: String?

    public init(userId: String? = nil, anonymousId: String? = nil) {
        self.userId = userId
        self.anonymousId = anonymousId
    }
}

/// Custom events, feedback and identify calls as OpenTelemetry log records, exported over OTLP/HTTP to
/// `<base>/v1/logs` (`IntrospectionLogs` in the JavaScript, Python and Rust SDKs).
///
/// Records are batched; nothing here blocks on the network or throws for a delivery failure, which is logged to
/// ``TelemetryOptions/logger``. Call ``flush()`` before the app is suspended.
public final class IntrospectionLogs: Sendable {
    /// The resource's `service.name`.
    public let serviceName: String
    /// The OTLP base URL; records go to `<baseURL>/v1/logs`.
    public let baseURL: URL
    /// The provider, for registering globally (`OpenTelemetry.registerLoggerProvider`).
    public let loggerProvider: LoggerProviderSdk
    // Upstream types that are internally synchronized but not annotated Sendable.
    nonisolated(unsafe) private let processor: BatchLogRecordProcessor
    nonisolated(unsafe) private let otelLogger: any OpenTelemetryApi.Logger
    private let logger: Logging.Logger
    private let now: @Sendable () -> Date

    /// Export with `credentials` (for example `client.dataPlane.credentials` or an `AuthClient`'s credentials, so
    /// a refreshed session keeps working). Unset settings come from the environment, then the defaults.
    public convenience init(
        credentials: any CredentialProvider, baseURL: URL? = nil, serviceName: String? = nil, options: TelemetryOptions = TelemetryOptions()
    ) throws {
        try self.init(
            credentials: credentials, resolved: ResolvedTelemetry(baseURL: baseURL, serviceName: serviceName, options: options),
            options: options, now: { Date() })
    }

    /// Export with a fixed token; nil reads `INTROSPECTION_TOKEN`.
    public convenience init(
        token: String? = nil, baseURL: URL? = nil, serviceName: String? = nil, options: TelemetryOptions = TelemetryOptions()
    ) throws {
        let token = try ResolvedTelemetry.token(token, environment: options.environment)
        try self.init(credentials: BearerToken(token), baseURL: baseURL, serviceName: serviceName, options: options)
    }

    /// Export with a token read on every request, such as an app's current session token.
    public convenience init(
        token: @escaping @Sendable () async throws -> String?, baseURL: URL? = nil, serviceName: String? = nil,
        options: TelemetryOptions = TelemetryOptions()
    ) throws {
        try self.init(credentials: ClosureCredentials(token: token), baseURL: baseURL, serviceName: serviceName, options: options)
    }

    /// Everything from the environment: `INTROSPECTION_TOKEN` (required), `INTROSPECTION_BASE_OTEL_URL`,
    /// `INTROSPECTION_SERVICE_NAME` and the `OTEL_BLRP_*` batch settings.
    public static func fromEnvironment(options: TelemetryOptions = TelemetryOptions()) throws -> IntrospectionLogs {
        try IntrospectionLogs(token: nil, options: options)
    }

    init(
        credentials: any CredentialProvider, resolved: ResolvedTelemetry, options: TelemetryOptions, now: @escaping @Sendable () -> Date
    )
        throws
    {
        serviceName = resolved.serviceName
        baseURL = resolved.baseURL
        logger = options.logger
        self.now = now
        let batch = resolved.logBatch
        let exporter = OtlpHttpLogExporter(
            endpoint: resolved.baseURL.appendingPathComponent("v1/logs"),
            config: OtlpConfiguration(
                timeout: batch.exportTimeout.timeInterval, compression: resolved.compression == .gzip ? .gzip : .none),
            httpClient: OTLPTransport(resolved: resolved, credentials: credentials, options: options, timeout: batch.exportTimeout),
            envVarHeaders: nil, requeueOnFailure: false)
        processor = BatchLogRecordProcessor(
            logRecordExporter: exporter, scheduleDelay: batch.scheduleDelay.timeInterval, exportTimeout: batch.exportTimeout.timeInterval,
            maxQueueSize: batch.maxQueueSize, maxExportBatchSize: batch.maxExportBatchSize)
        loggerProvider = LoggerProviderBuilder().with(resource: telemetryResource(serviceName: resolved.serviceName)).with(processors: [
            processor
        ]).build()
        otelLogger = loggerProvider.loggerBuilder(instrumentationScopeName: telemetryScopeName).setInstrumentationVersion(
            IntrospectionSDK.version
        ).build()
    }

    /// The reserved prefix `name` falls under (`introspection.`, `gen_ai.`), if any.
    public static func reservedPrefix(of name: String) -> String? {
        LogAttributes.reservedEventNamePrefixes.first { name.hasPrefix($0) }
    }

    /// Log an app event under a name of your own, such as `"ark.feed.entry"` (`logEvent` in the other SDKs).
    ///
    /// `attributes` are written under `properties.*`, where the platform's `introspection.track` projection reads
    /// them: nulls are omitted, arrays and objects become JSON strings. The scoped ``TelemetryContext`` adds the
    /// identity, conversation and agent. Pass a stable `eventId` when the same event may be logged twice.
    ///
    /// - Throws: `IntrospectionError` with kind `invalidRequest` for an empty name or one under a reserved prefix.
    public func logEvent(
        _ name: String,
        attributes: JSONObject? = nil,
        eventId: String? = nil,
        timestamp: Date? = nil,
        identity: EventIdentity? = nil,
        severity: LogEventSeverity = .info
    ) throws {
        if name.isEmpty {
            throw IntrospectionError(kind: .invalidRequest, message: "logEvent: the event name must not be empty")
        }
        if let prefix = Self.reservedPrefix(of: name) {
            throw IntrospectionError(
                kind: .invalidRequest,
                message:
                    "logEvent: '\(name)' is in the reserved '\(prefix)*' namespace; use your own prefix, such as 'myapp.\(name.dropFirst(prefix.count))'"
            )
        }
        emit(name, properties: attributes, eventId: eventId, timestamp: timestamp, identity: identity, severity: severity)
    }

    /// Track an analytics event: ``logEvent(_:attributes:eventId:timestamp:identity:severity:)`` at `INFO`.
    public func track(_ name: String, properties: JSONObject? = nil, eventId: String? = nil) throws {
        try logEvent(name, attributes: properties, eventId: eventId)
    }

    /// Record feedback on a response as an `introspection.feedback` event. `properties` are extra fields; they
    /// cannot replace `name` or `comments`.
    public func feedback(
        _ name: String, comments: String? = nil, conversationId: String? = nil, previousResponseId: String? = nil,
        eventId: String? = nil, properties: JSONObject? = nil
    ) {
        var fields = properties ?? [:]
        fields["name"] = .string(name)
        if let comments { fields["comments"] = .string(comments) }
        emit(
            PlatformEventNames.feedback, properties: fields, eventId: eventId, conversationId: conversationId,
            previousResponseId: previousResponseId)
    }

    /// Record who the user is as an `identify` event; `traits` land under `context.traits.*`.
    public func identify(_ userId: String, traits: JSONObject? = nil, anonymousId: String? = nil, eventId: String? = nil) {
        emit(
            LogAttributes.identifyEventName, properties: nil, eventId: eventId,
            identity: EventIdentity(userId: userId, anonymousId: anonymousId), traits: traits)
    }

    /// Export every record logged so far, and return once the request has finished.
    public func flush() async {
        await offPool { _ = self.processor.forceFlush(explicitTimeout: nil) }
    }

    /// Flush, then stop exporting.
    public func shutdown() async {
        await offPool { _ = self.processor.shutdown(explicitTimeout: nil) }
    }

    private func emit(
        _ name: String, properties: JSONObject?, eventId: String?, timestamp: Date? = nil, identity: EventIdentity? = nil,
        severity: LogEventSeverity = .info, conversationId: String? = nil, previousResponseId: String? = nil, traits: JSONObject? = nil
    ) {
        let context = TelemetryContext.current
        let observed = now()
        var attributes: [String: AttributeValue] = [
            LogAttributes.eventName: .string(name),
            LogAttributes.eventId: .string(eventId.flatMap { $0.isEmpty ? nil : $0 } ?? Self.generateEventId(now: observed)),
        ]
        attributes[LogAttributes.identityUserId] = (identity?.userId ?? context.userId).map(AttributeValue.string)
        attributes[LogAttributes.identityAnonymousId] = (identity?.anonymousId ?? context.anonymousId).map(AttributeValue.string)
        attributes[GenAIAttributes.conversationId] = (conversationId ?? context.conversationId).map(AttributeValue.string)
        attributes[GenAIAttributes.requestPreviousResponseId] = (previousResponseId ?? context.previousResponseId).map(
            AttributeValue.string)
        attributes[GenAIAttributes.agentName] = context.agentName.map(AttributeValue.string)
        attributes[GenAIAttributes.agentId] = context.agentId.map(AttributeValue.string)
        for (key, value) in properties ?? [:] {
            attributes[LogAttributes.propertiesPrefix + key] = AttributeValue(json: value)
        }
        for (key, value) in traits ?? [:] {
            attributes[LogAttributes.traitsPrefix + key] = AttributeValue(json: value)
        }
        otelLogger.logRecordBuilder()
            .setTimestamp(timestamp ?? observed)
            .setObservedTimestamp(observed)
            .setSeverity(severity.otel)
            .setEventName(name)
            .setAttributes(attributes)
            .emit()
        logger.debug("Logged event", metadata: ["event.name": "\(name)"])
    }

    /// `intro_event_<hex milliseconds>-<8 hex>`, the shape the other SDKs generate.
    static func generateEventId(now: Date) -> String {
        let millis = UInt64(max(0, now.timeIntervalSince1970 * 1000))
        let random = String(UInt32.random(in: .min ... .max), radix: 16)
        return "intro_event_\(String(millis, radix: 16))-\(String(repeating: "0", count: 8 - random.count))\(random)"
    }
}

let telemetryScopeName = "introspection-sdk"

func telemetryResource(serviceName: String) -> Resource {
    Resource().merging(other: Resource(attributes: ["service.name": .string(serviceName)]))
}

extension AttributeValue {
    /// Nil for `null`. Integral numbers are integers, as the JavaScript SDK sends them; arrays and objects are JSON
    /// strings; a non-finite number is its description, since JSON has no literal for it.
    init?(json value: JSONValue) {
        switch value {
        case .null: return nil
        case let .string(text): self = .string(text)
        case let .bool(flag): self = .bool(flag)
        case let .number(number):
            if !number.isFinite {
                self = .string(String(describing: number))
            } else if number.rounded() == number, abs(number) < 9_007_199_254_740_992 {
                self = .int(Int(number))
            } else {
                self = .double(number)
            }
        case .array, .object:
            self = .string(jsonString(value))
        }
    }
}

let telemetryEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return encoder
}()

func jsonString(_ value: some Encodable) -> String {
    String(decoding: (try? telemetryEncoder.encode(value)) ?? Data(), as: UTF8.self)
}
#endif
