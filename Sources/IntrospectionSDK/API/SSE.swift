import Foundation

/// One Server-Sent Events frame.
public struct SSEFrame: Sendable, Equatable {
    /// The `event:` field; `"message"` when absent.
    public var event: String
    /// The `data:` lines joined with newlines.
    public var data: String
    public var id: String?
    public var retry: Int?

    public init(event: String = "message", data: String = "", id: String? = nil, retry: Int? = nil) {
        self.event = event
        self.data = data
        self.id = id
        self.retry = retry
    }
}

/// Incremental SSE parser. Feed it bytes as they arrive; it returns each
/// frame once its terminating blank line has been read. A partial frame left
/// at end of stream is discarded, as the SSE specification requires.
public struct SSEParser: Sendable {
    private var buffer = Data()
    private var event = "message"
    private var dataLines: [String] = []
    private var id: String?
    private var retry: Int?
    private var hasField = false

    public init() {}

    public mutating func push(_ chunk: Data) -> [SSEFrame] {
        buffer.append(chunk)
        var frames: [SSEFrame] = []
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            var lineData = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if lineData.last == UInt8(ascii: "\r") { lineData = lineData.dropLast() }
            let line = String(decoding: lineData, as: UTF8.self)
            if line.isEmpty {
                if let frame = flush() { frames.append(frame) }
                continue
            }
            if line.hasPrefix(":") { continue }
            let field: Substring
            var value: Substring
            if let colon = line.firstIndex(of: ":") {
                field = line[..<colon]
                value = line[line.index(after: colon)...]
                if value.hasPrefix(" ") { value = value.dropFirst() }
            } else {
                field = Substring(line)
                value = ""
            }
            switch field {
            case "event": event = String(value); hasField = true
            case "data": dataLines.append(String(value)); hasField = true
            case "id": id = String(value); hasField = true
            case "retry": retry = Int(value); hasField = true
            default: break
            }
        }
        return frames
    }

    private mutating func flush() -> SSEFrame? {
        defer {
            event = "message"
            dataLines = []
            id = nil
            retry = nil
            hasField = false
        }
        guard hasField else { return nil }
        return SSEFrame(event: event, data: dataLines.joined(separator: "\n"), id: id, retry: retry)
    }
}

extension HTTPStreamResponse {
    /// The body parsed as Server-Sent Events frames.
    public var frames: AsyncThrowingStream<SSEFrame, any Error> {
        let bytes = self.bytes
        return AsyncThrowingStream { continuation in
            let task = Task {
                var parser = SSEParser()
                do {
                    for try await chunk in bytes {
                        for frame in parser.push(chunk) { continuation.yield(frame) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
