import Foundation
import Logging
import Synchronization

/// Severity of a custom event, with its OpenTelemetry severity number.
public enum LogEventSeverity: String, Sendable, Hashable, CaseIterable {
    case debug = "DEBUG"
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"

    /// The OpenTelemetry `SeverityNumber`.
    public var number: Int {
        switch self {
        case .debug: 5
        case .info: 9
        case .warn: 13
        case .error: 17
        }
    }
}

/// The end user a custom event is about. The platform replaces these with the verified identity of the
/// token that sent the event when the token carries one.
public struct EventIdentity: Sendable, Hashable {
    public var userId: String?
    public var anonymousId: String?

    public init(userId: String? = nil, anonymousId: String? = nil) {
        self.userId = userId
        self.anonymousId = anonymousId
    }
}

/// Writes custom events: OpenTelemetry log records sent over OTLP/HTTP (JSON) to `<otelURL>/v1/logs`, with the
/// Data Plane credentials. Read them back through ``EventsAPI`` as ``IntrospectionEventName/track`` events.
///
/// Events are buffered and sent in batches: when `maxBatchSize` are waiting, after `flushInterval`, or on
/// ``flush()``. Call ``flush()`` before the app is suspended. Logging never blocks and never throws for a delivery
/// failure: failures are logged to the client's `logger` and the batch is dropped.
///
/// The platform keeps an event only when the sending token grants `telemetry:write`, and drops it silently
/// otherwise. API keys always carry it; an Application's tokens carry it when the Application's `allowed_scopes`
/// do (or are unset).
public final class EventLogger: Sendable {
    public struct Configuration: Sendable {
        /// Sent as the resource's `service.name`.
        public var serviceName: String
        /// Events per request; reaching it sends a batch immediately.
        public var maxBatchSize: Int
        /// Events held while unsent; an event logged beyond it is dropped with a warning.
        public var maxQueueSize: Int
        /// How long the first unsent event waits before a batch is sent.
        public var flushInterval: Duration
        /// Default identity for every event; a per-call identity overrides it field by field.
        public var identity: EventIdentity?

        public init(
            serviceName: String = "introspection-client",
            maxBatchSize: Int = 100,
            maxQueueSize: Int = 2048,
            flushInterval: Duration = .seconds(5),
            identity: EventIdentity? = nil
        ) {
            self.serviceName = serviceName
            self.maxBatchSize = max(1, maxBatchSize)
            self.maxQueueSize = max(1, maxQueueSize)
            self.flushInterval = flushInterval
            self.identity = identity
        }
    }

    /// The hosted OTLP endpoint, used when the client configuration names none.
    public static let defaultOTelURL = URL(string: "https://otel.introspection.dev")!

    private struct State {
        var buffer: [OTLPLogRecord] = []
        var timer: Task<Void, Never>?
        var exporter: Task<Void, Never>?
    }

    public let configuration: Configuration
    /// The OTLP base URL; records go to `<otelURL>/v1/logs`.
    public let otelURL: URL
    private let http: @Sendable () -> HTTPClient
    private let now: @Sendable () -> Date
    private let state = Mutex(State())

    /// Send with `http`'s credentials, transport and options to `otelURL` (a trailing `/v1/logs` is accepted).
    public convenience init(otelURL: URL, http: HTTPClient, configuration: Configuration = Configuration()) {
        self.init(otelURL: otelURL, http: http, configuration: configuration, now: { Date() })
    }

    convenience init(otelURL: URL, http: HTTPClient, configuration: Configuration, now: @escaping @Sendable () -> Date) {
        let base = Self.normalize(otelURL)
        let client = http.with(baseURL: base, credentials: http.credentials)
        self.init(base: base, http: { client }, configuration: configuration, now: now)
    }

    /// Send with the connection's current Data Plane credentials, so a ``Runner`` refreshed later keeps working.
    public convenience init(otelURL: URL, connection: some DataPlaneConnection, configuration: Configuration = Configuration()) {
        let base = Self.normalize(otelURL)
        self.init(
            base: base,
            http: {
                let dataPlane = connection.dataPlane
                return dataPlane.with(baseURL: base, credentials: dataPlane.credentials)
            }, configuration: configuration, now: { Date() })
    }

    private init(
        base: URL, http: @escaping @Sendable () -> HTTPClient, configuration: Configuration, now: @escaping @Sendable () -> Date
    ) {
        otelURL = base
        self.http = http
        self.configuration = configuration
        self.now = now
    }

    private static func normalize(_ url: URL) -> URL {
        var text = url.absoluteString
        while text.hasSuffix("/") { text.removeLast() }
        if text.hasSuffix("/v1/logs") { text.removeLast("/v1/logs".count) }
        return URL(string: text) ?? url
    }

    /// The reserved prefix `name` falls under, if any.
    public static func reservedPrefix(of name: String) -> String? {
        LogAttributes.reservedEventNamePrefixes.first { name.hasPrefix($0) }
    }

    /// Log an app event under a name of your own, such as `"ark.feed.entry"`.
    ///
    /// `attributes` are written under `properties.*`, where the ``IntrospectionEventName/track`` projection reads
    /// them; nulls are omitted, and arrays and objects are sent as JSON strings. Pass a stable `eventId` when the
    /// same event may be logged twice: readers dedupe on it.
    ///
    /// - Throws: ``IntrospectionError`` with kind `invalidRequest` when `name` is empty or starts with a reserved
    ///   prefix (`introspection.`, `gen_ai.`). Nothing is queued then.
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
        let observed = now()
        let record = OTLPLogRecord(
            timeUnixNano: Self.unixNano(timestamp ?? observed),
            observedTimeUnixNano: Self.unixNano(observed),
            severityNumber: severity.number,
            severityText: severity.rawValue,
            eventName: name,
            attributes: attributeList(name: name, properties: attributes, eventId: eventId, identity: identity)
        )
        let accepted = state.withLock { state in
            guard state.buffer.count < configuration.maxQueueSize else { return false }
            state.buffer.append(record)
            if state.buffer.count >= configuration.maxBatchSize {
                startExport(&state)
            } else if state.timer == nil, state.exporter == nil {
                let interval = configuration.flushInterval
                state.timer = Task {
                    do { try await Task.sleep(for: interval) } catch { return }
                    self.state.withLock { state in
                        state.timer = nil
                        self.startExport(&state)
                    }
                }
            }
            return true
        }
        if !accepted {
            logger.warning("Custom event dropped: the event queue is full", metadata: ["event.name": "\(name)"])
        }
    }

    /// Track an analytics event: ``logEvent(_:attributes:eventId:timestamp:identity:severity:)`` at `INFO`.
    public func track(_ name: String, properties: JSONObject? = nil, eventId: String? = nil) throws {
        try logEvent(name, attributes: properties, eventId: eventId)
    }

    /// Send every event logged so far, and return once the requests have finished.
    public func flush() async {
        while true {
            let exporter = state.withLock { state in
                if !state.buffer.isEmpty { startExport(&state) }
                return state.exporter
            }
            guard let exporter else { return }
            await exporter.value
        }
    }

    private var logger: Logger { http().options.logger }

    private func startExport(_ state: inout State) {
        guard state.exporter == nil else { return }
        state.timer?.cancel()
        state.timer = nil
        state.exporter = Task { await self.drain() }
    }

    private func drain() async {
        while true {
            let batch: [OTLPLogRecord]? = state.withLock { state in
                guard !state.buffer.isEmpty else {
                    state.exporter = nil
                    return nil
                }
                let count = min(configuration.maxBatchSize, state.buffer.count)
                let batch = Array(state.buffer.prefix(count))
                state.buffer.removeFirst(count)
                return batch
            }
            guard let batch else { return }
            await export(batch)
        }
    }

    private func export(_ records: [OTLPLogRecord]) async {
        let client = http()
        let logger = client.options.logger
        do {
            let body = try Self.encoder.encode(request(records))
            let response = try await client.send("POST", "/v1/logs", body: .raw(body, contentType: "application/json"))
            let rejected = (try? JSONCoding.decoder.decode(JSONValue.self, from: response.body))?["partialSuccess"]?[
                "rejectedLogRecords"]
            if let rejected, (rejected.intValue ?? rejected.stringValue.flatMap({ Int($0) }) ?? 0) > 0 {
                logger.warning(
                    "Custom events rejected by the collector",
                    metadata: ["count": "\(records.count)", "rejected": "\(rejected)"])
            } else {
                logger.debug("Custom events sent", metadata: ["count": "\(records.count)"])
            }
        } catch {
            logger.warning("Could not send custom events; they were dropped", metadata: ["count": "\(records.count)", "error": "\(error)"])
        }
    }

    func request(_ records: [OTLPLogRecord]) -> OTLPExportLogsRequest {
        OTLPExportLogsRequest(resourceLogs: [
            OTLPResourceLogs(
                resource: OTLPResource(attributes: [
                    OTLPKeyValue("service.name", .string(configuration.serviceName)),
                    OTLPKeyValue("telemetry.sdk.language", .string("swift")),
                    OTLPKeyValue("telemetry.sdk.name", .string("introspection-sdk")),
                    OTLPKeyValue("telemetry.sdk.version", .string(IntrospectionSDK.version)),
                ]),
                scopeLogs: [
                    OTLPScopeLogs(scope: OTLPScope(name: "introspection-sdk", version: IntrospectionSDK.version), logRecords: records)
                ]
            )
        ])
    }

    private func attributeList(name: String, properties: JSONObject?, eventId: String?, identity: EventIdentity?) -> [OTLPKeyValue] {
        var attributes = [
            OTLPKeyValue(LogAttributes.eventName, .string(name)),
            OTLPKeyValue(LogAttributes.eventId, .string(eventId.flatMap { $0.isEmpty ? nil : $0 } ?? Self.generateEventId(now: now()))),
        ]
        if let userId = identity?.userId ?? configuration.identity?.userId {
            attributes.append(OTLPKeyValue(LogAttributes.identityUserId, .string(userId)))
        }
        if let anonymousId = identity?.anonymousId ?? configuration.identity?.anonymousId {
            attributes.append(OTLPKeyValue(LogAttributes.identityAnonymousId, .string(anonymousId)))
        }
        for (key, value) in (properties ?? [:]).sorted(by: { $0.key < $1.key }) {
            if let value = OTLPAnyValue(value) {
                attributes.append(OTLPKeyValue(LogAttributes.propertiesPrefix + key, value))
            }
        }
        return attributes
    }

    /// `intro_event_<hex milliseconds>-<8 hex>`, the shape the other SDKs generate.
    static func generateEventId(now: Date) -> String {
        let millis = UInt64(max(0, now.timeIntervalSince1970 * 1000))
        let random = String(UInt32.random(in: .min ... .max), radix: 16)
        return "intro_event_\(String(millis, radix: 16))-\(String(repeating: "0", count: 8 - random.count))\(random)"
    }

    static func unixNano(_ date: Date) -> String {
        let micros = (date.timeIntervalSince1970 * 1_000_000).rounded()
        return micros > 0 ? String(UInt64(micros) * 1000) : "0"
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()
}

// MARK: OTLP/JSON

struct OTLPExportLogsRequest: Encodable, Sendable {
    var resourceLogs: [OTLPResourceLogs]
}

struct OTLPResourceLogs: Encodable, Sendable {
    var resource: OTLPResource
    var scopeLogs: [OTLPScopeLogs]
}

struct OTLPResource: Encodable, Sendable {
    var attributes: [OTLPKeyValue]
}

struct OTLPScopeLogs: Encodable, Sendable {
    var scope: OTLPScope
    var logRecords: [OTLPLogRecord]
}

struct OTLPScope: Encodable, Sendable {
    var name: String
    var version: String
}

struct OTLPLogRecord: Encodable, Sendable {
    /// OTLP/JSON writes 64-bit integers as decimal strings.
    var timeUnixNano: String
    var observedTimeUnixNano: String
    var severityNumber: Int
    var severityText: String
    var eventName: String
    var attributes: [OTLPKeyValue]
}

struct OTLPKeyValue: Encodable, Sendable {
    var key: String
    var value: OTLPAnyValue

    init(_ key: String, _ value: OTLPAnyValue) {
        self.key = key
        self.value = value
    }
}

enum OTLPAnyValue: Encodable, Sendable, Equatable {
    case string(String)
    case bool(Bool)
    case int(Int64)
    case double(Double)

    /// Nil for `null`. Integral numbers are integers, as the JavaScript SDK sends them; a non-finite number
    /// is sent as its description, since JSON has no literal for it.
    init?(_ value: JSONValue) {
        switch value {
        case .null: return nil
        case let .string(text): self = .string(text)
        case let .bool(flag): self = .bool(flag)
        case let .number(number):
            if !number.isFinite {
                self = .string(String(describing: number))
            } else if number.rounded() == number, abs(number) < 9_007_199_254_740_992 {
                self = .int(Int64(number))
            } else {
                self = .double(number)
            }
        case .array, .object:
            let data = (try? EventLogger.encoder.encode(value)) ?? Data()
            self = .string(String(decoding: data, as: UTF8.self))
        }
    }

    private enum CodingKeys: String, CodingKey {
        case stringValue, boolValue, intValue, doubleValue
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .string(value): try container.encode(value, forKey: .stringValue)
        case let .bool(value): try container.encode(value, forKey: .boolValue)
        case let .int(value): try container.encode(String(value), forKey: .intValue)
        case let .double(value): try container.encode(value, forKey: .doubleValue)
        }
    }
}

extension IntrospectionClient {
    /// Log a custom event with ``eventLogger``.
    public func logEvent(
        _ name: String,
        attributes: JSONObject? = nil,
        eventId: String? = nil,
        timestamp: Date? = nil,
        identity: EventIdentity? = nil,
        severity: LogEventSeverity = .info
    ) throws {
        try eventLogger.logEvent(
            name, attributes: attributes, eventId: eventId, timestamp: timestamp, identity: identity, severity: severity)
    }

    /// Track an analytics event with ``eventLogger``.
    public func track(_ name: String, properties: JSONObject? = nil, eventId: String? = nil) throws {
        try eventLogger.track(name, properties: properties, eventId: eventId)
    }
}
