import Foundation

/// One AG-UI protocol event, as streamed from a task run. The full event is
/// kept as `raw`; the common fields have typed accessors.
public struct AGUIEvent: Sendable, Hashable, Codable {
    public let raw: JSONValue

    public init(raw: JSONValue) { self.raw = raw }

    public init(from decoder: any Decoder) throws {
        raw = try JSONValue(from: decoder)
    }

    public func encode(to encoder: any Encoder) throws {
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
    /// Extra information attached to the event.
    public var metadata: JSONObject? { raw["metadata"]?.objectValue }
    /// The subagent invocation that produced the event; `nil` means the parent agent did.
    public var subagentRunId: String? { raw["subagentRunId"]?.stringValue }
    /// `RUN_FINISHED`: why the run ended, as sent.
    public var outcome: JSONValue? { raw["outcome"] }
    /// `RUN_FINISHED`: the outcome's type; an absent outcome means success. `nil` for other events.
    public var outcomeType: AGUIRunOutcomeType? {
        guard eventType == .runFinished else { return nil }
        guard let outcome else { return .success }
        return AGUIRunOutcomeType(rawValue: outcome["type"]?.stringValue ?? "")
    }
    /// `RUN_FINISHED` with an `interrupt` outcome: what the run is waiting for.
    public var interrupts: [JSONValue]? { outcome?["interrupts"]?.arrayValue }

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
}

/// Why a run ended, from `RUN_FINISHED.outcome.type`. Unknown types are preserved.
public struct AGUIRunOutcomeType: RawRepresentable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }

    public static let success: AGUIRunOutcomeType = "success"
    public static let interrupt: AGUIRunOutcomeType = "interrupt"
    public static let cancelled: AGUIRunOutcomeType = "cancelled"
}
