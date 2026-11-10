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

extension HTTPClient {
    /// `GET` a JSON-lines export and decode one `T` per line as the body arrives. `query` runs once,
    /// before the request; its error, a non-2xx status and an undecodable line each fail the stream.
    func jsonLines<T: Decodable & Sendable>(
        _ path: String, as _: T.Type = T.self, transform: @escaping @Sendable (T) -> T = { $0 },
        query: @escaping @Sendable () async throws -> Query
    ) -> AsyncThrowingStream<T, any Error> {
        let headers = ["Accept": ConversationExportFormat.jsonl.accept]
        return AsyncThrowingStream { continuation in
            let worker = Task {
                do {
                    let response = try await self.stream("GET", path, query: try await query(), headers: headers)
                    var parser = JSONLinesParser()
                    for try await chunk in response.bytes {
                        for line in parser.push(chunk) {
                            continuation.yield(try transform(self.decodeLine(T.self, line, of: response, route: path)))
                        }
                    }
                    // A body cut off inside a line fails here, on the incomplete JSON.
                    if let line = parser.finish() {
                        continuation.yield(try transform(self.decodeLine(T.self, line, of: response, route: path)))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in worker.cancel() }
        }
    }

    private func decodeLine<T: Decodable>(_: T.Type, _ line: Data, of response: HTTPStreamResponse, route: String) throws -> T {
        try decode(T.self, from: HTTPResponse(status: response.status, headers: response.headers, body: line), route: route)
    }
}
