#if Telemetry
import Foundation
import IntrospectionSDK
import OpenTelemetryApi
import OpenTelemetryProtocolExporterCommon
import OpenTelemetryProtocolExporterHttp
import OpenTelemetrySdk
import Synchronization

/// Exports gen_ai spans over OTLP/HTTP to `<base>/v1/traces` (`IntrospectionSpanProcessor` in the other SDKs).
///
/// A span is kept only when it carries `gen_ai.provider.name`, `gen_ai.operation.name`, `gen_ai.request.model`,
/// `gen_ai.input.messages` or `gen_ai.output.messages`. Each kept span gets the conversation (from
/// ``TelemetryContext``, else its own attribute, else an id shared by its trace), the agent and the end-user identity
/// scoped where it ended, and `gen_ai.operation.name = chat` when it has messages but no operation.
///
/// ``IntrospectionTelemetry`` installs one; add one yourself to a `TracerProviderBuilder` you already own.
public final class IntrospectionSpanProcessor: SpanProcessor {
    public let isStartRequired = false
    public let isEndRequired = true
    private let batch: BatchSpanProcessor
    private let enrichment: SpanEnrichment

    /// Export with `credentials`. Unset settings come from the environment, then the defaults.
    public convenience init(credentials: any CredentialProvider, baseURL: URL? = nil, options: TelemetryOptions = TelemetryOptions()) throws
    {
        self.init(
            credentials: credentials, resolved: try ResolvedTelemetry(baseURL: baseURL, serviceName: nil, options: options),
            options: options)
    }

    /// Export with a fixed token; nil reads `INTROSPECTION_TOKEN`.
    public convenience init(token: String? = nil, baseURL: URL? = nil, options: TelemetryOptions = TelemetryOptions()) throws {
        let token = try ResolvedTelemetry.token(token, environment: options.environment)
        try self.init(credentials: BearerToken(token), baseURL: baseURL, options: options)
    }

    /// Everything from the environment: `INTROSPECTION_TOKEN` (required), `INTROSPECTION_BASE_OTEL_URL` and the
    /// `OTEL_BSP_*` batch settings.
    public static func fromEnvironment(options: TelemetryOptions = TelemetryOptions()) throws -> IntrospectionSpanProcessor {
        try IntrospectionSpanProcessor(token: nil, options: options)
    }

    init(credentials: any CredentialProvider, resolved: ResolvedTelemetry, options: TelemetryOptions) {
        let settings = resolved.spanBatch
        let exporter = OtlpHttpTraceExporter(
            endpoint: resolved.baseURL.appendingPathComponent("v1/traces"),
            config: OtlpConfiguration(timeout: settings.exportTimeout.timeInterval),
            httpClient: OTLPTransport(
                resolved: resolved, credentials: credentials, options: options, timeout: settings.exportTimeout),
            envVarHeaders: nil, requeueOnFailure: false)
        let enrichment = SpanEnrichment()
        self.enrichment = enrichment
        batch = BatchSpanProcessor(
            spanExporter: exporter, scheduleDelay: settings.scheduleDelay.timeInterval, exportTimeout: settings.exportTimeout.timeInterval,
            maxQueueSize: settings.maxQueueSize, maxExportBatchSize: settings.maxExportBatchSize,
            willExportCallback: { spans in enrichment.apply(to: &spans) })
    }

    public func onStart(parentContext: SpanContext?, span: any ReadableSpan) {}

    public func onEnd(span: any ReadableSpan) {
        let data = span.toSpanData()
        guard SpanEnrichment.isGenAI(data.attributes) else { return }
        enrichment.record(data, context: TelemetryContext.current)
        batch.onEnd(span: span)
    }

    public func shutdown(explicitTimeout: TimeInterval?) {
        batch.shutdown(explicitTimeout: explicitTimeout)
    }

    public func forceFlush(timeout: TimeInterval?) {
        batch.forceFlush(timeout: timeout)
    }
}

/// The attributes a span ends with, held until the batch exports it: a span's own attributes are fixed once it ends.
final class SpanEnrichment: Sendable {
    private struct State {
        var pending: [SpanId: [String: AttributeValue]] = [:]
        var pendingOrder: [SpanId] = []
        var conversations: [TraceId: String] = [:]
        var conversationOrder: [TraceId] = []
    }

    static let maxTracked = 4096
    private static let markers = [
        GenAIAttributes.providerName, GenAIAttributes.operationName, GenAIAttributes.requestModel, GenAIAttributes.inputMessages,
        GenAIAttributes.outputMessages,
    ]
    private let state = Mutex(State())

    static func isGenAI(_ attributes: [String: AttributeValue]) -> Bool {
        markers.contains { attributes[$0] != nil }
    }

    func record(_ span: SpanData, context: TelemetryContext) {
        var attributes = span.attributes
        attributes.removeValue(forKey: "gen_ai.system")
        if let conversationId = context.conversationId {
            attributes[GenAIAttributes.conversationId] = .string(conversationId)
        } else if attributes[GenAIAttributes.conversationId] == nil {
            attributes[GenAIAttributes.conversationId] = .string(conversation(for: span.traceId))
        }
        if attributes[GenAIAttributes.operationName] == nil,
            attributes[GenAIAttributes.inputMessages] != nil || attributes[GenAIAttributes.outputMessages] != nil
        {
            attributes[GenAIAttributes.operationName] = .string(GenAIOperationNames.chat)
        }
        if let agentName = context.agentName { attributes[GenAIAttributes.agentName] = .string(agentName) }
        if let agentId = context.agentId { attributes[GenAIAttributes.agentId] = .string(agentId) }
        if let userId = context.userId { attributes[LogAttributes.identityUserId] = .string(userId) }
        if let anonymousId = context.anonymousId { attributes[LogAttributes.identityAnonymousId] = .string(anonymousId) }
        let finished = attributes
        state.withLock { state in
            if state.pending.updateValue(finished, forKey: span.spanId) == nil { state.pendingOrder.append(span.spanId) }
            while state.pendingOrder.count > Self.maxTracked {
                state.pending.removeValue(forKey: state.pendingOrder.removeFirst())
            }
        }
    }

    func apply(to spans: inout [SpanData]) {
        let ids = Set(spans.map(\.spanId))
        let found = state.withLock { state in
            let found = state.pending.filter { ids.contains($0.key) }
            for id in found.keys { state.pending.removeValue(forKey: id) }
            state.pendingOrder.removeAll { found[$0] != nil }
            return found
        }
        for index in spans.indices {
            guard let attributes = found[spans[index].spanId] else { continue }
            // The exporter derives the dropped count from the total, so the total moves with the attributes.
            let dropped = max(0, spans[index].totalAttributeCount - spans[index].attributes.count)
            spans[index].settingAttributes(attributes)
            spans[index].settingTotalAttributeCount(dropped + attributes.count)
        }
    }

    private func conversation(for traceId: TraceId) -> String {
        state.withLock { state in
            if let existing = state.conversations[traceId] { return existing }
            let id = TelemetryContext.newConversationId()
            state.conversations[traceId] = id
            state.conversationOrder.append(traceId)
            while state.conversationOrder.count > Self.maxTracked {
                state.conversations.removeValue(forKey: state.conversationOrder.removeFirst())
            }
            return id
        }
    }
}
#endif
