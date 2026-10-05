#if Telemetry
import Foundation
import IntrospectionSDK
import OpenTelemetryApi
import OpenTelemetrySdk
import Synchronization

/// Traces and custom events for Introspection on one OpenTelemetry setup: the `init()` of the JavaScript and Python
/// SDKs. It builds a tracer provider with an ``IntrospectionSpanProcessor`` and an ``IntrospectionLogs``, both
/// exporting to the same OTLP base URL with the same credentials and service name.
///
/// ```swift
/// let telemetry = try IntrospectionTelemetry(credentials: auth.credentials)
/// try await IntrospectionTelemetry.withUserId("user_123") {
///     try telemetry.logEvent("ark.feed.entry", attributes: ["entry_id": "e_1"])
///     try await telemetry.withGenAISpan(model: "gpt-5") { span in
///         span.setGenAIInputMessages([.user("Hi")])
///     }
/// }
/// await telemetry.flush()
/// ```
public final class IntrospectionTelemetry: Sendable {
    /// Custom events, feedback and identify.
    public let logs: IntrospectionLogs
    /// Spans from tracers of this provider go through the ``IntrospectionSpanProcessor``.
    nonisolated(unsafe) public let tracerProvider: TracerProviderSdk
    /// The tracer ``withGenAISpan(_:model:provider:body:)`` uses.
    nonisolated(unsafe) public let tracer: any Tracer

    /// Export with `credentials` (for example `client.dataPlane.credentials` or an `AuthClient`'s). Unset settings
    /// come from the environment, then the defaults.
    public convenience init(
        credentials: any CredentialProvider, baseURL: URL? = nil, serviceName: String? = nil, options: TelemetryOptions = TelemetryOptions()
    ) throws {
        let resolved = try ResolvedTelemetry(baseURL: baseURL, serviceName: serviceName, options: options)
        try self.init(credentials: credentials, resolved: resolved, options: options)
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

    /// Everything from the environment; see ``TelemetryEnvironment``.
    public static func fromEnvironment(options: TelemetryOptions = TelemetryOptions()) throws -> IntrospectionTelemetry {
        try IntrospectionTelemetry(token: nil, options: options)
    }

    init(credentials: any CredentialProvider, resolved: ResolvedTelemetry, options: TelemetryOptions) throws {
        logs = try IntrospectionLogs(credentials: credentials, resolved: resolved, options: options, now: { Date() })
        tracerProvider = TracerProviderBuilder()
            .with(resource: telemetryResource(serviceName: resolved.serviceName))
            .add(spanProcessor: IntrospectionSpanProcessor(credentials: credentials, resolved: resolved, options: options))
            .build()
        tracer = tracerProvider.get(instrumentationName: telemetryScopeName, instrumentationVersion: IntrospectionSDK.version)
    }

    private static let installed = Mutex<IntrospectionTelemetry?>(nil)

    /// The telemetry ``bootstrap(credentials:baseURL:serviceName:options:)`` installed (`getClient()` and
    /// `getTracerProvider()` in the other SDKs); nil before it, and after its ``shutdown()``.
    public static var current: IntrospectionTelemetry? { installed.withLock { $0 } }

    /// The `init()` of the other SDKs: configure both signals, register them as the global OpenTelemetry providers
    /// and keep them as ``current``. Idempotent: once installed, later calls return the installed telemetry.
    @discardableResult
    public static func bootstrap(
        credentials: any CredentialProvider, baseURL: URL? = nil, serviceName: String? = nil, options: TelemetryOptions = TelemetryOptions()
    ) throws -> IntrospectionTelemetry {
        try install { try IntrospectionTelemetry(credentials: credentials, baseURL: baseURL, serviceName: serviceName, options: options) }
    }

    /// ``bootstrap(credentials:baseURL:serviceName:options:)`` with a fixed token; nil reads `INTROSPECTION_TOKEN`.
    @discardableResult
    public static func bootstrap(
        token: String? = nil, baseURL: URL? = nil, serviceName: String? = nil, options: TelemetryOptions = TelemetryOptions()
    ) throws -> IntrospectionTelemetry {
        try install { try IntrospectionTelemetry(token: token, baseURL: baseURL, serviceName: serviceName, options: options) }
    }

    private static func install(_ make: () throws -> IntrospectionTelemetry) throws -> IntrospectionTelemetry {
        try installed.withLock { installed in
            if let installed { return installed }
            let telemetry = try make()
            telemetry.registerGlobally()
            installed = telemetry
            return telemetry
        }
    }

    /// Make these the global OpenTelemetry tracer and logger providers, so other instrumentation exports here too.
    public func registerGlobally() {
        OpenTelemetry.registerTracerProvider(tracerProvider: tracerProvider)
        OpenTelemetry.registerLoggerProvider(loggerProvider: logs.loggerProvider)
    }

    /// ``IntrospectionLogs/logEvent(_:attributes:eventId:timestamp:identity:severity:)``.
    public func logEvent(
        _ name: String, attributes: JSONObject? = nil, eventId: String? = nil, timestamp: Date? = nil, identity: EventIdentity? = nil,
        severity: LogEventSeverity = .info
    ) throws {
        try logs.logEvent(name, attributes: attributes, eventId: eventId, timestamp: timestamp, identity: identity, severity: severity)
    }

    /// ``IntrospectionLogs/track(_:properties:eventId:)``.
    public func track(_ name: String, properties: JSONObject? = nil, eventId: String? = nil) throws {
        try logs.track(name, properties: properties, eventId: eventId)
    }

    /// ``IntrospectionLogs/feedback(_:comments:conversationId:previousResponseId:eventId:properties:)``.
    public func feedback(
        _ name: String, comments: String? = nil, conversationId: String? = nil, previousResponseId: String? = nil,
        eventId: String? = nil, properties: JSONObject? = nil
    ) {
        logs.feedback(
            name, comments: comments, conversationId: conversationId, previousResponseId: previousResponseId, eventId: eventId,
            properties: properties)
    }

    /// ``IntrospectionLogs/identify(_:traits:anonymousId:eventId:)``.
    public func identify(_ userId: String, traits: JSONObject? = nil, anonymousId: String? = nil, eventId: String? = nil) {
        logs.identify(userId, traits: traits, anonymousId: anonymousId, eventId: eventId)
    }

    /// Export every span and record so far, and return once the requests have finished.
    public func flush() async {
        await offPool { self.tracerProvider.forceFlush() }
        await logs.flush()
    }

    /// Flush, then stop exporting. Uninstalls it when it is ``current``.
    public func shutdown() async {
        Self.installed.withLock { installed in
            if installed === self { installed = nil }
        }
        await offPool { self.tracerProvider.shutdown() }
        await logs.shutdown()
    }
}
#endif
