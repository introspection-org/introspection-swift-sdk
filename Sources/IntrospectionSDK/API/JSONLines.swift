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

/// A JSON-lines response read on demand. Iterate it with `for try await`: the request is sent when the first
/// row is asked for, each row is decoded only when it is asked for, and the next chunk of the body is read
/// only once the rows of the last one are consumed. Stopping the loop, or cancelling its task, ends the read.
public struct JSONLinesSequence<Element: Decodable & Sendable>: AsyncSequence, Sendable {
    private let open: @Sendable () async throws -> HTTPStreamResponse
    private let decode: @Sendable (Data, HTTPStreamResponse) throws -> Element

    init(
        open: @escaping @Sendable () async throws -> HTTPStreamResponse,
        decode: @escaping @Sendable (Data, HTTPStreamResponse) throws -> Element
    ) {
        self.open = open
        self.decode = decode
    }

    public func makeAsyncIterator() -> Iterator {
        Iterator(open: open, decode: decode)
    }

    public struct Iterator: AsyncIteratorProtocol {
        private let open: @Sendable () async throws -> HTTPStreamResponse
        private let decode: @Sendable (Data, HTTPStreamResponse) throws -> Element
        private var response: HTTPStreamResponse?
        private var bytes: AsyncThrowingStream<Data, any Error>.AsyncIterator?
        private var parser = JSONLinesParser()
        private var lines: [Data] = []
        private var index = 0
        private var ended = false

        init(
            open: @escaping @Sendable () async throws -> HTTPStreamResponse,
            decode: @escaping @Sendable (Data, HTTPStreamResponse) throws -> Element
        ) {
            self.open = open
            self.decode = decode
        }

        public mutating func next() async throws -> Element? {
            try Task.checkCancellation()
            let response = try await opened()
            while index >= lines.count {
                if ended { return nil }
                index = 0
                if let chunk = try await bytes?.next(isolation: #isolation) {
                    lines = parser.push(chunk)
                } else {
                    // A cancelled task ends the byte stream early, which is not the end of the body.
                    try Task.checkCancellation()
                    ended = true
                    // A body cut off inside a line fails on the incomplete JSON when that line is decoded.
                    lines = parser.finish().map { [$0] } ?? []
                }
            }
            defer { index += 1 }
            return try decode(lines[index], response)
        }

        private mutating func opened() async throws -> HTTPStreamResponse {
            if let response { return response }
            let opened = try await open()
            response = opened
            bytes = opened.bytes.makeAsyncIterator()
            return opened
        }
    }
}

extension HTTPClient {
    /// `GET` a JSON-lines export, decoding one `T` per line as the caller asks for it. A non-2xx status and an
    /// undecodable line each fail the iteration.
    func jsonLines<T: Decodable & Sendable>(
        _ path: String, query: Query = Query(), as _: T.Type = T.self, transform: @escaping @Sendable (T) -> T = { $0 }
    ) -> JSONLinesSequence<T> {
        let headers = ["Accept": ConversationExportFormat.jsonl.accept]
        return JSONLinesSequence(
            open: { try await self.stream("GET", path, query: query, headers: headers) },
            decode: { line, response in
                let body = HTTPResponse(status: response.status, headers: response.headers, body: line)
                return try transform(self.decode(T.self, from: body, route: path))
            }
        )
    }
}
