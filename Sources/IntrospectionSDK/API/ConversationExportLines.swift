import Foundation

extension ConversationsAPI {
    /// Export the complete conversation as GenAI spans. The body is JSON lines (`application/x-ndjson`):
    /// one span per line, each line a complete JSON object. The spans are read on demand: each is decoded
    /// when the loop asks for it, so the export is never buffered whole and a slow consumer holds the read
    /// back. It replaces the JSON-envelope export, which was removed.
    public func exportJSONLines(
        _ conversationId: String, _ params: ConversationExportParams = ConversationExportParams()
    ) -> JSONLinesSequence<GenAISpan> {
        http.jsonLines(
            "/v1/conversations/\(pathSegment(conversationId))/export", query: params.query, as: GenAISpan.self,
            transform: { $0.normalizingLegacyToolResults() }
        )
    }
}
