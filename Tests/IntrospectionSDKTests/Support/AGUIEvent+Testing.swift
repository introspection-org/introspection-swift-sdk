@testable import IntrospectionSDK

extension AGUIEvent {
    /// The text a `TEXT_MESSAGE_CONTENT` or `TEXT_MESSAGE_CHUNK` event adds.
    var textDelta: String? {
        switch payload {
        case let .textMessageContent(content): content.delta
        case let .textMessageChunk(chunk): chunk.delta
        default: nil
        }
    }

    /// A `CUSTOM` event's value.
    var customValue: JSONValue? {
        guard case let .custom(custom) = payload else { return nil }
        return custom.value
    }
}
