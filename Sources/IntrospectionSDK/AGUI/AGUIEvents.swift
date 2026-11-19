import Foundation

// jscpd:ignore-start: one struct per AG-UI event schema, which repeat the base event fields.
extension AGUI {
    /// `TEXT_MESSAGE_START`.
    public struct TextMessageStartEvent: AGUIEventBody {
        public static let eventType: AGUIEventType = .textMessageStart
        public var type = AGUIConst<TextMessageStartEvent>()
        public var timestamp: Int?
        public var rawEvent: JSONValue?
        public var metadata: JSONValue?
        public var subagentRunId: String?
        public var messageId: String
        public var role: TextMessageRole?
        public var name: String?

        public init(
            messageId: String, subagentRunId: String? = nil, role: TextMessageRole? = nil, name: String? = nil, timestamp: Int? = nil,
            rawEvent: JSONValue? = nil, metadata: JSONValue? = nil
        ) {
            self.timestamp = timestamp
            self.rawEvent = rawEvent
            self.metadata = metadata
            self.subagentRunId = subagentRunId
            self.messageId = messageId
            self.role = role
            self.name = name
        }
    }

    /// `TEXT_MESSAGE_CONTENT`.
    public struct TextMessageContentEvent: AGUIEventBody {
        public static let eventType: AGUIEventType = .textMessageContent
        public var type = AGUIConst<TextMessageContentEvent>()
        public var timestamp: Int?
        public var rawEvent: JSONValue?
        public var metadata: JSONValue?
        public var subagentRunId: String?
        public var messageId: String
        public var delta: String

        public init(
            messageId: String, delta: String, subagentRunId: String? = nil, timestamp: Int? = nil, rawEvent: JSONValue? = nil,
            metadata: JSONValue? = nil
        ) {
            self.timestamp = timestamp
            self.rawEvent = rawEvent
            self.metadata = metadata
            self.subagentRunId = subagentRunId
            self.messageId = messageId
            self.delta = delta
        }
    }

    /// `TEXT_MESSAGE_END`.
    public struct TextMessageEndEvent: AGUIEventBody {
        public static let eventType: AGUIEventType = .textMessageEnd
        public var type = AGUIConst<TextMessageEndEvent>()
        public var timestamp: Int?
        public var rawEvent: JSONValue?
        public var metadata: JSONValue?
        public var subagentRunId: String?
        public var messageId: String

        public init(
            messageId: String, subagentRunId: String? = nil, timestamp: Int? = nil, rawEvent: JSONValue? = nil, metadata: JSONValue? = nil
        ) {
            self.timestamp = timestamp
            self.rawEvent = rawEvent
            self.metadata = metadata
            self.subagentRunId = subagentRunId
            self.messageId = messageId
        }
    }

    /// `TEXT_MESSAGE_CHUNK`.
    public struct TextMessageChunkEvent: AGUIEventBody {
        public static let eventType: AGUIEventType = .textMessageChunk
        public var type = AGUIConst<TextMessageChunkEvent>()
        public var timestamp: Int?
        public var rawEvent: JSONValue?
        public var metadata: JSONValue?
        public var subagentRunId: String?
        public var messageId: String?
        public var role: TextMessageRole?
        public var delta: String?
        public var name: String?

        public init(
            subagentRunId: String? = nil, messageId: String? = nil, role: TextMessageRole? = nil, delta: String? = nil, name: String? = nil,
            timestamp: Int? = nil, rawEvent: JSONValue? = nil, metadata: JSONValue? = nil
        ) {
            self.timestamp = timestamp
            self.rawEvent = rawEvent
            self.metadata = metadata
            self.subagentRunId = subagentRunId
            self.messageId = messageId
            self.role = role
            self.delta = delta
            self.name = name
        }
    }

    /// `TOOL_CALL_START`.
    public struct ToolCallStartEvent: AGUIEventBody {
        public static let eventType: AGUIEventType = .toolCallStart
        public var type = AGUIConst<ToolCallStartEvent>()
        public var timestamp: Int?
        public var rawEvent: JSONValue?
        public var metadata: JSONValue?
        public var subagentRunId: String?
        public var toolCallId: String
        public var toolCallName: String
        public var parentMessageId: String?

        public init(
            toolCallId: String, toolCallName: String, subagentRunId: String? = nil, parentMessageId: String? = nil, timestamp: Int? = nil,
            rawEvent: JSONValue? = nil, metadata: JSONValue? = nil
        ) {
            self.timestamp = timestamp
            self.rawEvent = rawEvent
            self.metadata = metadata
            self.subagentRunId = subagentRunId
            self.toolCallId = toolCallId
            self.toolCallName = toolCallName
            self.parentMessageId = parentMessageId
        }
    }

    /// `TOOL_CALL_ARGS`.
    public struct ToolCallArgsEvent: AGUIEventBody {
        public static let eventType: AGUIEventType = .toolCallArgs
        public var type = AGUIConst<ToolCallArgsEvent>()
        public var timestamp: Int?
        public var rawEvent: JSONValue?
        public var metadata: JSONValue?
        public var subagentRunId: String?
        public var toolCallId: String
        public var delta: String

        public init(
            toolCallId: String, delta: String, subagentRunId: String? = nil, timestamp: Int? = nil, rawEvent: JSONValue? = nil,
            metadata: JSONValue? = nil
        ) {
            self.timestamp = timestamp
            self.rawEvent = rawEvent
            self.metadata = metadata
            self.subagentRunId = subagentRunId
            self.toolCallId = toolCallId
            self.delta = delta
        }
    }

    /// `TOOL_CALL_END`.
    public struct ToolCallEndEvent: AGUIEventBody {
        public static let eventType: AGUIEventType = .toolCallEnd
        public var type = AGUIConst<ToolCallEndEvent>()
        public var timestamp: Int?
        public var rawEvent: JSONValue?
        public var metadata: JSONValue?
        public var subagentRunId: String?
        public var toolCallId: String

        public init(
            toolCallId: String, subagentRunId: String? = nil, timestamp: Int? = nil, rawEvent: JSONValue? = nil, metadata: JSONValue? = nil
        ) {
            self.timestamp = timestamp
            self.rawEvent = rawEvent
            self.metadata = metadata
            self.subagentRunId = subagentRunId
            self.toolCallId = toolCallId
        }
    }

    /// `TOOL_CALL_CHUNK`.
    public struct ToolCallChunkEvent: AGUIEventBody {
        public static let eventType: AGUIEventType = .toolCallChunk
        public var type = AGUIConst<ToolCallChunkEvent>()
        public var timestamp: Int?
        public var rawEvent: JSONValue?
        public var metadata: JSONValue?
        public var subagentRunId: String?
        public var toolCallId: String?
        public var toolCallName: String?
        public var parentMessageId: String?
        public var delta: String?

        public init(
            subagentRunId: String? = nil, toolCallId: String? = nil, toolCallName: String? = nil, parentMessageId: String? = nil,
            delta: String? = nil, timestamp: Int? = nil, rawEvent: JSONValue? = nil, metadata: JSONValue? = nil
        ) {
            self.timestamp = timestamp
            self.rawEvent = rawEvent
            self.metadata = metadata
            self.subagentRunId = subagentRunId
            self.toolCallId = toolCallId
            self.toolCallName = toolCallName
            self.parentMessageId = parentMessageId
            self.delta = delta
        }
    }

    /// `TOOL_CALL_RESULT`.
    public struct ToolCallResultEvent: AGUIEventBody {
        public static let eventType: AGUIEventType = .toolCallResult
        public var type = AGUIConst<ToolCallResultEvent>()
        public var timestamp: Int?
        public var rawEvent: JSONValue?
        public var metadata: JSONValue?
        public var subagentRunId: String?
        public var messageId: String
        public var toolCallId: String
        public var content: MessageContent
        public var role: AGUIConst<ToolMessage>?

        public init(
            messageId: String, toolCallId: String, content: MessageContent, subagentRunId: String? = nil,
            role: AGUIConst<ToolMessage>? = nil, timestamp: Int? = nil, rawEvent: JSONValue? = nil, metadata: JSONValue? = nil
        ) {
            self.timestamp = timestamp
            self.rawEvent = rawEvent
            self.metadata = metadata
            self.subagentRunId = subagentRunId
            self.messageId = messageId
            self.toolCallId = toolCallId
            self.content = content
            self.role = role
        }
    }

    /// `STATE_SNAPSHOT`.
    public struct StateSnapshotEvent: AGUIEventBody {
        public static let eventType: AGUIEventType = .stateSnapshot
        public var type = AGUIConst<StateSnapshotEvent>()
        public var timestamp: Int?
        public var rawEvent: JSONValue?
        public var metadata: JSONValue?
        public var subagentRunId: String?
        public var snapshot: JSONValue

        public init(
            snapshot: JSONValue, subagentRunId: String? = nil, timestamp: Int? = nil, rawEvent: JSONValue? = nil, metadata: JSONValue? = nil
        ) {
            self.timestamp = timestamp
            self.rawEvent = rawEvent
            self.metadata = metadata
            self.subagentRunId = subagentRunId
            self.snapshot = snapshot
        }
    }

    /// `STATE_DELTA`.
    public struct StateDeltaEvent: AGUIEventBody {
        public static let eventType: AGUIEventType = .stateDelta
        public var type = AGUIConst<StateDeltaEvent>()
        public var timestamp: Int?
        public var rawEvent: JSONValue?
        public var metadata: JSONValue?
        public var subagentRunId: String?
        public var delta: [JsonPatchOperation]

        public init(
            delta: [JsonPatchOperation], subagentRunId: String? = nil, timestamp: Int? = nil, rawEvent: JSONValue? = nil,
            metadata: JSONValue? = nil
        ) {
            self.timestamp = timestamp
            self.rawEvent = rawEvent
            self.metadata = metadata
            self.subagentRunId = subagentRunId
            self.delta = delta
        }
    }

    /// `MESSAGES_SNAPSHOT`.
    public struct MessagesSnapshotEvent: AGUIEventBody {
        public static let eventType: AGUIEventType = .messagesSnapshot
        public var type = AGUIConst<MessagesSnapshotEvent>()
        public var timestamp: Int?
        public var rawEvent: JSONValue?
        public var metadata: JSONValue?
        public var messages: [Message]

        public init(messages: [Message], timestamp: Int? = nil, rawEvent: JSONValue? = nil, metadata: JSONValue? = nil) {
            self.timestamp = timestamp
            self.rawEvent = rawEvent
            self.metadata = metadata
            self.messages = messages
        }
    }

    /// `ACTIVITY_SNAPSHOT`.
    public struct ActivitySnapshotEvent: AGUIEventBody {
        public static let eventType: AGUIEventType = .activitySnapshot
        public var type = AGUIConst<ActivitySnapshotEvent>()
        public var timestamp: Int?
        public var rawEvent: JSONValue?
        public var metadata: JSONValue?
        public var subagentRunId: String?
        public var messageId: String
        public var activityType: String
        public var content: JSONValue
        public var replace: Bool?

        public init(
            messageId: String, activityType: String, content: JSONValue, subagentRunId: String? = nil, replace: Bool? = nil,
            timestamp: Int? = nil, rawEvent: JSONValue? = nil, metadata: JSONValue? = nil
        ) {
            self.timestamp = timestamp
            self.rawEvent = rawEvent
            self.metadata = metadata
            self.subagentRunId = subagentRunId
            self.messageId = messageId
            self.activityType = activityType
            self.content = content
            self.replace = replace
        }
    }

    /// `ACTIVITY_DELTA`.
    public struct ActivityDeltaEvent: AGUIEventBody {
        public static let eventType: AGUIEventType = .activityDelta
        public var type = AGUIConst<ActivityDeltaEvent>()
        public var timestamp: Int?
        public var rawEvent: JSONValue?
        public var metadata: JSONValue?
        public var subagentRunId: String?
        public var messageId: String
        public var activityType: String
        public var patch: [JsonPatchOperation]

        public init(
            messageId: String, activityType: String, patch: [JsonPatchOperation], subagentRunId: String? = nil, timestamp: Int? = nil,
            rawEvent: JSONValue? = nil, metadata: JSONValue? = nil
        ) {
            self.timestamp = timestamp
            self.rawEvent = rawEvent
            self.metadata = metadata
            self.subagentRunId = subagentRunId
            self.messageId = messageId
            self.activityType = activityType
            self.patch = patch
        }
    }

    /// `RAW`.
    public struct RawEvent: AGUIEventBody {
        public static let eventType: AGUIEventType = .raw
        public var type = AGUIConst<RawEvent>()
        public var timestamp: Int?
        public var rawEvent: JSONValue?
        public var metadata: JSONValue?
        public var subagentRunId: String?
        public var event: JSONValue
        public var source: String?

        public init(
            event: JSONValue, subagentRunId: String? = nil, source: String? = nil, timestamp: Int? = nil, rawEvent: JSONValue? = nil,
            metadata: JSONValue? = nil
        ) {
            self.timestamp = timestamp
            self.rawEvent = rawEvent
            self.metadata = metadata
            self.subagentRunId = subagentRunId
            self.event = event
            self.source = source
        }
    }

    /// `CUSTOM`.
    public struct CustomEvent: AGUIEventBody {
        public static let eventType: AGUIEventType = .custom
        public var type = AGUIConst<CustomEvent>()
        public var timestamp: Int?
        public var rawEvent: JSONValue?
        public var metadata: JSONValue?
        public var subagentRunId: String?
        public var name: String
        public var value: JSONValue

        public init(
            name: String, value: JSONValue, subagentRunId: String? = nil, timestamp: Int? = nil, rawEvent: JSONValue? = nil,
            metadata: JSONValue? = nil
        ) {
            self.timestamp = timestamp
            self.rawEvent = rawEvent
            self.metadata = metadata
            self.subagentRunId = subagentRunId
            self.name = name
            self.value = value
        }
    }

    /// `RUN_STARTED`.
    public struct RunStartedEvent: AGUIEventBody {
        public static let eventType: AGUIEventType = .runStarted
        public var type = AGUIConst<RunStartedEvent>()
        public var timestamp: Int?
        public var rawEvent: JSONValue?
        public var metadata: JSONValue?
        public var threadId: String
        public var runId: String
        public var protocolVersion: String?
        public var parentRunId: String?
        public var input: RunAgentInput?

        public init(
            threadId: String, runId: String, protocolVersion: String? = nil, parentRunId: String? = nil, input: RunAgentInput? = nil,
            timestamp: Int? = nil, rawEvent: JSONValue? = nil, metadata: JSONValue? = nil
        ) {
            self.timestamp = timestamp
            self.rawEvent = rawEvent
            self.metadata = metadata
            self.threadId = threadId
            self.runId = runId
            self.protocolVersion = protocolVersion
            self.parentRunId = parentRunId
            self.input = input
        }
    }

    /// `RUN_FINISHED`.
    public struct RunFinishedEvent: AGUIEventBody {
        public static let eventType: AGUIEventType = .runFinished
        public var type = AGUIConst<RunFinishedEvent>()
        public var timestamp: Int?
        public var rawEvent: JSONValue?
        public var metadata: JSONValue?
        public var threadId: String
        public var runId: String
        public var result: JSONValue?
        public var outcome: RunFinishedOutcome?
        public var usage: [TokenUsage]?

        public init(
            threadId: String, runId: String, result: JSONValue? = nil, outcome: RunFinishedOutcome? = nil, usage: [TokenUsage]? = nil,
            timestamp: Int? = nil, rawEvent: JSONValue? = nil, metadata: JSONValue? = nil
        ) {
            self.timestamp = timestamp
            self.rawEvent = rawEvent
            self.metadata = metadata
            self.threadId = threadId
            self.runId = runId
            self.result = result
            self.outcome = outcome
            self.usage = usage
        }
    }

    /// `RUN_ERROR`.
    public struct RunErrorEvent: AGUIEventBody {
        public static let eventType: AGUIEventType = .runError
        public var type = AGUIConst<RunErrorEvent>()
        public var timestamp: Int?
        public var rawEvent: JSONValue?
        public var metadata: JSONValue?
        public var message: String
        public var code: String?
        public var usage: [TokenUsage]?

        public init(
            message: String, code: String? = nil, usage: [TokenUsage]? = nil, timestamp: Int? = nil, rawEvent: JSONValue? = nil,
            metadata: JSONValue? = nil
        ) {
            self.timestamp = timestamp
            self.rawEvent = rawEvent
            self.metadata = metadata
            self.message = message
            self.code = code
            self.usage = usage
        }
    }

    /// `STEP_STARTED`.
    public struct StepStartedEvent: AGUIEventBody {
        public static let eventType: AGUIEventType = .stepStarted
        public var type = AGUIConst<StepStartedEvent>()
        public var timestamp: Int?
        public var rawEvent: JSONValue?
        public var metadata: JSONValue?
        public var subagentRunId: String?
        public var stepName: String

        public init(
            stepName: String, subagentRunId: String? = nil, timestamp: Int? = nil, rawEvent: JSONValue? = nil, metadata: JSONValue? = nil
        ) {
            self.timestamp = timestamp
            self.rawEvent = rawEvent
            self.metadata = metadata
            self.subagentRunId = subagentRunId
            self.stepName = stepName
        }
    }

    /// `STEP_FINISHED`.
    public struct StepFinishedEvent: AGUIEventBody {
        public static let eventType: AGUIEventType = .stepFinished
        public var type = AGUIConst<StepFinishedEvent>()
        public var timestamp: Int?
        public var rawEvent: JSONValue?
        public var metadata: JSONValue?
        public var subagentRunId: String?
        public var stepName: String

        public init(
            stepName: String, subagentRunId: String? = nil, timestamp: Int? = nil, rawEvent: JSONValue? = nil, metadata: JSONValue? = nil
        ) {
            self.timestamp = timestamp
            self.rawEvent = rawEvent
            self.metadata = metadata
            self.subagentRunId = subagentRunId
            self.stepName = stepName
        }
    }

    /// `REASONING_START`.
    public struct ReasoningStartEvent: AGUIEventBody {
        public static let eventType: AGUIEventType = .reasoningStart
        public var type = AGUIConst<ReasoningStartEvent>()
        public var timestamp: Int?
        public var rawEvent: JSONValue?
        public var metadata: JSONValue?
        public var subagentRunId: String?
        public var messageId: String

        public init(
            messageId: String, subagentRunId: String? = nil, timestamp: Int? = nil, rawEvent: JSONValue? = nil, metadata: JSONValue? = nil
        ) {
            self.timestamp = timestamp
            self.rawEvent = rawEvent
            self.metadata = metadata
            self.subagentRunId = subagentRunId
            self.messageId = messageId
        }
    }

    /// `REASONING_MESSAGE_START`.
    public struct ReasoningMessageStartEvent: AGUIEventBody {
        public static let eventType: AGUIEventType = .reasoningMessageStart
        public var type = AGUIConst<ReasoningMessageStartEvent>()
        public var timestamp: Int?
        public var rawEvent: JSONValue?
        public var metadata: JSONValue?
        public var subagentRunId: String?
        public var messageId: String
        public var role = AGUIConst<ReasoningMessage>()

        public init(
            messageId: String, subagentRunId: String? = nil, timestamp: Int? = nil, rawEvent: JSONValue? = nil, metadata: JSONValue? = nil
        ) {
            self.timestamp = timestamp
            self.rawEvent = rawEvent
            self.metadata = metadata
            self.subagentRunId = subagentRunId
            self.messageId = messageId
        }
    }

    /// `REASONING_MESSAGE_CONTENT`.
    public struct ReasoningMessageContentEvent: AGUIEventBody {
        public static let eventType: AGUIEventType = .reasoningMessageContent
        public var type = AGUIConst<ReasoningMessageContentEvent>()
        public var timestamp: Int?
        public var rawEvent: JSONValue?
        public var metadata: JSONValue?
        public var subagentRunId: String?
        public var messageId: String
        public var delta: String

        public init(
            messageId: String, delta: String, subagentRunId: String? = nil, timestamp: Int? = nil, rawEvent: JSONValue? = nil,
            metadata: JSONValue? = nil
        ) {
            self.timestamp = timestamp
            self.rawEvent = rawEvent
            self.metadata = metadata
            self.subagentRunId = subagentRunId
            self.messageId = messageId
            self.delta = delta
        }
    }

    /// `REASONING_MESSAGE_END`.
    public struct ReasoningMessageEndEvent: AGUIEventBody {
        public static let eventType: AGUIEventType = .reasoningMessageEnd
        public var type = AGUIConst<ReasoningMessageEndEvent>()
        public var timestamp: Int?
        public var rawEvent: JSONValue?
        public var metadata: JSONValue?
        public var subagentRunId: String?
        public var messageId: String

        public init(
            messageId: String, subagentRunId: String? = nil, timestamp: Int? = nil, rawEvent: JSONValue? = nil, metadata: JSONValue? = nil
        ) {
            self.timestamp = timestamp
            self.rawEvent = rawEvent
            self.metadata = metadata
            self.subagentRunId = subagentRunId
            self.messageId = messageId
        }
    }

    /// `REASONING_MESSAGE_CHUNK`.
    public struct ReasoningMessageChunkEvent: AGUIEventBody {
        public static let eventType: AGUIEventType = .reasoningMessageChunk
        public var type = AGUIConst<ReasoningMessageChunkEvent>()
        public var timestamp: Int?
        public var rawEvent: JSONValue?
        public var metadata: JSONValue?
        public var subagentRunId: String?
        public var messageId: String?
        public var delta: String?

        public init(
            subagentRunId: String? = nil, messageId: String? = nil, delta: String? = nil, timestamp: Int? = nil, rawEvent: JSONValue? = nil,
            metadata: JSONValue? = nil
        ) {
            self.timestamp = timestamp
            self.rawEvent = rawEvent
            self.metadata = metadata
            self.subagentRunId = subagentRunId
            self.messageId = messageId
            self.delta = delta
        }
    }

    /// `REASONING_END`.
    public struct ReasoningEndEvent: AGUIEventBody {
        public static let eventType: AGUIEventType = .reasoningEnd
        public var type = AGUIConst<ReasoningEndEvent>()
        public var timestamp: Int?
        public var rawEvent: JSONValue?
        public var metadata: JSONValue?
        public var subagentRunId: String?
        public var messageId: String

        public init(
            messageId: String, subagentRunId: String? = nil, timestamp: Int? = nil, rawEvent: JSONValue? = nil, metadata: JSONValue? = nil
        ) {
            self.timestamp = timestamp
            self.rawEvent = rawEvent
            self.metadata = metadata
            self.subagentRunId = subagentRunId
            self.messageId = messageId
        }
    }

    /// `REASONING_ENCRYPTED_VALUE`.
    public struct ReasoningEncryptedValueEvent: AGUIEventBody {
        public static let eventType: AGUIEventType = .reasoningEncryptedValue
        public var type = AGUIConst<ReasoningEncryptedValueEvent>()
        public var timestamp: Int?
        public var rawEvent: JSONValue?
        public var metadata: JSONValue?
        public var subagentRunId: String?
        public var subtype: ReasoningEncryptedValueSubtype
        public var entityId: String
        public var encryptedValue: String

        public init(
            subtype: ReasoningEncryptedValueSubtype, entityId: String, encryptedValue: String, subagentRunId: String? = nil,
            timestamp: Int? = nil, rawEvent: JSONValue? = nil, metadata: JSONValue? = nil
        ) {
            self.timestamp = timestamp
            self.rawEvent = rawEvent
            self.metadata = metadata
            self.subagentRunId = subagentRunId
            self.subtype = subtype
            self.entityId = entityId
            self.encryptedValue = encryptedValue
        }
    }

    /// `SUBAGENT_STARTED`.
    public struct SubagentStartedEvent: AGUIEventBody {
        public static let eventType: AGUIEventType = .subagentStarted
        public var type = AGUIConst<SubagentStartedEvent>()
        public var timestamp: Int?
        public var rawEvent: JSONValue?
        public var metadata: JSONValue?
        public var subagentRunId: String
        public var name: String
        public var description: String?
        public var parentSubagentRunId: String?
        public var parentToolCallId: String?
        public var parentMessageId: String?

        public init(
            subagentRunId: String, name: String, description: String? = nil, parentSubagentRunId: String? = nil,
            parentToolCallId: String? = nil, parentMessageId: String? = nil, timestamp: Int? = nil, rawEvent: JSONValue? = nil,
            metadata: JSONValue? = nil
        ) {
            self.timestamp = timestamp
            self.rawEvent = rawEvent
            self.metadata = metadata
            self.subagentRunId = subagentRunId
            self.name = name
            self.description = description
            self.parentSubagentRunId = parentSubagentRunId
            self.parentToolCallId = parentToolCallId
            self.parentMessageId = parentMessageId
        }
    }

    /// `SUBAGENT_FINISHED`.
    public struct SubagentFinishedEvent: AGUIEventBody {
        public static let eventType: AGUIEventType = .subagentFinished
        public var type = AGUIConst<SubagentFinishedEvent>()
        public var timestamp: Int?
        public var rawEvent: JSONValue?
        public var metadata: JSONValue?
        public var subagentRunId: String
        public var result: JSONValue?
        public var outcome: SubagentFinishedOutcome?

        public init(
            subagentRunId: String, result: JSONValue? = nil, outcome: SubagentFinishedOutcome? = nil, timestamp: Int? = nil,
            rawEvent: JSONValue? = nil, metadata: JSONValue? = nil
        ) {
            self.timestamp = timestamp
            self.rawEvent = rawEvent
            self.metadata = metadata
            self.subagentRunId = subagentRunId
            self.result = result
            self.outcome = outcome
        }
    }

    /// `SUBAGENT_ERROR`.
    public struct SubagentErrorEvent: AGUIEventBody {
        public static let eventType: AGUIEventType = .subagentError
        public var type = AGUIConst<SubagentErrorEvent>()
        public var timestamp: Int?
        public var rawEvent: JSONValue?
        public var metadata: JSONValue?
        public var subagentRunId: String
        public var message: String
        public var code: String?

        public init(
            subagentRunId: String, message: String, code: String? = nil, timestamp: Int? = nil, rawEvent: JSONValue? = nil,
            metadata: JSONValue? = nil
        ) {
            self.timestamp = timestamp
            self.rawEvent = rawEvent
            self.metadata = metadata
            self.subagentRunId = subagentRunId
            self.message = message
            self.code = code
        }
    }
}
// jscpd:ignore-end
