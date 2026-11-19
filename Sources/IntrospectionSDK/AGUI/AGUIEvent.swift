import Foundation

/// The AG-UI protocol types, exactly as `@ag-ui/core` defines them.
public enum AGUI {}

/// One AG-UI protocol event, as streamed from a task run. `payload` is the event as its
/// `@ag-ui/core` type; `raw` keeps the frame as sent, including any key AG-UI does not define.
public struct AGUIEvent: Sendable, Hashable, Codable {
    public let raw: JSONValue
    /// The typed event, or `.unknown` for a new type or a frame that does not satisfy its AG-UI schema.
    public let payload: AGUIEventPayload

    public init(raw: JSONValue) {
        self.raw = raw
        payload = AGUIEventPayload(raw: raw)
    }

    public init(from decoder: any Decoder) throws {
        self.init(raw: try JSONValue(from: decoder))
    }

    public func encode(to encoder: any Encoder) throws {
        try raw.encode(to: encoder)
    }

    /// The AG-UI `type`, for example `TEXT_MESSAGE_CONTENT` or `RUN_FINISHED`, as sent.
    public var type: String { raw["type"]?.stringValue ?? "" }
    public var eventType: AGUIEventType { AGUIEventType(rawValue: type) }

    /// A `CUSTOM` event with the given name.
    public static func custom(_ name: String, value: JSONValue) -> AGUIEvent {
        AGUIEvent(raw: ["type": "CUSTOM", "name": .string(name), "value": value])
    }
}

/// AG-UI event types. Unknown types are preserved.
public struct AGUIEventType: RawRepresentable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }

    // jscpd:ignore-start: the AG-UI event type catalogue.
    public static let runStarted: AGUIEventType = "RUN_STARTED"
    public static let runFinished: AGUIEventType = "RUN_FINISHED"
    public static let runError: AGUIEventType = "RUN_ERROR"
    public static let stepStarted: AGUIEventType = "STEP_STARTED"
    public static let stepFinished: AGUIEventType = "STEP_FINISHED"
    public static let textMessageStart: AGUIEventType = "TEXT_MESSAGE_START"
    public static let textMessageContent: AGUIEventType = "TEXT_MESSAGE_CONTENT"
    public static let textMessageEnd: AGUIEventType = "TEXT_MESSAGE_END"
    public static let textMessageChunk: AGUIEventType = "TEXT_MESSAGE_CHUNK"
    public static let toolCallStart: AGUIEventType = "TOOL_CALL_START"
    public static let toolCallArgs: AGUIEventType = "TOOL_CALL_ARGS"
    public static let toolCallEnd: AGUIEventType = "TOOL_CALL_END"
    public static let toolCallChunk: AGUIEventType = "TOOL_CALL_CHUNK"
    public static let toolCallResult: AGUIEventType = "TOOL_CALL_RESULT"
    public static let stateSnapshot: AGUIEventType = "STATE_SNAPSHOT"
    public static let stateDelta: AGUIEventType = "STATE_DELTA"
    public static let messagesSnapshot: AGUIEventType = "MESSAGES_SNAPSHOT"
    public static let activitySnapshot: AGUIEventType = "ACTIVITY_SNAPSHOT"
    public static let activityDelta: AGUIEventType = "ACTIVITY_DELTA"
    public static let reasoningStart: AGUIEventType = "REASONING_START"
    public static let reasoningMessageStart: AGUIEventType = "REASONING_MESSAGE_START"
    public static let reasoningMessageContent: AGUIEventType = "REASONING_MESSAGE_CONTENT"
    public static let reasoningMessageEnd: AGUIEventType = "REASONING_MESSAGE_END"
    public static let reasoningMessageChunk: AGUIEventType = "REASONING_MESSAGE_CHUNK"
    public static let reasoningEnd: AGUIEventType = "REASONING_END"
    public static let reasoningEncryptedValue: AGUIEventType = "REASONING_ENCRYPTED_VALUE"
    public static let subagentStarted: AGUIEventType = "SUBAGENT_STARTED"
    public static let subagentFinished: AGUIEventType = "SUBAGENT_FINISHED"
    public static let subagentError: AGUIEventType = "SUBAGENT_ERROR"
    public static let raw: AGUIEventType = "RAW"
    public static let custom: AGUIEventType = "CUSTOM"
    // jscpd:ignore-end
}

/// A type whose wire form carries a constant tag (an event `type`, a message `role`, a patch `op`).
public protocol AGUIDiscriminated {
    /// The tag's value on the wire.
    static var discriminator: String { get }
}

/// A constant tag: encodes as `Owner.discriminator` and fails to decode any other value.
public struct AGUIConst<Owner: AGUIDiscriminated>: Codable, Sendable, Hashable {
    public init() {}

    /// The tag's value on the wire.
    public var value: String { Owner.discriminator }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard value == Owner.discriminator else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Expected \"\(Owner.discriminator)\", found \"\(value)\"")
        }
    }

    public func encode(to encoder: any Encoder) throws { try encoder.encodeSingle(Owner.discriminator) }
}

/// One AG-UI event type's model, with the fields every event carries.
public protocol AGUIEventBody: AGUIDiscriminated, Codable, Sendable, Hashable {
    static var eventType: AGUIEventType { get }
    var timestamp: Int? { get }
    var rawEvent: JSONValue? { get }
    var metadata: JSONValue? { get }
}

extension AGUIEventBody {
    public static var discriminator: String { eventType.rawValue }
}

/// An AG-UI event as its `@ag-ui/core` type.
public enum AGUIEventPayload: Sendable, Hashable {
    // jscpd:ignore-start: one case per AG-UI event type.
    case textMessageStart(AGUI.TextMessageStartEvent)
    case textMessageContent(AGUI.TextMessageContentEvent)
    case textMessageEnd(AGUI.TextMessageEndEvent)
    case textMessageChunk(AGUI.TextMessageChunkEvent)
    case toolCallStart(AGUI.ToolCallStartEvent)
    case toolCallArgs(AGUI.ToolCallArgsEvent)
    case toolCallEnd(AGUI.ToolCallEndEvent)
    case toolCallChunk(AGUI.ToolCallChunkEvent)
    case toolCallResult(AGUI.ToolCallResultEvent)
    case stateSnapshot(AGUI.StateSnapshotEvent)
    case stateDelta(AGUI.StateDeltaEvent)
    case messagesSnapshot(AGUI.MessagesSnapshotEvent)
    case activitySnapshot(AGUI.ActivitySnapshotEvent)
    case activityDelta(AGUI.ActivityDeltaEvent)
    case raw(AGUI.RawEvent)
    case custom(AGUI.CustomEvent)
    case runStarted(AGUI.RunStartedEvent)
    case runFinished(AGUI.RunFinishedEvent)
    case runError(AGUI.RunErrorEvent)
    case stepStarted(AGUI.StepStartedEvent)
    case stepFinished(AGUI.StepFinishedEvent)
    case reasoningStart(AGUI.ReasoningStartEvent)
    case reasoningMessageStart(AGUI.ReasoningMessageStartEvent)
    case reasoningMessageContent(AGUI.ReasoningMessageContentEvent)
    case reasoningMessageEnd(AGUI.ReasoningMessageEndEvent)
    case reasoningMessageChunk(AGUI.ReasoningMessageChunkEvent)
    case reasoningEnd(AGUI.ReasoningEndEvent)
    case reasoningEncryptedValue(AGUI.ReasoningEncryptedValueEvent)
    case subagentStarted(AGUI.SubagentStartedEvent)
    case subagentFinished(AGUI.SubagentFinishedEvent)
    case subagentError(AGUI.SubagentErrorEvent)
    /// A type this SDK does not know, or a frame that does not satisfy its AG-UI schema; `AGUIEvent.raw` keeps it.
    // jscpd:ignore-end
    case unknown

    /// The typed event, or `nil` for `.unknown`.
    public var body: (any AGUIEventBody)? {
        // Every case but `.unknown` holds exactly one body; a 32-case switch would exceed the complexity limit.
        Mirror(reflecting: self).children.first?.value as? any AGUIEventBody
    }

    init(raw: JSONValue) {
        self = (try? raw.decode(Tagged.self).payload) ?? .unknown
    }

    private struct Tagged: Decodable {
        let payload: AGUIEventPayload
        init(from decoder: any Decoder) throws { payload = try decodeTagged(decoder, key: "type", AGUIEventPayload.decoders) }
    }

    // jscpd:ignore-start: the payload catalogue, one branch per case.
    static let decoders: [String: TaggedDecoder<AGUIEventPayload>] = taggedDecoders([
        tagged(AGUI.TextMessageStartEvent.self) { .textMessageStart($0) },
        tagged(AGUI.TextMessageContentEvent.self) { .textMessageContent($0) },
        tagged(AGUI.TextMessageEndEvent.self) { .textMessageEnd($0) },
        tagged(AGUI.TextMessageChunkEvent.self) { .textMessageChunk($0) },
        tagged(AGUI.ToolCallStartEvent.self) { .toolCallStart($0) },
        tagged(AGUI.ToolCallArgsEvent.self) { .toolCallArgs($0) },
        tagged(AGUI.ToolCallEndEvent.self) { .toolCallEnd($0) },
        tagged(AGUI.ToolCallChunkEvent.self) { .toolCallChunk($0) },
        tagged(AGUI.ToolCallResultEvent.self) { .toolCallResult($0) },
        tagged(AGUI.StateSnapshotEvent.self) { .stateSnapshot($0) },
        tagged(AGUI.StateDeltaEvent.self) { .stateDelta($0) },
        tagged(AGUI.MessagesSnapshotEvent.self) { .messagesSnapshot($0) },
        tagged(AGUI.ActivitySnapshotEvent.self) { .activitySnapshot($0) },
        tagged(AGUI.ActivityDeltaEvent.self) { .activityDelta($0) },
        tagged(AGUI.RawEvent.self) { .raw($0) },
        tagged(AGUI.CustomEvent.self) { .custom($0) },
        tagged(AGUI.RunStartedEvent.self) { .runStarted($0) },
        tagged(AGUI.RunFinishedEvent.self) { .runFinished($0) },
        tagged(AGUI.RunErrorEvent.self) { .runError($0) },
        tagged(AGUI.StepStartedEvent.self) { .stepStarted($0) },
        tagged(AGUI.StepFinishedEvent.self) { .stepFinished($0) },
        tagged(AGUI.ReasoningStartEvent.self) { .reasoningStart($0) },
        tagged(AGUI.ReasoningMessageStartEvent.self) { .reasoningMessageStart($0) },
        tagged(AGUI.ReasoningMessageContentEvent.self) { .reasoningMessageContent($0) },
        tagged(AGUI.ReasoningMessageEndEvent.self) { .reasoningMessageEnd($0) },
        tagged(AGUI.ReasoningMessageChunkEvent.self) { .reasoningMessageChunk($0) },
        tagged(AGUI.ReasoningEndEvent.self) { .reasoningEnd($0) },
        tagged(AGUI.ReasoningEncryptedValueEvent.self) { .reasoningEncryptedValue($0) },
        tagged(AGUI.SubagentStartedEvent.self) { .subagentStarted($0) },
        tagged(AGUI.SubagentFinishedEvent.self) { .subagentFinished($0) },
        tagged(AGUI.SubagentErrorEvent.self) { .subagentError($0) },
    ])
    // jscpd:ignore-end
}

// MARK: Tagged unions

typealias TaggedDecoder<T> = @Sendable (any Decoder) throws -> T

/// One branch of a tagged union: the member's tag and how to decode it into the union.
func tagged<Member: AGUIDiscriminated & Decodable & SendableMetatype, Union>(
    _ member: Member.Type, _ wrap: @escaping @Sendable (Member) -> Union
) -> (String, TaggedDecoder<Union>) {
    (Member.discriminator, { wrap(try Member(from: $0)) })
}

/// Encodes the one member a union case holds; the member encodes its own tag.
func encodeMember(of union: Any, to encoder: any Encoder) throws {
    guard let member = Mirror(reflecting: union).children.first?.value as? any Encodable else {
        throw EncodingError.invalidValue(union, .init(codingPath: encoder.codingPath, debugDescription: "Not a tagged union case"))
    }
    try member.encode(to: encoder)
}

func taggedDecoders<Union>(_ branches: [(String, TaggedDecoder<Union>)]) -> [String: TaggedDecoder<Union>] {
    Dictionary(uniqueKeysWithValues: branches)
}

/// Decodes the union member whose tag `key` holds; an unknown tag throws.
func decodeTagged<Union>(_ decoder: any Decoder, key: String, _ branches: [String: TaggedDecoder<Union>]) throws -> Union {
    let container = try decoder.container(keyedBy: TagKey.self)
    let tag = try container.decode(String.self, forKey: TagKey(stringValue: key))
    guard let decode = branches[tag] else {
        throw DecodingError.dataCorruptedError(
            forKey: TagKey(stringValue: key), in: container, debugDescription: "Unknown AG-UI \(key) \"\(tag)\"")
    }
    return try decode(decoder)
}

struct TagKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue _: Int) { nil }
}
