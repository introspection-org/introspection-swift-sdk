import Foundation

/// One AG-UI protocol event, as streamed from a task run. The full event is
/// kept as `raw`; the common fields have typed accessors.
public struct AGUIEvent: Sendable, Hashable, Codable {
    public let raw: JSONValue

    public init(raw: JSONValue) { self.raw = raw }

    public init(from decoder: Decoder) throws {
        raw = try JSONValue(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try raw.encode(to: encoder)
    }

    /// The AG-UI `type`, for example `TEXT_MESSAGE_CONTENT` or `RUN_FINISHED`.
    public var type: String { raw["type"]?.stringValue ?? "" }
    public var eventType: AGUIEventType { AGUIEventType(rawValue: type) }

    public var messageId: String? { raw["messageId"]?.stringValue }
    public var role: String? { raw["role"]?.stringValue }
    public var delta: String? { raw["delta"]?.stringValue }
    public var toolCallId: String? { raw["toolCallId"]?.stringValue }
    public var toolCallName: String? { raw["toolCallName"]?.stringValue }
    public var parentMessageId: String? { raw["parentMessageId"]?.stringValue }
    public var content: JSONValue? { raw["content"] }
    public var threadId: String? { raw["threadId"]?.stringValue }
    public var runId: String? { raw["runId"]?.stringValue }
    public var message: String? { raw["message"]?.stringValue }
    public var code: String? { raw["code"]?.stringValue }
    /// `CUSTOM` and `RAW` events.
    public var name: String? { raw["name"]?.stringValue }
    public var value: JSONValue? { raw["value"] }
    public var snapshot: JSONValue? { raw["snapshot"] }
    public var timestamp: Double? { raw["timestamp"]?.doubleValue }

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

    public static let runStarted: AGUIEventType = "RUN_STARTED"
    public static let runFinished: AGUIEventType = "RUN_FINISHED"
    public static let runError: AGUIEventType = "RUN_ERROR"
    public static let stepStarted: AGUIEventType = "STEP_STARTED"
    public static let stepFinished: AGUIEventType = "STEP_FINISHED"
    public static let textMessageStart: AGUIEventType = "TEXT_MESSAGE_START"
    public static let textMessageContent: AGUIEventType = "TEXT_MESSAGE_CONTENT"
    public static let textMessageEnd: AGUIEventType = "TEXT_MESSAGE_END"
    public static let textMessageChunk: AGUIEventType = "TEXT_MESSAGE_CHUNK"
    public static let thinkingStart: AGUIEventType = "THINKING_START"
    public static let thinkingEnd: AGUIEventType = "THINKING_END"
    public static let thinkingTextMessageStart: AGUIEventType = "THINKING_TEXT_MESSAGE_START"
    public static let thinkingTextMessageContent: AGUIEventType = "THINKING_TEXT_MESSAGE_CONTENT"
    public static let thinkingTextMessageEnd: AGUIEventType = "THINKING_TEXT_MESSAGE_END"
    public static let toolCallStart: AGUIEventType = "TOOL_CALL_START"
    public static let toolCallArgs: AGUIEventType = "TOOL_CALL_ARGS"
    public static let toolCallEnd: AGUIEventType = "TOOL_CALL_END"
    public static let toolCallChunk: AGUIEventType = "TOOL_CALL_CHUNK"
    public static let toolCallResult: AGUIEventType = "TOOL_CALL_RESULT"
    public static let stateSnapshot: AGUIEventType = "STATE_SNAPSHOT"
    public static let stateDelta: AGUIEventType = "STATE_DELTA"
    public static let messagesSnapshot: AGUIEventType = "MESSAGES_SNAPSHOT"
    public static let raw: AGUIEventType = "RAW"
    public static let custom: AGUIEventType = "CUSTOM"
}
