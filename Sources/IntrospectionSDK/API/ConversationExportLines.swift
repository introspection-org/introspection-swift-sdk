import Foundation

/// Incremental JSON-lines splitter. Feed it bytes as they arrive; it returns each line once its
/// newline has been read, skipping blank ones.
struct JSONLinesParser: Sendable {
    private var buffer = Data()

    mutating func push(_ chunk: Data) -> [Data] {
        buffer.append(chunk)
        var lines: [Data] = []
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = Data(buffer[buffer.startIndex..<newline])
            buffer.removeSubrange(buffer.startIndex...newline)
            if !Self.isBlank(line) { lines.append(line) }
        }
        return lines
    }

    /// The bytes after the last newline, at end of stream; nil when there are none.
    mutating func finish() -> Data? {
        let rest = buffer
        buffer = Data()
        return Self.isBlank(rest) ? nil : rest
    }

    private static func isBlank(_ line: Data) -> Bool {
        line.allSatisfy { $0 == UInt8(ascii: " ") || $0 == UInt8(ascii: "\t") || $0 == UInt8(ascii: "\r") }
    }
}

extension ConversationsAPI {
    /// Export the complete conversation as GenAI spans, decoded one JSON line at a time as the body arrives.
    /// A data plane that predates the JSON-lines form fails the stream with a 406.
    public func exportJSONLines(
        _ conversationId: String, _ params: ConversationExportParams = ConversationExportParams()
    ) -> AsyncThrowingStream<GenAISpan, any Error> {
        let route = "/v1/conversations/\(pathSegment(conversationId))/export"
        return AsyncThrowingStream { continuation in
            let worker = Task {
                do {
                    let response = try await http.stream(
                        "GET", route, query: params.query, headers: ["Accept": ConversationExportFormat.jsonl.accept])
                    var parser = JSONLinesParser()
                    for try await chunk in response.bytes {
                        for line in parser.push(chunk) {
                            continuation.yield(try exportedSpan(line, of: response, route: route))
                        }
                    }
                    // A body cut off inside a line fails here, on the incomplete JSON.
                    if let line = parser.finish() {
                        continuation.yield(try exportedSpan(line, of: response, route: route))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in worker.cancel() }
        }
    }

    private func exportedSpan(_ line: Data, of response: HTTPStreamResponse, route: String) throws -> GenAISpan {
        let span = try http.decode(
            GenAISpan.self, from: HTTPResponse(status: response.status, headers: response.headers, body: line), route: route)
        return span.normalizingLegacyToolResults()
    }
}
