import Foundation

extension AGUI {
    /// AG-UI `TextMessageRole`.
    public enum TextMessageRole: String, Codable, Sendable, Hashable, CaseIterable {
        case developer, system, assistant, user
    }

    /// AG-UI `ReasoningEncryptedValueSubtype`.
    public enum ReasoningEncryptedValueSubtype: String, Codable, Sendable, Hashable, CaseIterable {
        case toolCall = "tool-call"
        case message
    }

    /// AG-UI `ResumeEntry.status`.
    public enum ResumeStatus: String, Codable, Sendable, Hashable, CaseIterable {
        case resolved, cancelled
    }

    /// AG-UI `Message`, tagged by `role`.
    public enum Message: Codable, Sendable, Hashable {
        // jscpd:ignore-start: the union catalogue, one member per case.
        case developer(DeveloperMessage)
        case system(SystemMessage)
        case assistant(AssistantMessage)
        case user(UserMessage)
        case tool(ToolMessage)
        case activity(ActivityMessage)
        case reasoning(ReasoningMessage)

        static let decoders: [String: TaggedDecoder<Message>] = taggedDecoders([
            tagged(DeveloperMessage.self) { .developer($0) },
            tagged(SystemMessage.self) { .system($0) },
            tagged(AssistantMessage.self) { .assistant($0) },
            tagged(UserMessage.self) { .user($0) },
            tagged(ToolMessage.self) { .tool($0) },
            tagged(ActivityMessage.self) { .activity($0) },
            tagged(ReasoningMessage.self) { .reasoning($0) },
        ])
        // jscpd:ignore-end

        public init(from decoder: any Decoder) throws { self = try decodeTagged(decoder, key: "role", Self.decoders) }

        public func encode(to encoder: any Encoder) throws { try encodeMember(of: self, to: encoder) }
    }

    /// AG-UI `InputContent`, tagged by `type`.
    public enum InputContent: Codable, Sendable, Hashable {
        // jscpd:ignore-start: the union catalogue, one member per case.
        case text(TextPart)
        case image(ImagePart)
        case audio(AudioPart)
        case video(VideoPart)
        case document(DocumentPart)

        static let decoders: [String: TaggedDecoder<InputContent>] = taggedDecoders([
            tagged(TextPart.self) { .text($0) },
            tagged(ImagePart.self) { .image($0) },
            tagged(AudioPart.self) { .audio($0) },
            tagged(VideoPart.self) { .video($0) },
            tagged(DocumentPart.self) { .document($0) },
        ])
        // jscpd:ignore-end

        public init(from decoder: any Decoder) throws { self = try decodeTagged(decoder, key: "type", Self.decoders) }

        public func encode(to encoder: any Encoder) throws { try encodeMember(of: self, to: encoder) }
    }

    /// AG-UI `InputContentSource`, tagged by `type`.
    public enum InputContentSource: Codable, Sendable, Hashable {
        // jscpd:ignore-start: the union catalogue, one member per case.
        case data(DataSource)
        case url(UrlSource)
        case file(FileSource)

        static let decoders: [String: TaggedDecoder<InputContentSource>] = taggedDecoders([
            tagged(DataSource.self) { .data($0) },
            tagged(UrlSource.self) { .url($0) },
            tagged(FileSource.self) { .file($0) },
        ])
        // jscpd:ignore-end

        public init(from decoder: any Decoder) throws { self = try decodeTagged(decoder, key: "type", Self.decoders) }

        public func encode(to encoder: any Encoder) throws { try encodeMember(of: self, to: encoder) }
    }

    /// A user or tool message's `content`: a string, or a list of content parts.
    public enum MessageContent: Codable, Sendable, Hashable {
        case text(String)
        case parts([InputContent])

        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                self = .text(text)
            } else {
                self = .parts(try container.decode([InputContent].self))
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case let .text(text): try container.encode(text)
            case let .parts(parts): try container.encode(parts)
            }
        }
    }

    /// AG-UI `RunFinishedOutcome`, tagged by `type`.
    public enum RunFinishedOutcome: Codable, Sendable, Hashable {
        // jscpd:ignore-start: the union catalogue, one member per case.
        case success(RunFinishedSuccessOutcome)
        case interrupt(RunFinishedInterruptOutcome)
        case cancelled(RunFinishedCancelledOutcome)

        static let decoders: [String: TaggedDecoder<RunFinishedOutcome>] = taggedDecoders([
            tagged(RunFinishedSuccessOutcome.self) { .success($0) },
            tagged(RunFinishedInterruptOutcome.self) { .interrupt($0) },
            tagged(RunFinishedCancelledOutcome.self) { .cancelled($0) },
        ])
        // jscpd:ignore-end

        public init(from decoder: any Decoder) throws { self = try decodeTagged(decoder, key: "type", Self.decoders) }

        public func encode(to encoder: any Encoder) throws { try encodeMember(of: self, to: encoder) }
    }

    /// AG-UI `SubagentFinishedOutcome`, tagged by `type`.
    public enum SubagentFinishedOutcome: Codable, Sendable, Hashable {
        // jscpd:ignore-start: the union catalogue, one member per case.
        case success(SubagentFinishedSuccessOutcome)
        case suspended(SubagentFinishedSuspendedOutcome)

        static let decoders: [String: TaggedDecoder<SubagentFinishedOutcome>] = taggedDecoders([
            tagged(SubagentFinishedSuccessOutcome.self) { .success($0) },
            tagged(SubagentFinishedSuspendedOutcome.self) { .suspended($0) },
        ])
        // jscpd:ignore-end

        public init(from decoder: any Decoder) throws { self = try decodeTagged(decoder, key: "type", Self.decoders) }

        public func encode(to encoder: any Encoder) throws { try encodeMember(of: self, to: encoder) }
    }

    /// AG-UI `JsonPatchOperation` (RFC 6902), tagged by `op`.
    public enum JsonPatchOperation: Codable, Sendable, Hashable {
        // jscpd:ignore-start: the union catalogue, one member per case.
        case add(AddOperation)
        case remove(RemoveOperation)
        case replace(ReplaceOperation)
        case move(MoveOperation)
        case copy(CopyOperation)
        case test(TestOperation)

        static let decoders: [String: TaggedDecoder<JsonPatchOperation>] = taggedDecoders([
            tagged(AddOperation.self) { .add($0) },
            tagged(RemoveOperation.self) { .remove($0) },
            tagged(ReplaceOperation.self) { .replace($0) },
            tagged(MoveOperation.self) { .move($0) },
            tagged(CopyOperation.self) { .copy($0) },
            tagged(TestOperation.self) { .test($0) },
        ])
        // jscpd:ignore-end

        public init(from decoder: any Decoder) throws { self = try decodeTagged(decoder, key: "op", Self.decoders) }

        public func encode(to encoder: any Encoder) throws { try encodeMember(of: self, to: encoder) }
    }
}
