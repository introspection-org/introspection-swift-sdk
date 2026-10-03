import Foundation

// MARK: - Read window (shared by the conversations and events list reads)

/// Sort direction for the telemetry list reads. Sent as `direction`.
public struct ReadOrder: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }

    public static let asc: ReadOrder = "asc"
    public static let desc: ReadOrder = "desc"
}

/// A relative read window such as `"24h"`, `"7d"` or `"500ms"` (units `ms`, `s`, `m`, `h`, `d`, `w`).
/// The client turns it into `start_date = now - lookback` before sending.
public struct ReadLookback: Sendable, Hashable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }

    public static func milliseconds(_ value: Int) -> ReadLookback { ReadLookback("\(value)ms") }
    public static func seconds(_ value: Int) -> ReadLookback { ReadLookback("\(value)s") }
    public static func minutes(_ value: Int) -> ReadLookback { ReadLookback("\(value)m") }
    public static func hours(_ value: Int) -> ReadLookback { ReadLookback("\(value)h") }
    public static func days(_ value: Int) -> ReadLookback { ReadLookback("\(value)d") }
    public static func weeks(_ value: Int) -> ReadLookback { ReadLookback("\(value)w") }

    public var description: String { rawValue }

    /// The duration in seconds, or nil when the string is not a valid lookback.
    public var seconds: TimeInterval? {
        let text = rawValue.trimmingCharacters(in: .whitespaces)
        let digits = text.prefix { $0.isASCII && $0.isNumber }
        let unit = text.dropFirst(digits.count)
        guard !digits.isEmpty, let amount = Double(digits) else { return nil }
        let unitSeconds: Double
        switch unit {
        case "ms": unitSeconds = 0.001
        case "s": unitSeconds = 1
        case "m": unitSeconds = 60
        case "h": unitSeconds = 3_600
        case "d": unitSeconds = 86_400
        case "w": unitSeconds = 604_800
        default: return nil
        }
        return amount * unitSeconds
    }
}

/// Serialize the ergonomic window params onto the wire, validating them before any request.
func applyReadWindow(
    to query: inout Query, order: ReadOrder?, start: Date?, end: Date?, lookback: ReadLookback?, now: Date
) throws {
    if let lookback {
        guard start == nil, end == nil else {
            throw IntrospectionError(
                kind: .validation,
                message: "`lookback` is mutually exclusive with `start`/`end`: pass a relative lookback or an explicit window, not both",
                code: "invalid_request"
            )
        }
        guard let seconds = lookback.seconds else {
            throw IntrospectionError(
                kind: .validation,
                message: "Invalid `lookback` \"\(lookback.rawValue)\": expected a relative duration like \"24h\", \"7d\", or \"500ms\" (units: ms, s, m, h, d, w)",
                code: "invalid_request"
            )
        }
        query.add("start_date", now.addingTimeInterval(-seconds))
    } else {
        query.add("start_date", start)
        query.add("end_date", end)
    }
    query.add("direction", order)
}

// MARK: - GenAI span model

/// OpenTelemetry span kind.
public struct GenAISpanKind: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }

    public static let unspecified: GenAISpanKind = "UNSPECIFIED"
    public static let `internal`: GenAISpanKind = "INTERNAL"
    public static let server: GenAISpanKind = "SERVER"
    public static let client: GenAISpanKind = "CLIENT"
    public static let producer: GenAISpanKind = "PRODUCER"
    public static let consumer: GenAISpanKind = "CONSUMER"
}

/// OpenTelemetry span status code, as the API spells it (`Ok`, `Error`, `Unset`).
public struct GenAISpanStatusCode: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }

    public static let ok: GenAISpanStatusCode = "Ok"
    public static let error: GenAISpanStatusCode = "Error"
    public static let unset: GenAISpanStatusCode = "Unset"
}

/// OpenTelemetry span status.
public struct GenAISpanStatus: Codable, Sendable, Hashable {
    public var code: GenAISpanStatusCode?
    public var message: String?

    public init(code: GenAISpanStatusCode? = nil, message: String? = nil) {
        self.code = code
        self.message = message
    }
}

/// An event within a span (exception, log, state change).
public struct GenAISpanEvent: Codable, Sendable, Hashable {
    public var timestamp: Date?
    public var name: String?
    public var attributes: JSONObject?

    public init(timestamp: Date? = nil, name: String? = nil, attributes: JSONObject? = nil) {
        self.timestamp = timestamp
        self.name = name
        self.attributes = attributes
    }
}

/// One conversation item: an OpenTelemetry span with its attributes nested by semantic-convention
/// name (`attributes["gen_ai"]["input"]["messages"]`). The attribute tree is open; typed accessors
/// cover the common reads.
public struct GenAISpan: Codable, Sendable, Hashable {
    public var traceId: String
    /// Also the `itemId` of the item detail read.
    public var spanId: String?
    public var parentSpanId: String?
    public var name: String?
    public var kind: GenAISpanKind?
    public var startTime: Date?
    public var endTime: Date?
    public var durationNs: Int64?
    public var status: GenAISpanStatus?
    public var resource: JSONObject?
    /// Present when requested with the `events` include.
    public var events: [GenAISpanEvent]?
    public var attributes: JSONObject

    public init(
        traceId: String, spanId: String? = nil, parentSpanId: String? = nil, name: String? = nil,
        kind: GenAISpanKind? = nil, startTime: Date? = nil, endTime: Date? = nil, durationNs: Int64? = nil,
        status: GenAISpanStatus? = nil, resource: JSONObject? = nil, events: [GenAISpanEvent]? = nil,
        attributes: JSONObject = [:]
    ) {
        self.traceId = traceId
        self.spanId = spanId
        self.parentSpanId = parentSpanId
        self.name = name
        self.kind = kind
        self.startTime = startTime
        self.endTime = endTime
        self.durationNs = durationNs
        self.status = status
        self.resource = resource
        self.events = events
        self.attributes = attributes
    }

    private enum CodingKeys: String, CodingKey {
        case name, kind, status, resource, events, attributes
        case traceId = "trace_id"
        case spanId = "span_id"
        case parentSpanId = "parent_span_id"
        case startTime = "start_time"
        case endTime = "end_time"
        case durationNs = "duration_ns"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        traceId = try container.decodeIfPresent(String.self, forKey: .traceId) ?? ""
        spanId = try container.decodeIfPresent(String.self, forKey: .spanId)
        parentSpanId = try container.decodeIfPresent(String.self, forKey: .parentSpanId)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        kind = try container.decodeIfPresent(GenAISpanKind.self, forKey: .kind)
        startTime = try container.decodeIfPresent(Date.self, forKey: .startTime)
        endTime = try container.decodeIfPresent(Date.self, forKey: .endTime)
        durationNs = try container.decodeIfPresent(Int64.self, forKey: .durationNs)
        status = try container.decodeIfPresent(GenAISpanStatus.self, forKey: .status)
        resource = try container.decodeIfPresent(JSONObject.self, forKey: .resource)
        events = try container.decodeIfPresent([GenAISpanEvent].self, forKey: .events)
        attributes = try container.decodeIfPresent(JSONObject.self, forKey: .attributes) ?? [:]
    }

    /// The attribute at a dotted semantic-convention path, walking the nested tree
    /// (and falling back to a flat dotted key).
    public func attribute(_ path: String) -> JSONValue? {
        var current: JSONValue? = .object(attributes)
        for key in path.split(separator: ".") {
            current = current?[String(key)]
            if current == nil { break }
        }
        if let current, !current.isNull { return current }
        if let flat = attributes[path], !flat.isNull { return flat }
        return nil
    }

    private func string(_ path: String) -> String? {
        guard let value = attribute(path)?.stringValue, !value.isEmpty else { return nil }
        return value
    }

    /// `gen_ai.operation.name`: `chat`, `execute_tool`, `invoke_agent`, ...
    public var operationName: String? { string("gen_ai.operation.name") }
    /// `gen_ai.conversation.id`.
    public var conversationId: String? { string("gen_ai.conversation.id") }
    public var providerName: String? { string("gen_ai.provider.name") }
    public var requestModel: String? { string("gen_ai.request.model") }
    public var responseModel: String? { string("gen_ai.response.model") }
    /// `gen_ai.response.id`.
    public var responseId: String? { string("gen_ai.response.id") }
    public var agentId: String? { string("gen_ai.agent.id") }
    public var agentName: String? { string("gen_ai.agent.name") }
    public var toolName: String? { string("gen_ai.tool.name") }
    /// `gen_ai.tool.call.id` on an `execute_tool` span.
    public var toolCallId: String? { string("gen_ai.tool.call.id") }
    /// `gen_ai.tool.call.arguments`, JSON-encoded.
    public var toolCallArguments: String? {
        guard let value = attribute("gen_ai.tool.call.arguments") else { return nil }
        return value.stringValue ?? (try? JSONCoding.encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) }
    }
    public var inputTokens: Int? { attribute("gen_ai.usage.input_tokens")?.intValue }
    public var outputTokens: Int? { attribute("gen_ai.usage.output_tokens")?.intValue }
    /// `gen_ai.cost.usd`.
    public var costUsd: Double? { attribute("gen_ai.cost.usd")?.doubleValue }
    /// `introspection.agent.invocation_id`, the durable child agent-run id on a delegation span.
    public var invocationId: String? { string("introspection.agent.invocation_id") }
    /// `introspection.conversation.client_message_id`.
    public var clientMessageId: String? { string("introspection.conversation.client_message_id") }

    /// `gen_ai.input.messages`: the turn-local delta on list reads, the full history on item detail.
    public var inputMessages: [GenAIMessage] { Self.messages(attribute("gen_ai.input.messages")) }
    /// `gen_ai.output.messages`.
    public var outputMessages: [GenAIMessage] { Self.messages(attribute("gen_ai.output.messages")) }
    /// `gen_ai.system_instructions`, present when requested with that include.
    public var systemInstructions: [GenAISystemInstruction] {
        (attribute("gen_ai.system_instructions")?.arrayValue ?? []).compactMap { try? $0.decode(GenAISystemInstruction.self) }
    }
    /// `gen_ai.tool.definitions`, present when requested with that include.
    public var toolDefinitions: [GenAIToolDefinition] {
        (attribute("gen_ai.tool.definitions")?.arrayValue ?? []).compactMap { try? $0.decode(GenAIToolDefinition.self) }
    }

    private static func messages(_ value: JSONValue?) -> [GenAIMessage] {
        (value?.arrayValue ?? []).compactMap { try? $0.decode(GenAIMessage.self) }
    }

    /// A copy whose `tool_call_response` parts use the semconv `response` key. Older data
    /// planes wrote it as `result`; every read in this SDK applies this.
    public func normalizingLegacyToolResults() -> GenAISpan {
        guard case var .object(genAI)? = attributes["gen_ai"] else { return self }
        var changed = false
        for side in ["input", "output"] {
            guard case var .object(node)? = genAI[side], case let .array(messages)? = node["messages"] else { continue }
            node["messages"] = .array(messages.map { Self.normalizeMessage($0, changed: &changed) })
            genAI[side] = .object(node)
        }
        guard changed else { return self }
        var copy = self
        copy.attributes["gen_ai"] = .object(genAI)
        return copy
    }

    private static func normalizeMessage(_ message: JSONValue, changed: inout Bool) -> JSONValue {
        guard case var .object(object) = message, case let .array(parts)? = object["parts"] else { return message }
        object["parts"] = .array(parts.map { part in
            guard case var .object(fields) = part, fields["type"]?.stringValue == "tool_call_response",
                  fields["response"] == nil, let result = fields["result"] else { return part }
            fields["response"] = result
            fields["result"] = nil
            changed = true
            return .object(fields)
        })
        return .object(object)
    }
}

/// OpenAI-style list envelope for conversation items. Pagination uses `next`.
public struct GenAISpanList: Codable, Sendable, Hashable {
    public var object: String?
    public var data: [GenAISpan]
    public var firstId: String?
    public var lastId: String?
    public var hasMore: Bool?
    public var next: String?

    public init(data: [GenAISpan], object: String? = "list", firstId: String? = nil, lastId: String? = nil, hasMore: Bool? = nil, next: String? = nil) {
        self.data = data
        self.object = object
        self.firstId = firstId
        self.lastId = lastId
        self.hasMore = hasMore
        self.next = next
    }

    private enum CodingKeys: String, CodingKey {
        case object, data, next
        case firstId = "first_id"
        case lastId = "last_id"
        case hasMore = "has_more"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        object = try container.decodeIfPresent(String.self, forKey: .object)
        data = try container.decodeIfPresent([GenAISpan].self, forKey: .data) ?? []
        firstId = try container.decodeIfPresent(String.self, forKey: .firstId)
        lastId = try container.decodeIfPresent(String.self, forKey: .lastId)
        hasMore = try container.decodeIfPresent(Bool.self, forKey: .hasMore)
        next = try container.decodeIfPresent(String.self, forKey: .next)
    }
}

// MARK: - GenAI messages

/// Message role. Unknown roles are preserved.
public struct GenAIMessageRole: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }

    public static let system: GenAIMessageRole = "system"
    public static let user: GenAIMessageRole = "user"
    public static let assistant: GenAIMessageRole = "assistant"
    public static let tool: GenAIMessageRole = "tool"
}

/// A `gen_ai.input.messages` or `gen_ai.output.messages` element. The output-only fields are nil on inputs.
public struct GenAIMessage: Codable, Sendable, Hashable {
    public var role: GenAIMessageRole
    public var parts: [GenAIMessagePart]
    /// Tool name when `role` is `tool`.
    public var name: String?
    public var finishReason: String?
    public var provider: String?
    public var model: String?
    public var api: String?
    public var responseId: String?

    public init(
        role: GenAIMessageRole, parts: [GenAIMessagePart] = [], name: String? = nil, finishReason: String? = nil,
        provider: String? = nil, model: String? = nil, api: String? = nil, responseId: String? = nil
    ) {
        self.role = role
        self.parts = parts
        self.name = name
        self.finishReason = finishReason
        self.provider = provider
        self.model = model
        self.api = api
        self.responseId = responseId
    }

    private enum CodingKeys: String, CodingKey {
        case role, parts, name, provider, model, api
        case finishReason = "finish_reason"
        case responseId = "response_id"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decodeIfPresent(GenAIMessageRole.self, forKey: .role) ?? ""
        parts = try container.decodeIfPresent([GenAIMessagePart].self, forKey: .parts) ?? []
        name = try container.decodeIfPresent(String.self, forKey: .name)
        finishReason = try container.decodeIfPresent(String.self, forKey: .finishReason)
        provider = try container.decodeIfPresent(String.self, forKey: .provider)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        api = try container.decodeIfPresent(String.self, forKey: .api)
        responseId = try container.decodeIfPresent(String.self, forKey: .responseId)
    }

    /// The text parts joined with newlines.
    public var text: String {
        parts.compactMap { part -> String? in
            if case let .text(text) = part { return text.content ?? "" }
            return nil
        }.joined(separator: "\n")
    }
}

/// One message part, discriminated on `type`. A type this SDK does not model, or a
/// malformed part, decodes as `.unknown` with its raw fields rather than failing.
public enum GenAIMessagePart: Codable, Sendable, Hashable {
    case text(GenAITextPart)
    /// `thinking` as stored, or `reasoning` per the semantic conventions.
    case thinking(GenAIThinkingPart)
    case toolCall(GenAIToolCallPart)
    case toolCallResponse(GenAIToolCallResponsePart)
    case compaction(GenAICompactionPart)
    /// `image-url`, `audio-url`, `video-url`, `document-url`, or the semconv `uri`.
    case media(GenAIMediaPart)
    case binary(GenAIBinaryPart)
    case blob(GenAIBlobPart)
    case file(GenAIFilePart)
    case unknown(JSONObject)

    /// The part's `type` discriminator.
    public var type: String {
        switch self {
        case .text: return "text"
        case let .thinking(part): return part.type
        case .toolCall: return "tool_call"
        case .toolCallResponse: return "tool_call_response"
        case .compaction: return "compaction"
        case let .media(part): return part.type
        case .binary: return "binary"
        case .blob: return "blob"
        case .file: return "file"
        case let .unknown(raw): return raw["type"]?.stringValue ?? ""
        }
    }

    public init(from decoder: Decoder) throws {
        let value = try JSONValue(from: decoder)
        guard case let .object(raw) = value else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Message part is not an object"))
        }
        func attempt<T: Decodable>(_ type: T.Type, _ wrap: (T) -> GenAIMessagePart) -> GenAIMessagePart {
            (try? value.decode(T.self)).map(wrap) ?? .unknown(raw)
        }
        switch raw["type"]?.stringValue {
        case "text": self = attempt(GenAITextPart.self, GenAIMessagePart.text)
        case "thinking", "reasoning": self = attempt(GenAIThinkingPart.self, GenAIMessagePart.thinking)
        case "tool_call": self = attempt(GenAIToolCallPart.self, GenAIMessagePart.toolCall)
        case "tool_call_response": self = attempt(GenAIToolCallResponsePart.self, GenAIMessagePart.toolCallResponse)
        case "compaction": self = attempt(GenAICompactionPart.self, GenAIMessagePart.compaction)
        case "image-url", "audio-url", "video-url", "document-url", "uri":
            self = attempt(GenAIMediaPart.self, GenAIMessagePart.media)
        case "binary": self = attempt(GenAIBinaryPart.self, GenAIMessagePart.binary)
        case "blob": self = attempt(GenAIBlobPart.self, GenAIMessagePart.blob)
        case "file": self = attempt(GenAIFilePart.self, GenAIMessagePart.file)
        default: self = .unknown(raw)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case let .text(part): try part.encode(to: encoder)
        case let .thinking(part): try part.encode(to: encoder)
        case let .toolCall(part): try part.encode(to: encoder)
        case let .toolCallResponse(part): try part.encode(to: encoder)
        case let .compaction(part): try part.encode(to: encoder)
        case let .media(part): try part.encode(to: encoder)
        case let .binary(part): try part.encode(to: encoder)
        case let .blob(part): try part.encode(to: encoder)
        case let .file(part): try part.encode(to: encoder)
        case let .unknown(raw): try JSONValue.object(raw).encode(to: encoder)
        }
    }
}

/// A text part.
public struct GenAITextPart: Codable, Sendable, Hashable {
    public var type = "text"
    public var content: String?
    /// Opaque per-block signature for replay continuity.
    public var textSignature: String?

    public init(content: String?, textSignature: String? = nil) {
        self.content = content
        self.textSignature = textSignature
    }

    private enum CodingKeys: String, CodingKey {
        case type, content
        case textSignature = "text_signature"
    }
}

/// A reasoning / thinking part.
public struct GenAIThinkingPart: Codable, Sendable, Hashable {
    /// `thinking` or `reasoning`, preserved as written.
    public var type: String
    public var content: String?
    /// Encrypted reasoning payload (Anthropic signature, OpenAI encrypted_content).
    public var signature: String?
    public var providerName: String?
    /// True when the visible content was redacted but the signed payload kept.
    public var redacted: Bool?

    public init(content: String?, type: String = "thinking", signature: String? = nil, providerName: String? = nil, redacted: Bool? = nil) {
        self.type = type
        self.content = content
        self.signature = signature
        self.providerName = providerName
        self.redacted = redacted
    }

    private enum CodingKeys: String, CodingKey {
        case type, content, signature, redacted
        case providerName = "provider_name"
    }
}

/// A tool call request.
public struct GenAIToolCallPart: Codable, Sendable, Hashable {
    public var type = "tool_call"
    public var id: String?
    public var name: String?
    public var arguments: JSONValue?

    public init(id: String?, name: String?, arguments: JSONValue? = nil) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

/// A tool call response. Decodes the legacy `result` key as `response`.
public struct GenAIToolCallResponsePart: Codable, Sendable, Hashable {
    public var type = "tool_call_response"
    public var id: String?
    public var name: String?
    public var response: JSONValue?

    public init(id: String?, response: JSONValue?, name: String? = nil) {
        self.id = id
        self.response = response
        self.name = name
    }

    private enum CodingKeys: String, CodingKey {
        case type, id, name, response, result
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        response = try container.decodeIfPresent(JSONValue.self, forKey: .response)
            ?? container.decodeIfPresent(JSONValue.self, forKey: .result)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(response, forKey: .response)
    }
}

/// Model-visible compacted history summary.
public struct GenAICompactionPart: Codable, Sendable, Hashable {
    public var type = "compaction"
    public var content: String?

    public init(content: String?) { self.content = content }
}

/// Media referenced by URL (`image-url` and friends) or by the semconv `uri` part.
public struct GenAIMediaPart: Codable, Sendable, Hashable {
    public var type: String
    public var url: String?
    public var uri: String?
    public var modality: String?
    public var mimeType: String?

    public init(type: String, url: String? = nil, uri: String? = nil, modality: String? = nil, mimeType: String? = nil) {
        self.type = type
        self.url = url
        self.uri = uri
        self.modality = modality
        self.mimeType = mimeType
    }

    private enum CodingKeys: String, CodingKey {
        case type, url, uri, modality
        case mimeType = "mime_type"
    }
}

/// Inline base64 binary data.
public struct GenAIBinaryPart: Codable, Sendable, Hashable {
    public var type = "binary"
    public var mediaType: String?
    public var content: String?

    public init(mediaType: String?, content: String? = nil) {
        self.mediaType = mediaType
        self.content = content
    }

    private enum CodingKeys: String, CodingKey {
        case type, content
        case mediaType = "media_type"
    }
}

/// Inline data per the semconv `blob` part; `content` is often omitted.
public struct GenAIBlobPart: Codable, Sendable, Hashable {
    public var type = "blob"
    public var modality: String?
    public var mimeType: String?
    public var content: String?

    public init(modality: String?, mimeType: String? = nil, content: String? = nil) {
        self.modality = modality
        self.mimeType = mimeType
        self.content = content
    }

    private enum CodingKeys: String, CodingKey {
        case type, modality, content
        case mimeType = "mime_type"
    }
}

/// Content referenced by a provider-assigned file id.
public struct GenAIFilePart: Codable, Sendable, Hashable {
    public var type = "file"
    public var modality: String?
    public var fileId: String?
    public var mimeType: String?

    public init(fileId: String?, modality: String? = nil, mimeType: String? = nil) {
        self.fileId = fileId
        self.modality = modality
        self.mimeType = mimeType
    }

    private enum CodingKeys: String, CodingKey {
        case type, modality
        case fileId = "file_id"
        case mimeType = "mime_type"
    }
}

/// A `gen_ai.system_instructions` entry.
public struct GenAISystemInstruction: Codable, Sendable, Hashable {
    public var type: String?
    public var content: String?

    public init(content: String?, type: String? = "text") {
        self.content = content
        self.type = type
    }
}

/// A `gen_ai.tool.definitions` entry.
public struct GenAIToolDefinition: Codable, Sendable, Hashable {
    public var type: String?
    public var name: String?
    public var description: String?
    /// JSON Schema of the parameters.
    public var parameters: JSONValue?

    public init(name: String?, description: String? = nil, type: String? = nil, parameters: JSONValue? = nil) {
        self.name = name
        self.description = description
        self.type = type
        self.parameters = parameters
    }
}

// MARK: - Conversation resource

/// One agent invocation discovered in a conversation.
public struct ConversationAgent: Codable, Sendable, Hashable {
    /// Accepted by the items `agent` selector.
    public var id: String
    public var name: String?
    public var parentId: String?
    public var invocationId: String?
    public var depth: Int?

    public init(id: String, name: String? = nil, parentId: String? = nil, invocationId: String? = nil, depth: Int? = nil) {
        self.id = id
        self.name = name
        self.parentId = parentId
        self.invocationId = invocationId
        self.depth = depth
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, depth
        case parentId = "parent_id"
        case invocationId = "invocation_id"
    }
}

/// Aggregated token usage.
public struct ConversationUsage: Codable, Sendable, Hashable {
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var totalTokens: Int?

    private enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
    }
}

/// Aggregated cost.
public struct ConversationCost: Codable, Sendable, Hashable {
    public var usd: Double?
}

/// Telemetry rollups for a conversation.
public struct ConversationMetrics: Codable, Sendable, Hashable {
    public var durationMs: Double?
    public var traceCount: Int?
    public var spanCount: Int?
    public var toolUseCount: Int?
    public var failedToolUseCount: Int?
    public var llmCallCount: Int?
    public var failedLlmCallCount: Int?
    public var hasErrors: Bool?

    private enum CodingKeys: String, CodingKey {
        case durationMs = "duration_ms"
        case traceCount = "trace_count"
        case spanCount = "span_count"
        case toolUseCount = "tool_use_count"
        case failedToolUseCount = "failed_tool_use_count"
        case llmCallCount = "llm_call_count"
        case failedLlmCallCount = "failed_llm_call_count"
        case hasErrors = "has_errors"
    }
}

/// A conversation summary resource.
public struct Conversation: Codable, Sendable, Hashable {
    public var object: String?
    public var id: String
    public var createdAt: Date?
    public var updatedAt: Date?
    /// Complete only on the single-conversation read.
    public var agents: [ConversationAgent]?
    public var usage: ConversationUsage?
    public var cost: ConversationCost?
    public var metrics: ConversationMetrics?
    public var environment: String?
    public var serviceName: String?
    public var runtimeId: String?
    public var runtimeGroupId: String?
    public var experimentId: String?
    public var recipeGitCommitSha: String?
    public var ownerKey: String?
    /// Customer-defined dimensions stamped via `introspection.metadata.<key>` span attributes.
    public var metadata: [String: String]?
    public var taskTitle: String?

    private enum CodingKeys: String, CodingKey {
        case object, id, agents, usage, cost, metrics, environment, metadata
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case serviceName = "service_name"
        case runtimeId = "runtime_id"
        case runtimeGroupId = "runtime_group_id"
        case experimentId = "experiment_id"
        case recipeGitCommitSha = "recipe_git_commit_sha"
        case ownerKey = "owner_key"
        case taskTitle = "task_title"
    }
}

/// Allow-listed sort fields for the conversations list.
public struct ConversationSortField: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }

    public static let created: ConversationSortField = "created"
    public static let duration: ConversationSortField = "duration"
    public static let turns: ConversationSortField = "turns"
    public static let toolCalls: ConversationSortField = "tool_calls"
    public static let llmCalls: ConversationSortField = "llm_calls"
    public static let tokens: ConversationSortField = "tokens"
    public static let cost: ConversationSortField = "cost"
}

/// Optional item expansions (repeated `include`).
public struct ConversationItemInclude: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }

    public static let systemInstructions: ConversationItemInclude = "gen_ai.system_instructions"
    public static let toolDefinitions: ConversationItemInclude = "gen_ai.tool.definitions"
    public static let events: ConversationItemInclude = "events"
    public static let resourceAttributes: ConversationItemInclude = "resource_attributes"
    public static let spanAttributes: ConversationItemInclude = "span_attributes"
}

/// Filters for `GET /v1/conversations`. `lookback` is mutually exclusive with `start`/`end`.
public struct ConversationListParams: Sendable, Hashable {
    public var limit: Int?
    public var next: String?
    /// Sent as `direction` (server default `desc`).
    public var order: ReadOrder?
    /// Sent as `start_date` (inclusive).
    public var start: Date?
    /// Sent as `end_date` (inclusive).
    public var end: Date?
    /// Computed into `start_date = now - lookback`.
    public var lookback: ReadLookback?
    public var sort: ConversationSortField?
    public var shareIds: [String]?
    public var conversationId: String?
    public var conversationIds: [String]?
    public var traceId: String?
    public var annotationId: String?
    public var model: String?
    public var agentName: String?
    public var status: GenAISpanStatusCode?
    public var serviceName: String?
    public var serviceNames: [String]?
    public var environment: String?
    public var runtimeId: String?
    public var runtimeGroupId: String?
    public var experimentId: String?
    public var recipeGitCommitSha: String?
    /// `resolved`, `blocked`, `unresolved` or `pending`.
    public var resolution: String?
    /// `positive`, `negative`, `mixed` or `neutral`.
    public var sentiment: String?
    public var ownerKey: String?
    /// Sent as repeated `metadata=key:value`; several pairs are ANDed and must co-occur on one span.
    public var metadata: [String: String]?

    public init(
        limit: Int? = nil, next: String? = nil, order: ReadOrder? = nil, start: Date? = nil, end: Date? = nil,
        lookback: ReadLookback? = nil, sort: ConversationSortField? = nil, shareIds: [String]? = nil,
        conversationId: String? = nil, conversationIds: [String]? = nil, traceId: String? = nil,
        annotationId: String? = nil, model: String? = nil, agentName: String? = nil,
        status: GenAISpanStatusCode? = nil, serviceName: String? = nil, serviceNames: [String]? = nil,
        environment: String? = nil, runtimeId: String? = nil, runtimeGroupId: String? = nil,
        experimentId: String? = nil, recipeGitCommitSha: String? = nil, resolution: String? = nil,
        sentiment: String? = nil, ownerKey: String? = nil, metadata: [String: String]? = nil
    ) {
        self.limit = limit
        self.next = next
        self.order = order
        self.start = start
        self.end = end
        self.lookback = lookback
        self.sort = sort
        self.shareIds = shareIds
        self.conversationId = conversationId
        self.conversationIds = conversationIds
        self.traceId = traceId
        self.annotationId = annotationId
        self.model = model
        self.agentName = agentName
        self.status = status
        self.serviceName = serviceName
        self.serviceNames = serviceNames
        self.environment = environment
        self.runtimeId = runtimeId
        self.runtimeGroupId = runtimeGroupId
        self.experimentId = experimentId
        self.recipeGitCommitSha = recipeGitCommitSha
        self.resolution = resolution
        self.sentiment = sentiment
        self.ownerKey = ownerKey
        self.metadata = metadata
    }

    func query(now: Date) throws -> Query {
        var q = Query()
        q.add("limit", limit)
        q.add("sort", sort)
        try applyReadWindow(to: &q, order: order, start: start, end: end, lookback: lookback, now: now)
        q.add("share_id", shareIds)
        q.add("conversation_id", conversationId)
        q.add("conversation_ids", conversationIds)
        q.add("trace_id", traceId)
        q.add("annotation_id", annotationId)
        q.add("model", model)
        q.add("agent_name", agentName)
        q.add("status", status)
        q.add("service_name", serviceName)
        q.add("service_names", serviceNames)
        q.add("environment", environment)
        q.add("runtime_id", runtimeId)
        q.add("runtime_group_id", runtimeGroupId)
        q.add("experiment_id", experimentId)
        q.add("recipe_git_commit_sha", recipeGitCommitSha)
        q.add("resolution", resolution)
        q.add("sentiment", sentiment)
        q.add("owner_key", ownerKey)
        q.add("metadata", metadata.map { pairs in pairs.keys.sorted().compactMap { key in pairs[key].map { "\(key):\($0)" } } })
        return q
    }
}

/// Filters for `GET /v1/conversations/{id}/items`. Items are always newest first.
public struct ConversationItemListParams: Sendable, Hashable {
    public var limit: Int?
    public var next: String?
    public var include: [ConversationItemInclude]?
    /// `root` for the depth-zero transcript, an exact agent id for that invocation, nil for everything.
    public var agent: String?
    public var serviceName: String?
    public var operationName: String?
    public var traceId: String?
    public var spanId: String?
    public var startDate: Date?
    public var endDate: Date?
    /// Partition lookback in days (1-365).
    public var lookbackDays: Int?
    public var shareId: String?
    public var annotationId: String?
    /// Resume from the latest compaction boundary (ascending).
    public var fromCompaction: Bool?

    public init(
        limit: Int? = nil, next: String? = nil, include: [ConversationItemInclude]? = nil, agent: String? = nil,
        serviceName: String? = nil, operationName: String? = nil, traceId: String? = nil, spanId: String? = nil,
        startDate: Date? = nil, endDate: Date? = nil, lookbackDays: Int? = nil, shareId: String? = nil,
        annotationId: String? = nil, fromCompaction: Bool? = nil
    ) {
        self.limit = limit
        self.next = next
        self.include = include
        self.agent = agent
        self.serviceName = serviceName
        self.operationName = operationName
        self.traceId = traceId
        self.spanId = spanId
        self.startDate = startDate
        self.endDate = endDate
        self.lookbackDays = lookbackDays
        self.shareId = shareId
        self.annotationId = annotationId
        self.fromCompaction = fromCompaction
    }

    var query: Query {
        var q = Query()
        q.add("limit", limit)
        q.add("include", include)
        q.add("agent", agent)
        q.add("service_name", serviceName)
        q.add("operation_name", operationName)
        q.add("trace_id", traceId)
        q.add("span_id", spanId)
        q.add("start_date", startDate)
        q.add("end_date", endDate)
        q.add("lookback_days", lookbackDays)
        q.add("share_id", shareId)
        q.add("annotation_id", annotationId)
        q.add("from_compaction", fromCompaction)
        return q
    }
}

/// Filters for `GET /v1/conversations/{id}/export`, which assembles the whole conversation.
public struct ConversationExportParams: Sendable, Hashable {
    public var agent: String?
    public var serviceName: String?
    public var operationName: String?
    public var lookbackDays: Int?
    public var shareId: String?
    public var annotationId: String?
    public var startDate: Date?
    public var endDate: Date?
    public var fromCompaction: Bool?

    public init(
        agent: String? = nil, serviceName: String? = nil, operationName: String? = nil, lookbackDays: Int? = nil,
        shareId: String? = nil, annotationId: String? = nil, startDate: Date? = nil, endDate: Date? = nil,
        fromCompaction: Bool? = nil
    ) {
        self.agent = agent
        self.serviceName = serviceName
        self.operationName = operationName
        self.lookbackDays = lookbackDays
        self.shareId = shareId
        self.annotationId = annotationId
        self.startDate = startDate
        self.endDate = endDate
        self.fromCompaction = fromCompaction
    }

    var query: Query {
        var q = Query()
        q.add("agent", agent)
        q.add("service_name", serviceName)
        q.add("operation_name", operationName)
        q.add("lookback_days", lookbackDays)
        q.add("share_id", shareId)
        q.add("annotation_id", annotationId)
        q.add("start_date", startDate)
        q.add("end_date", endDate)
        q.add("from_compaction", fromCompaction)
        return q
    }
}

/// The representation `exportStream` asks for.
public enum ConversationExportFormat: String, Sendable, Hashable, CaseIterable {
    case json
    /// Apache Arrow IPC stream (returned as raw bytes; this SDK does not decode Arrow).
    case arrow
    /// trajectory-v1.
    case trajectory
    /// Managed Recipe replay.
    case replay

    /// The `Accept` header value for this format.
    public var accept: String {
        switch self {
        case .json: return "application/json"
        case .arrow: return "application/vnd.apache.arrow.stream"
        case .trajectory: return "application/vnd.letta.trajectory+json;version=1"
        case .replay: return "application/vnd.introspection.conversation-replay+json;version=1"
        }
    }
}

// MARK: - Turns

/// Terminal state of a turn.
public struct ConversationTurnStatus: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }

    public static let completed: ConversationTurnStatus = "completed"
    public static let cancelled: ConversationTurnStatus = "cancelled"
    public static let error: ConversationTurnStatus = "error"
}

/// Delivery state of a reply posted back to a channel.
public struct ChannelReplyDelivery: Codable, Sendable, Hashable {
    /// `reply` or `send`.
    public var command: String?
    /// `sent`, `pending` or `unconfirmed`.
    public var status: String?
    public var url: String?
}

/// One user-visible message of a turn, without tool internals.
public struct ConversationTurnMessage: Codable, Sendable, Hashable {
    public var id: String
    /// `user` or `assistant`.
    public var role: GenAIMessageRole
    public var parts: [GenAIMessagePart]
    public var sourceSpanId: String?
    public var createdAt: Date?
    public var channelReply: ChannelReplyDelivery?
    public var clientMessageId: String?
    public var responseId: String?

    private enum CodingKeys: String, CodingKey {
        case id, role, parts
        case sourceSpanId = "source_span_id"
        case createdAt = "created_at"
        case channelReply = "channel_reply"
        case clientMessageId = "client_message_id"
        case responseId = "response_id"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        role = try container.decodeIfPresent(GenAIMessageRole.self, forKey: .role) ?? ""
        parts = try container.decodeIfPresent([GenAIMessagePart].self, forKey: .parts) ?? []
        sourceSpanId = try container.decodeIfPresent(String.self, forKey: .sourceSpanId)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        channelReply = try container.decodeIfPresent(ChannelReplyDelivery.self, forKey: .channelReply)
        clientMessageId = try container.decodeIfPresent(String.self, forKey: .clientMessageId)
        responseId = try container.decodeIfPresent(String.self, forKey: .responseId)
    }
}

/// One agent-scoped, trace-rooted user interaction.
public struct ConversationTurn: Codable, Sendable, Hashable {
    public var object: String?
    public var id: String
    public var traceId: String?
    /// One-based position within the agent transcript.
    public var ordinal: Int?
    public var agentId: String?
    public var agentName: String?
    public var startedAt: Date?
    public var endedAt: Date?
    public var status: ConversationTurnStatus?
    public var messages: [ConversationTurnMessage]?
    public var responseIds: [String]?
    public var hasSteps: Bool?
    public var itemCount: Int?
    public var toolUseCount: Int?
    public var failedToolUseCount: Int?
    public var errorCount: Int?
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var costUsd: Double?
    public var durationMs: Double?

    private enum CodingKeys: String, CodingKey {
        case object, id, ordinal, status, messages
        case traceId = "trace_id"
        case agentId = "agent_id"
        case agentName = "agent_name"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case responseIds = "response_ids"
        case hasSteps = "has_steps"
        case itemCount = "item_count"
        case toolUseCount = "tool_use_count"
        case failedToolUseCount = "failed_tool_use_count"
        case errorCount = "error_count"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case costUsd = "cost_usd"
        case durationMs = "duration_ms"
    }
}

/// Filters for `GET /v1/conversations/{id}/turns`. Pages walk from newest to older turns.
public struct ConversationTurnListParams: Sendable, Hashable {
    /// 1-100, server default 25.
    public var limit: Int?
    public var next: String?
    /// `root` (server default) or one exact agent id.
    public var agent: String?
    public var beforeTraceId: String?
    public var traceId: String?
    public var lookbackDays: Int?
    public var shareId: String?
    public var annotationId: String?

    public init(
        limit: Int? = nil, next: String? = nil, agent: String? = nil, beforeTraceId: String? = nil,
        traceId: String? = nil, lookbackDays: Int? = nil, shareId: String? = nil, annotationId: String? = nil
    ) {
        self.limit = limit
        self.next = next
        self.agent = agent
        self.beforeTraceId = beforeTraceId
        self.traceId = traceId
        self.lookbackDays = lookbackDays
        self.shareId = shareId
        self.annotationId = annotationId
    }
}

// MARK: - Trajectory

/// One tool call of a trajectory assistant record. `args` is a JSON-encoded object.
public struct TrajectoryToolCall: Codable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var args: String
}

/// One trajectory-v1 record, discriminated by `role` (`meta`, `user`, `reasoning`, `assistant`, `tool`).
public struct TrajectoryRecord: Codable, Sendable, Hashable {
    public var role: String
    /// Null on an assistant tool-call record.
    public var content: String?
    public var timestamp: Date?
    /// `meta` only.
    public var source: String?
    public var cwd: String?
    public var gitBranch: String?
    public var model: String?
    /// `assistant` tool-call records only.
    public var toolCalls: [TrajectoryToolCall]?
    /// `tool` records only.
    public var toolCallId: String?
    public var ok: Bool?

    private enum CodingKeys: String, CodingKey {
        case role, content, timestamp, source, cwd, model, ok
        case gitBranch = "git_branch"
        case toolCalls = "tool_calls"
        case toolCallId = "tool_call_id"
    }
}

// MARK: - API

/// Read-only conversations (`/v1/conversations`).
public struct ConversationsAPI: Sendable {
    let http: HTTPClient

    public init(http: HTTPClient) { self.http = http }

    /// Items (GenAI spans) of a conversation.
    public var items: ConversationItemsAPI { ConversationItemsAPI(http: http) }

    /// List conversation summaries. Throws before any request when the window params conflict;
    /// a `lookback` is pinned to one `now` for every page.
    public func list(_ params: ConversationListParams = ConversationListParams()) throws -> Paginator<Conversation> {
        try list(params, now: Date())
    }

    func list(_ params: ConversationListParams, now: Date) throws -> Paginator<Conversation> {
        http.paginate("/v1/conversations", query: try params.query(now: now), start: params.next)
    }

    /// Read one conversation summary with its complete agent index.
    public func get(_ conversationId: String, shareId: String? = nil, annotationId: String? = nil) async throws -> Conversation {
        var query = Query()
        query.add("share_id", shareId)
        query.add("annotation_id", annotationId)
        return try await http.json("GET", "/v1/conversations/\(pathSegment(conversationId))", query: query)
    }

    /// List lightweight user/assistant turns, newest first.
    public func turns(_ conversationId: String, _ params: ConversationTurnListParams = ConversationTurnListParams()) -> Paginator<ConversationTurn> {
        var query = Query()
        query.add("limit", params.limit)
        query.add("agent", params.agent)
        query.add("before_trace_id", params.beforeTraceId)
        query.add("trace_id", params.traceId)
        query.add("lookback_days", params.lookbackDays)
        query.add("share_id", params.shareId)
        query.add("annotation_id", params.annotationId)
        return http.paginate("/v1/conversations/\(pathSegment(conversationId))/turns", query: query, start: params.next)
    }

    /// Export the complete conversation as one GenAI-span list.
    public func exportJSON(_ conversationId: String, _ params: ConversationExportParams = ConversationExportParams()) async throws -> GenAISpanList {
        var list = try await http.json(
            "GET", "/v1/conversations/\(pathSegment(conversationId))/export",
            query: params.query, headers: ["Accept": ConversationExportFormat.json.accept], as: GenAISpanList.self
        )
        list.data = list.data.map { $0.normalizingLegacyToolResults() }
        return list
    }

    /// Export the complete conversation as trajectory-v1 records. A conversation that cannot be
    /// represented fails with a validation error; one with no records is not found.
    public func exportTrajectory(_ conversationId: String, _ params: ConversationExportParams = ConversationExportParams()) async throws -> [TrajectoryRecord] {
        try await http.json(
            "GET", "/v1/conversations/\(pathSegment(conversationId))/export",
            query: params.query, headers: ["Accept": ConversationExportFormat.trajectory.accept]
        )
    }

    /// Open the raw export byte stream in the given format, without buffering it.
    public func exportStream(
        _ conversationId: String, format: ConversationExportFormat,
        _ params: ConversationExportParams = ConversationExportParams()
    ) async throws -> HTTPStreamResponse {
        try await http.stream(
            "GET", "/v1/conversations/\(pathSegment(conversationId))/export",
            query: params.query, headers: ["Accept": format.accept]
        )
    }

    /// The conversation as of one item: that span's full input history, output, and attributes.
    /// Without `itemId`, the latest `chat` item (or the latest item with output). Nil when there are none.
    public func retrieve(conversationId: String, itemId: String? = nil) async throws -> GenAISpan? {
        let target: String?
        if let itemId {
            target = itemId
        } else {
            target = try await latestTurnId(conversationId)
        }
        guard let target else { return nil }
        return try await items.get(conversationId, target)
    }

    private func latestTurnId(_ conversationId: String) async throws -> String? {
        var fallback: GenAISpan?
        for try await item in items.list(conversationId) {
            if item.operationName == "chat" { return item.spanId }
            if fallback == nil, !item.outputMessages.isEmpty { fallback = item }
        }
        return fallback?.spanId
    }
}

/// Items of a conversation (`/v1/conversations/{id}/items`).
public struct ConversationItemsAPI: Sendable {
    let http: HTTPClient

    public init(http: HTTPClient) { self.http = http }

    /// List items, newest first. Each item carries only the input messages new to its turn.
    public func list(_ conversationId: String, _ params: ConversationItemListParams = ConversationItemListParams()) -> Paginator<GenAISpan> {
        let path = "/v1/conversations/\(pathSegment(conversationId))/items"
        let query = params.query
        return Paginator(start: params.next) { [http] cursor in
            var pageQuery = query
            pageQuery.set("next", cursor)
            let list = try await http.json("GET", path, query: pageQuery, as: GenAISpanList.self)
            let next = (list.next?.isEmpty ?? true) ? nil : list.next
            if list.hasMore == true, next == nil {
                throw IntrospectionError(kind: .decoding, message: "conversation items page for \(conversationId) has_more without next")
            }
            return Page(records: list.data.map { $0.normalizingLegacyToolResults() }, next: next, hasMore: list.hasMore)
        }
    }

    /// Read one item with the full input history as of that span.
    public func get(
        _ conversationId: String, _ itemId: String, include: [ConversationItemInclude]? = nil,
        shareId: String? = nil, annotationId: String? = nil
    ) async throws -> GenAISpan {
        var query = Query()
        query.add("include", include)
        query.add("share_id", shareId)
        query.add("annotation_id", annotationId)
        let span = try await http.json(
            "GET", "/v1/conversations/\(pathSegment(conversationId))/items/\(pathSegment(itemId))",
            query: query, as: GenAISpan.self
        )
        return span.normalizingLegacyToolResults()
    }
}

extension DataPlaneConnection {
    /// Read-only conversations and their GenAI span items.
    public var conversations: ConversationsAPI { ConversationsAPI(http: dataPlane) }
}
