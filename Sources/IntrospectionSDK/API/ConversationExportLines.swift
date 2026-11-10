import Foundation

extension ConversationsAPI {
    /// Export the complete conversation as GenAI spans, decoded one JSON line at a time as the body arrives.
    /// A data plane that predates the JSON-lines form fails the stream with a 406.
    public func exportJSONLines(
        _ conversationId: String, _ params: ConversationExportParams = ConversationExportParams()
    ) -> AsyncThrowingStream<GenAISpan, any Error> {
        http.jsonLines(
            "/v1/conversations/\(pathSegment(conversationId))/export", as: GenAISpan.self,
            transform: { $0.normalizingLegacyToolResults() }
        ) { params.query }
    }
}
