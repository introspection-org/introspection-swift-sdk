import Foundation

// jscpd:ignore-start: one struct per AG-UI message and content schema, which repeat their fields.
extension AGUI {
    /// AG-UI `DeveloperMessage`.
    public struct DeveloperMessage: AGUIDiscriminated, Codable, Sendable, Hashable {
        public static let discriminator = "developer"
        public var subagentRunId: String?
        public var id: String
        public var role = AGUIConst<DeveloperMessage>()
        public var name: String?
        public var encryptedValue: String?
        public var metadata: JSONValue?
        public var content: String

        public init(
            id: String, content: String, subagentRunId: String? = nil, name: String? = nil, encryptedValue: String? = nil,
            metadata: JSONValue? = nil
        ) {
            self.subagentRunId = subagentRunId
            self.id = id
            self.name = name
            self.encryptedValue = encryptedValue
            self.metadata = metadata
            self.content = content
        }
    }

    /// AG-UI `SystemMessage`.
    public struct SystemMessage: AGUIDiscriminated, Codable, Sendable, Hashable {
        public static let discriminator = "system"
        public var subagentRunId: String?
        public var id: String
        public var role = AGUIConst<SystemMessage>()
        public var name: String?
        public var encryptedValue: String?
        public var metadata: JSONValue?
        public var content: String

        public init(
            id: String, content: String, subagentRunId: String? = nil, name: String? = nil, encryptedValue: String? = nil,
            metadata: JSONValue? = nil
        ) {
            self.subagentRunId = subagentRunId
            self.id = id
            self.name = name
            self.encryptedValue = encryptedValue
            self.metadata = metadata
            self.content = content
        }
    }

    /// AG-UI `AssistantMessage`.
    public struct AssistantMessage: AGUIDiscriminated, Codable, Sendable, Hashable {
        public static let discriminator = "assistant"
        public var subagentRunId: String?
        public var id: String
        public var role = AGUIConst<AssistantMessage>()
        public var name: String?
        public var encryptedValue: String?
        public var metadata: JSONValue?
        public var content: String?
        public var toolCalls: [ToolCall]?

        public init(
            id: String, subagentRunId: String? = nil, name: String? = nil, encryptedValue: String? = nil, content: String? = nil,
            toolCalls: [ToolCall]? = nil, metadata: JSONValue? = nil
        ) {
            self.subagentRunId = subagentRunId
            self.id = id
            self.name = name
            self.encryptedValue = encryptedValue
            self.metadata = metadata
            self.content = content
            self.toolCalls = toolCalls
        }
    }

    /// AG-UI `UserMessage`.
    public struct UserMessage: AGUIDiscriminated, Codable, Sendable, Hashable {
        public static let discriminator = "user"
        public var subagentRunId: String?
        public var id: String
        public var role = AGUIConst<UserMessage>()
        public var name: String?
        public var encryptedValue: String?
        public var metadata: JSONValue?
        public var content: MessageContent

        public init(
            id: String, content: MessageContent, subagentRunId: String? = nil, name: String? = nil, encryptedValue: String? = nil,
            metadata: JSONValue? = nil
        ) {
            self.subagentRunId = subagentRunId
            self.id = id
            self.name = name
            self.encryptedValue = encryptedValue
            self.metadata = metadata
            self.content = content
        }
    }

    /// AG-UI `ToolMessage`.
    public struct ToolMessage: AGUIDiscriminated, Codable, Sendable, Hashable {
        public static let discriminator = "tool"
        public var subagentRunId: String?
        public var id: String
        public var role = AGUIConst<ToolMessage>()
        public var content: MessageContent
        public var toolCallId: String
        public var error: String?
        public var encryptedValue: String?
        public var metadata: JSONValue?

        public init(
            id: String, content: MessageContent, toolCallId: String, subagentRunId: String? = nil, error: String? = nil,
            encryptedValue: String? = nil, metadata: JSONValue? = nil
        ) {
            self.subagentRunId = subagentRunId
            self.id = id
            self.content = content
            self.toolCallId = toolCallId
            self.error = error
            self.encryptedValue = encryptedValue
            self.metadata = metadata
        }
    }

    /// AG-UI `ActivityMessage`.
    public struct ActivityMessage: AGUIDiscriminated, Codable, Sendable, Hashable {
        public static let discriminator = "activity"
        public var subagentRunId: String?
        public var id: String
        public var role = AGUIConst<ActivityMessage>()
        public var activityType: String
        public var content: JSONValue
        public var metadata: JSONValue?

        public init(id: String, activityType: String, content: JSONValue, subagentRunId: String? = nil, metadata: JSONValue? = nil) {
            self.subagentRunId = subagentRunId
            self.id = id
            self.activityType = activityType
            self.content = content
            self.metadata = metadata
        }
    }

    /// AG-UI `ReasoningMessage`.
    public struct ReasoningMessage: AGUIDiscriminated, Codable, Sendable, Hashable {
        public static let discriminator = "reasoning"
        public var subagentRunId: String?
        public var id: String
        public var role = AGUIConst<ReasoningMessage>()
        public var content: String
        public var encryptedValue: String?
        public var metadata: JSONValue?

        public init(id: String, content: String, subagentRunId: String? = nil, encryptedValue: String? = nil, metadata: JSONValue? = nil) {
            self.subagentRunId = subagentRunId
            self.id = id
            self.content = content
            self.encryptedValue = encryptedValue
            self.metadata = metadata
        }
    }

    /// AG-UI `ToolCall`.
    public struct ToolCall: AGUIDiscriminated, Codable, Sendable, Hashable {
        public static let discriminator = "function"
        public var id: String
        public var type = AGUIConst<ToolCall>()
        public var function: FunctionCall
        public var encryptedValue: String?
        public var metadata: JSONValue?

        public init(id: String, function: FunctionCall, encryptedValue: String? = nil, metadata: JSONValue? = nil) {
            self.id = id
            self.function = function
            self.encryptedValue = encryptedValue
            self.metadata = metadata
        }
    }

    /// AG-UI `FunctionCall`.
    public struct FunctionCall: Codable, Sendable, Hashable {
        public var name: String
        public var arguments: String

        public init(name: String, arguments: String) {
            self.name = name
            self.arguments = arguments
        }
    }

    /// AG-UI `TextPart`.
    public struct TextPart: AGUIDiscriminated, Codable, Sendable, Hashable {
        public static let discriminator = "text"
        public var type = AGUIConst<TextPart>()
        public var id: String?
        public var text: String
        public var metadata: JSONValue?

        public init(text: String, id: String? = nil, metadata: JSONValue? = nil) {
            self.id = id
            self.text = text
            self.metadata = metadata
        }
    }

    /// AG-UI `ImagePart`.
    public struct ImagePart: AGUIDiscriminated, Codable, Sendable, Hashable {
        public static let discriminator = "image"
        public var type = AGUIConst<ImagePart>()
        public var id: String?
        public var source: InputContentSource
        public var metadata: JSONValue?

        public init(source: InputContentSource, id: String? = nil, metadata: JSONValue? = nil) {
            self.id = id
            self.source = source
            self.metadata = metadata
        }
    }

    /// AG-UI `AudioPart`.
    public struct AudioPart: AGUIDiscriminated, Codable, Sendable, Hashable {
        public static let discriminator = "audio"
        public var type = AGUIConst<AudioPart>()
        public var id: String?
        public var source: InputContentSource
        public var metadata: JSONValue?

        public init(source: InputContentSource, id: String? = nil, metadata: JSONValue? = nil) {
            self.id = id
            self.source = source
            self.metadata = metadata
        }
    }

    /// AG-UI `VideoPart`.
    public struct VideoPart: AGUIDiscriminated, Codable, Sendable, Hashable {
        public static let discriminator = "video"
        public var type = AGUIConst<VideoPart>()
        public var id: String?
        public var source: InputContentSource
        public var metadata: JSONValue?

        public init(source: InputContentSource, id: String? = nil, metadata: JSONValue? = nil) {
            self.id = id
            self.source = source
            self.metadata = metadata
        }
    }

    /// AG-UI `DocumentPart`.
    public struct DocumentPart: AGUIDiscriminated, Codable, Sendable, Hashable {
        public static let discriminator = "document"
        public var type = AGUIConst<DocumentPart>()
        public var id: String?
        public var source: InputContentSource
        public var metadata: JSONValue?

        public init(source: InputContentSource, id: String? = nil, metadata: JSONValue? = nil) {
            self.id = id
            self.source = source
            self.metadata = metadata
        }
    }

    /// AG-UI `DataSource`.
    public struct DataSource: AGUIDiscriminated, Codable, Sendable, Hashable {
        public static let discriminator = "data"
        public var type = AGUIConst<DataSource>()
        public var value: String
        public var mimeType: String

        public init(value: String, mimeType: String) {
            self.value = value
            self.mimeType = mimeType
        }
    }

    /// AG-UI `UrlSource`.
    public struct UrlSource: AGUIDiscriminated, Codable, Sendable, Hashable {
        public static let discriminator = "url"
        public var type = AGUIConst<UrlSource>()
        public var value: String
        public var mimeType: String?

        public init(value: String, mimeType: String? = nil) {
            self.value = value
            self.mimeType = mimeType
        }
    }

    /// AG-UI `FileSource`.
    public struct FileSource: AGUIDiscriminated, Codable, Sendable, Hashable {
        public static let discriminator = "file"
        public var type = AGUIConst<FileSource>()
        public var value: String
        public var provider: String?
        public var mimeType: String?

        public init(value: String, provider: String? = nil, mimeType: String? = nil) {
            self.value = value
            self.provider = provider
            self.mimeType = mimeType
        }
    }
}
// jscpd:ignore-end
