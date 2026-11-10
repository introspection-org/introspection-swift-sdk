import Foundation

extension ConversationsAPI {
    /// Export the complete conversation as GenAI spans. The body is JSON lines (`application/x-ndjson`):
    /// one span per line, each line a complete JSON object, decoded and yielded as it arrives, so the
    /// export is never buffered whole. It replaces the JSON-envelope export, which was removed.
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
