import Foundation

// jscpd:ignore-start: one struct per AG-UI schema, which repeat their fields.
extension AGUI {
    /// AG-UI `Interrupt`.
    public struct Interrupt: Codable, Sendable, Hashable {
        public var subagentRunId: String?
        public var id: String
        public var reason: String
        public var message: String?
        public var toolCallId: String?
        public var responseSchema: JSONValue?
        public var expiresAt: String?
        public var metadata: JSONValue?

        public init(
            id: String, reason: String, subagentRunId: String? = nil, message: String? = nil, toolCallId: String? = nil,
            responseSchema: JSONValue? = nil, expiresAt: String? = nil, metadata: JSONValue? = nil
        ) {
            self.subagentRunId = subagentRunId
            self.id = id
            self.reason = reason
            self.message = message
            self.toolCallId = toolCallId
            self.responseSchema = responseSchema
            self.expiresAt = expiresAt
            self.metadata = metadata
        }
    }

    /// AG-UI `RunFinishedSuccessOutcome`.
    public struct RunFinishedSuccessOutcome: AGUIDiscriminated, Codable, Sendable, Hashable {
        public static let discriminator = "success"
        public var type = AGUIConst<RunFinishedSuccessOutcome>()
        public var pendingToolCallIds: [String]?

        public init(pendingToolCallIds: [String]? = nil) {
            self.pendingToolCallIds = pendingToolCallIds
        }
    }

    /// AG-UI `RunFinishedInterruptOutcome`.
    public struct RunFinishedInterruptOutcome: AGUIDiscriminated, Codable, Sendable, Hashable {
        public static let discriminator = "interrupt"
        public var type = AGUIConst<RunFinishedInterruptOutcome>()
        public var interrupts: [Interrupt]

        public init(interrupts: [Interrupt]) {
            self.interrupts = interrupts
        }
    }

    /// AG-UI `RunFinishedCancelledOutcome`.
    public struct RunFinishedCancelledOutcome: AGUIDiscriminated, Codable, Sendable, Hashable {
        public static let discriminator = "cancelled"
        public var type = AGUIConst<RunFinishedCancelledOutcome>()

        public init() {
        }
    }

    /// AG-UI `SubagentFinishedSuccessOutcome`.
    public struct SubagentFinishedSuccessOutcome: AGUIDiscriminated, Codable, Sendable, Hashable {
        public static let discriminator = "success"
        public var type = AGUIConst<SubagentFinishedSuccessOutcome>()

        public init() {
        }
    }

    /// AG-UI `SubagentFinishedSuspendedOutcome`.
    public struct SubagentFinishedSuspendedOutcome: AGUIDiscriminated, Codable, Sendable, Hashable {
        public static let discriminator = "suspended"
        public var type = AGUIConst<SubagentFinishedSuspendedOutcome>()
        public var interruptIds: [String]?

        public init(interruptIds: [String]? = nil) {
            self.interruptIds = interruptIds
        }
    }

    /// AG-UI `AddOperation`.
    public struct AddOperation: AGUIDiscriminated, Codable, Sendable, Hashable {
        public static let discriminator = "add"
        public var op = AGUIConst<AddOperation>()
        public var path: String
        public var value: JSONValue

        public init(path: String, value: JSONValue) {
            self.path = path
            self.value = value
        }
    }

    /// AG-UI `RemoveOperation`.
    public struct RemoveOperation: AGUIDiscriminated, Codable, Sendable, Hashable {
        public static let discriminator = "remove"
        public var op = AGUIConst<RemoveOperation>()
        public var path: String

        public init(path: String) {
            self.path = path
        }
    }

    /// AG-UI `ReplaceOperation`.
    public struct ReplaceOperation: AGUIDiscriminated, Codable, Sendable, Hashable {
        public static let discriminator = "replace"
        public var op = AGUIConst<ReplaceOperation>()
        public var path: String
        public var value: JSONValue

        public init(path: String, value: JSONValue) {
            self.path = path
            self.value = value
        }
    }

    /// AG-UI `MoveOperation`.
    public struct MoveOperation: AGUIDiscriminated, Codable, Sendable, Hashable {
        public static let discriminator = "move"
        public var op = AGUIConst<MoveOperation>()
        public var from: String
        public var path: String

        public init(from: String, path: String) {
            self.from = from
            self.path = path
        }
    }

    /// AG-UI `CopyOperation`.
    public struct CopyOperation: AGUIDiscriminated, Codable, Sendable, Hashable {
        public static let discriminator = "copy"
        public var op = AGUIConst<CopyOperation>()
        public var from: String
        public var path: String

        public init(from: String, path: String) {
            self.from = from
            self.path = path
        }
    }

    /// AG-UI `TestOperation`.
    public struct TestOperation: AGUIDiscriminated, Codable, Sendable, Hashable {
        public static let discriminator = "test"
        public var op = AGUIConst<TestOperation>()
        public var path: String
        public var value: JSONValue

        public init(path: String, value: JSONValue) {
            self.path = path
            self.value = value
        }
    }

    /// AG-UI `RunAgentInput`.
    public struct RunAgentInput: Codable, Sendable, Hashable {
        public var threadId: String
        public var runId: String
        public var protocolVersion: String?
        public var parentRunId: String?
        public var state: JSONValue?
        public var messages: [Message]
        public var tools: [Tool]?
        public var context: [Context]?
        public var forwardedProps: JSONValue?
        public var resume: [ResumeEntry]?

        public init(
            threadId: String, runId: String, messages: [Message], protocolVersion: String? = nil, parentRunId: String? = nil,
            state: JSONValue? = nil, tools: [Tool]? = nil, context: [Context]? = nil, forwardedProps: JSONValue? = nil,
            resume: [ResumeEntry]? = nil
        ) {
            self.threadId = threadId
            self.runId = runId
            self.protocolVersion = protocolVersion
            self.parentRunId = parentRunId
            self.state = state
            self.messages = messages
            self.tools = tools
            self.context = context
            self.forwardedProps = forwardedProps
            self.resume = resume
        }
    }

    /// AG-UI `Tool`.
    public struct Tool: Codable, Sendable, Hashable {
        public var name: String
        public var description: String
        public var parameters: JSONValue?
        public var metadata: JSONValue?

        public init(name: String, description: String, parameters: JSONValue? = nil, metadata: JSONValue? = nil) {
            self.name = name
            self.description = description
            self.parameters = parameters
            self.metadata = metadata
        }
    }

    /// AG-UI `Context`.
    public struct Context: Codable, Sendable, Hashable {
        public var description: String
        public var value: String

        public init(description: String, value: String) {
            self.description = description
            self.value = value
        }
    }

    /// AG-UI `ResumeEntry`.
    public struct ResumeEntry: Codable, Sendable, Hashable {
        public var interruptId: String
        public var status: ResumeStatus
        public var payload: JSONValue?
        public var metadata: JSONValue?

        public init(interruptId: String, status: ResumeStatus, payload: JSONValue? = nil, metadata: JSONValue? = nil) {
            self.interruptId = interruptId
            self.status = status
            self.payload = payload
            self.metadata = metadata
        }
    }

    /// AG-UI `TokenUsage`.
    public struct TokenUsage: Codable, Sendable, Hashable {
        public var provider: String?
        public var model: String?
        public var inputTokens: Int?
        public var outputTokens: Int?
        public var totalTokens: Int?
        public var reasoningTokens: Int?
        public var cachedInputTokens: Int?
        public var cacheWriteInputTokens: Int?

        public init(
            provider: String? = nil, model: String? = nil, inputTokens: Int? = nil, outputTokens: Int? = nil, totalTokens: Int? = nil,
            reasoningTokens: Int? = nil, cachedInputTokens: Int? = nil, cacheWriteInputTokens: Int? = nil
        ) {
            self.provider = provider
            self.model = model
            self.inputTokens = inputTokens
            self.outputTokens = outputTokens
            self.totalTokens = totalTokens
            self.reasoningTokens = reasoningTokens
            self.cachedInputTokens = cachedInputTokens
            self.cacheWriteInputTokens = cacheWriteInputTokens
        }
    }
}
// jscpd:ignore-end

extension AGUI.RunAgentInput {
    // `state` may be an explicit `null`, which synthesized decoding would read as absent.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        threadId = try container.decode(String.self, forKey: .threadId)
        runId = try container.decode(String.self, forKey: .runId)
        protocolVersion = try container.decodeIfPresent(String.self, forKey: .protocolVersion)
        parentRunId = try container.decodeIfPresent(String.self, forKey: .parentRunId)
        state = container.contains(.state) ? try container.decode(JSONValue.self, forKey: .state) : JSONValue?.none
        messages = try container.decode([AGUI.Message].self, forKey: .messages)
        tools = try container.decodeIfPresent([AGUI.Tool].self, forKey: .tools)
        context = try container.decodeIfPresent([AGUI.Context].self, forKey: .context)
        forwardedProps = try container.decodeIfPresent(JSONValue.self, forKey: .forwardedProps)
        resume = try container.decodeIfPresent([AGUI.ResumeEntry].self, forKey: .resume)
    }
}
