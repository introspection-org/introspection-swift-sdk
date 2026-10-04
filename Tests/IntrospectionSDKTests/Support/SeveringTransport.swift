import Foundation
import Synchronization

@testable import IntrospectionSDK

/// Passes every request to `base`, and fails the body of the first run stream it
/// opens once that stream has delivered `severAfter` text deltas, the way a dropped
/// connection does. The attach after the sever waits `reconnectDelay` before it
/// reaches the network, so the run keeps producing output while no client is attached.
/// Records every complete `ag_ui` frame each attach delivered.
final class SeveringTransport: HTTPTransport, Sendable {
    struct Frame: Sendable {
        /// 1 for the first attach, 2 for the reconnect after it, and so on.
        let attach: Int
        let id: String?
        let event: AGUIEvent
    }

    private struct State {
        var attaches = 0
        var severed = false
        var frames: [Frame] = []
    }

    private let base: any HTTPTransport
    private let severAfter: Int
    private let reconnectDelay: Duration
    private let state = Mutex(State())

    init(_ base: any HTTPTransport, severAfter: Int, reconnectDelay: Duration = .zero) {
        self.base = base
        self.severAfter = severAfter
        self.reconnectDelay = reconnectDelay
    }

    var frames: [Frame] { state.withLock { $0.frames } }
    var attaches: Int { state.withLock { $0.attaches } }
    var severed: Bool { state.withLock { $0.severed } }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        try await base.send(request)
    }

    func stream(_ request: HTTPRequest) async throws -> HTTPStreamResponse {
        guard request.url.path.hasSuffix("/stream") else { return try await base.stream(request) }
        let (attach, firstReconnect) = state.withLock { state in
            state.attaches += 1
            return (state.attaches, state.severed && state.attaches == 2)
        }
        if firstReconnect, reconnectDelay > .zero { try await Task.sleep(for: reconnectDelay) }
        let response = try await base.stream(request)
        let (bytes, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
        let pump = Task { [self] in
            var parser = SSEParser()
            var deltas = 0
            do {
                for try await chunk in response.bytes {
                    let frames = parser.push(chunk).compactMap { frame -> Frame? in
                        guard frame.event == "ag_ui",
                            let event = try? JSONCoding.decoder.decode(AGUIEvent.self, from: Data(frame.data.utf8))
                        else { return nil }
                        return Frame(attach: attach, id: frame.id, event: event)
                    }
                    deltas += frames.filter { $0.event.eventType == .textMessageContent }.count
                    state.withLock { $0.frames.append(contentsOf: frames) }
                    continuation.yield(chunk)
                    if attach == 1, deltas >= severAfter {
                        state.withLock { $0.severed = true }
                        continuation.finish(throwing: IntrospectionError(kind: .network, message: "Connection severed by the test"))
                        return
                    }
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in pump.cancel() }
        return HTTPStreamResponse(status: response.status, headers: response.headers, bytes: bytes)
    }
}
