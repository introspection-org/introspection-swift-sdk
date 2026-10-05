#if Telemetry
import Foundation
import IntrospectionSDK
import OpenTelemetryApi
import OpenTelemetrySdk

/// One part of a gen_ai message, in the OpenTelemetry GenAI message format the platform reads.
public enum GenAIMessagePart: Sendable, Hashable, Encodable {
    case text(String)
    case toolCall(id: String, name: String, arguments: String)
    case toolCallResponse(id: String, response: String?)
    case thinking(content: String?, signature: String?)

    private enum CodingKeys: String, CodingKey {
        case type, content, id, name, arguments, response, signature
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(content):
            try container.encode("text", forKey: .type)
            try container.encode(content, forKey: .content)
        case let .toolCall(id, name, arguments):
            try container.encode("tool_call", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(arguments, forKey: .arguments)
        case let .toolCallResponse(id, response):
            try container.encode("tool_call_response", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encodeIfPresent(response, forKey: .response)
        case let .thinking(content, signature):
            try container.encode("thinking", forKey: .type)
            try container.encodeIfPresent(content, forKey: .content)
            try container.encodeIfPresent(signature, forKey: .signature)
        }
    }
}

/// A gen_ai input or output message (`gen_ai.input.messages`, `gen_ai.output.messages`).
public struct GenAIMessage: Sendable, Hashable, Encodable {
    public var role: String
    public var parts: [GenAIMessagePart]
    /// Output messages only.
    public var finishReason: String?

    public init(role: String, parts: [GenAIMessagePart], finishReason: String? = nil) {
        self.role = role
        self.parts = parts
        self.finishReason = finishReason
    }

    public static func user(_ text: String) -> GenAIMessage { GenAIMessage(role: "user", parts: [.text(text)]) }
    public static func system(_ text: String) -> GenAIMessage { GenAIMessage(role: "system", parts: [.text(text)]) }
    /// An assistant message; as an output message, pass `finishReason` (such as `"stop"`).
    public static func assistant(_ text: String, finishReason: String? = nil) -> GenAIMessage {
        GenAIMessage(role: "assistant", parts: [.text(text)], finishReason: finishReason)
    }

    private enum CodingKeys: String, CodingKey {
        case role, parts
        case finishReason = "finish_reason"
    }
}

extension Span {
    /// Set `gen_ai.input.messages`.
    public func setGenAIInputMessages(_ messages: [GenAIMessage]) {
        setAttribute(key: GenAIAttributes.inputMessages, value: jsonString(messages))
    }

    /// Set `gen_ai.output.messages`.
    public func setGenAIOutputMessages(_ messages: [GenAIMessage]) {
        setAttribute(key: GenAIAttributes.outputMessages, value: jsonString(messages))
    }

    /// Set the `gen_ai.usage.*` token counts that are given.
    public func setGenAIUsage(inputTokens: Int? = nil, outputTokens: Int? = nil, cacheReadInputTokens: Int? = nil) {
        if let inputTokens { setAttribute(key: GenAIAttributes.usageInputTokens, value: inputTokens) }
        if let outputTokens { setAttribute(key: GenAIAttributes.usageOutputTokens, value: outputTokens) }
        if let cacheReadInputTokens { setAttribute(key: GenAIAttributes.usageCacheReadInputTokens, value: cacheReadInputTokens) }
    }

    /// Set the `gen_ai.response.*` attributes that are given.
    public func setGenAIResponse(model: String? = nil, id: String? = nil, finishReasons: [String]? = nil) {
        if let model { setAttribute(key: GenAIAttributes.responseModel, value: model) }
        if let id { setAttribute(key: GenAIAttributes.responseId, value: id) }
        if let finishReasons {
            setAttribute(
                key: GenAIAttributes.responseFinishReasons, value: .array(AttributeArray(values: finishReasons.map { .string($0) })))
        }
    }
}

extension IntrospectionTelemetry {
    /// Run `body` in a client span named `"<operation> <model>"` carrying `gen_ai.operation.name`,
    /// `gen_ai.request.model` and `gen_ai.provider.name`, active for spans started inside it. The span ends when
    /// `body` returns; a thrown error marks it failed and is rethrown.
    public func withGenAISpan<T>(
        _ operation: String = GenAIOperationNames.chat, model: String? = nil, provider: String? = nil,
        body: (any Span) async throws -> T
    ) async throws -> T {
        let span = tracer.spanBuilder(spanName: model.map { "\(operation) \($0)" } ?? operation).setSpanKind(spanKind: .client).startSpan()
        span.setAttribute(key: GenAIAttributes.operationName, value: operation)
        if let model { span.setAttribute(key: GenAIAttributes.requestModel, value: model) }
        if let provider { span.setAttribute(key: GenAIAttributes.providerName, value: provider) }
        // OpenTelemetry's async `withActiveSpan` runs its operation `@concurrent`; the SDK's spans are Sendable
        // `ReadableSpan`s, and `body` stays on this task.
        nonisolated(unsafe) let body = body
        do {
            let result: T
            if let active = span as? any ReadableSpan {
                result = try await OpenTelemetry.instance.contextProvider.withActiveSpan(active) { try await body(active) }
            } else {
                result = try await body(span)
            }
            span.end()
            return result
        } catch {
            span.status = .error(description: "\(error)")
            span.end()
            throw error
        }
    }
}
#endif
