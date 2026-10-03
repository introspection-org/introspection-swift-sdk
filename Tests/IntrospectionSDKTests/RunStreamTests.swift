import Foundation
import Testing

@testable import IntrospectionSDK

@Suite struct RunStreamTests {
    struct Severed: Error {}

    static func frame(_ id: String?, _ event: String = "ag_ui", _ data: String) -> Data {
        var text = "event: \(event)\n"
        if let id { text += "id: \(id)\n" }
        text += "data: \(data)\n\n"
        return Data(text.utf8)
    }

    static func content(_ id: String, _ delta: String) -> Data {
        frame(id, "ag_ui", #"{"type":"TEXT_MESSAGE_CONTENT","messageId":"m1","delta":"\#(delta)"}"#)
    }

    static let finished = frame("c-9", "ag_ui", #"{"type":"RUN_FINISHED","threadId":"t1","runId":"r1"}"#)
    static let fast = RunStreamOptions(backoff: 0.001)

    func collect(_ stream: AsyncThrowingStream<AGUIEvent, any Error>) async throws -> [AGUIEvent] {
        var events: [AGUIEvent] = []
        for try await event in stream { events.append(event) }
        return events
    }

    @Test func parsesAGUIFramesAndSkipsHeartbeats() async throws {
        let transport = MockTransport { _, _ in
            .stream(
                status: 200, headers: [:],
                chunks: [
                    Data(": keep-alive comment\n\n".utf8),
                    RunStreamTests.frame(nil, "heartbeat", #"{"runId":"r1"}"#),
                    // A frame split across chunks.
                    Data("event: ag_ui\nid: 1\ndata: {\"type\":\"RUN_STA".utf8),
                    Data("RTED\",\"threadId\":\"t1\",\"runId\":\"r1\"}\r\n\r\n".utf8),
                    RunStreamTests.frame("2", "ag_ui", #"{"type":"CUSTOM","name":"resume_gap","value":{}}"#),
                    RunStreamTests.finished,
                ], error: nil)
        }
        let client = makeClient(transport)
        let events = try await collect(client.tasks.runs.stream("t1", "current", options: Self.fast))
        #expect(events.map(\.type) == ["RUN_STARTED", "CUSTOM", "RUN_FINISHED"])
        #expect(events[0].runId == "r1")
        #expect(events[1].isResumeGap)
        #expect(transport.requests.count == 1)
        #expect(transport.last?.path == "/v1/tasks/t1/runs/current/stream")
        #expect(transport.last?.request.headers["Last-Event-ID"] == "0")
        #expect(transport.last?.query["wait_for_start"] == nil)
    }

    @Test func reconnectsWithLastNumericEventIdAfterSever() async throws {
        let transport = MockTransport { _, index in
            switch index {
            case 0:
                return .stream(
                    status: 200, headers: [:],
                    chunks: [
                        RunStreamTests.content("1", "a"),
                        RunStreamTests.content("2", "b"),
                        // Control-frame ids are not resume cursors.
                        RunStreamTests.frame("c-1", "ag_ui", #"{"type":"STEP_STARTED","stepName":"x"}"#),
                    ], error: Severed())
            default:
                return .stream(
                    status: 200, headers: [:],
                    chunks: [
                        RunStreamTests.content("3", "c"),
                        RunStreamTests.finished,
                    ], error: nil)
            }
        }
        let client = makeClient(transport)
        var options = Self.fast
        options.emitReconnectEvents = true
        options.waitForStart = false
        let events = try await collect(client.tasks.runs.stream("t1", "r1", options: options))
        #expect(events.compactMap(\.delta) == ["a", "b", "c"])
        let marker = try #require(events.first { $0.isReconnectMarker })
        #expect(marker.value?["reason"] == "severed")
        #expect(marker.value?["attempt"] == 0)
        #expect(marker.value?["lastEventId"] == "2")
        #expect(events.last?.eventType == .runFinished)
        #expect(transport.requests.count == 2)
        #expect(transport.requests[1].request.headers["Last-Event-ID"] == "2")
        #expect(transport.requests[1].query["wait_for_start"] == ["false"])
    }

    @Test func readinessWaitsHonourRetryAfterAndDoNotSpendReconnectBudget() async throws {
        let transport = MockTransport { _, index in
            if index < 4 {
                return .response(.json(#"{"status":"provisioning","detail":"not ready"}"#, status: 429, headers: ["retry-after": "0"]))
            }
            return .stream(status: 200, headers: [:], chunks: [RunStreamTests.content("1", "hi"), RunStreamTests.finished], error: nil)
        }
        let client = makeClient(transport)
        let options = RunStreamOptions(maxReconnects: 0, backoff: 0.001, emitReconnectEvents: true)
        let events = try await collect(client.tasks.runs.stream("t1", "r1", options: options))
        let markers = events.filter(\.isReconnectMarker)
        #expect(markers.count == 4)
        #expect(markers.map { $0.value?["attempt"]?.intValue } == [1, 2, 3, 4])
        #expect(markers[0].value?["reason"] == "readiness")
        #expect(markers[0].value?["phase"] == "provisioning")
        #expect(markers[0].value?["retryAfterMs"] == 0)
        #expect(events.compactMap(\.delta) == ["hi"])
        #expect(transport.requests.count == 5)
    }

    @Test func readinessIsBoundedByTimeout() async throws {
        let transport = MockTransport { _, _ in
            .response(.json(#"{"status":"queued"}"#, status: 429, headers: ["retry-after": "0"]))
        }
        let client = makeClient(transport)
        let options = RunStreamOptions(backoff: 0.001, timeout: 0.05)
        let error = try await #require(throws: IntrospectionError.self) {
            try await collect(client.tasks.runs.stream("t1", "r1", options: options))
        }
        #expect(error.kind == .rateLimited)
        #expect(transport.requests.count > 1)
    }

    @Test func reconnectBudgetExhaustionThrows() async {
        let transport = MockTransport { _, _ in
            .stream(status: 200, headers: [:], chunks: [RunStreamTests.frame(nil, "heartbeat", "{}")], error: Severed())
        }
        let client = makeClient(transport)
        let options = RunStreamOptions(maxReconnects: 2, backoff: 0.001)
        await #expect(throws: Severed.self) { try await collect(client.tasks.runs.stream("t1", "r1", options: options)) }
        // Initial attach plus two reconnects, none of which made progress.
        #expect(transport.requests.count == 3)
    }

    @Test func progressResetsReconnectBudget() async throws {
        let transport = MockTransport { _, index in
            if index < 4 {
                return .stream(status: 200, headers: [:], chunks: [RunStreamTests.content("\(index + 1)", "x")], error: Severed())
            }
            return .stream(status: 200, headers: [:], chunks: [RunStreamTests.finished], error: nil)
        }
        let client = makeClient(transport)
        let options = RunStreamOptions(maxReconnects: 1, backoff: 0.001)
        let events = try await collect(client.tasks.runs.stream("t1", "r1", options: options))
        #expect(events.count == 5)
        #expect(transport.requests.map { $0.request.headers["Last-Event-ID"] } == ["0", "1", "2", "3", "4"])
    }

    @Test func connectErrorsCountAndNotFoundFailsFast() async throws {
        let transport = MockTransport { _, _ in .response(.json(#"{"detail":"Task not found"}"#, status: 404)) }
        let client = makeClient(transport)
        let error = try await #require(throws: IntrospectionError.self) {
            try await collect(client.tasks.runs.stream("t1", "r1", options: Self.fast))
        }
        #expect(error.kind == .notFound)
        #expect(transport.requests.count == 1)

        let flaky = MockTransport { _, index in
            index < 2
                ? .response(.json(#"{"detail":"down"}"#, status: 503))
                : .stream(status: 200, headers: [:], chunks: [RunStreamTests.finished], error: nil)
        }
        let events = try? await collect(makeClient(flaky).tasks.runs.stream("t1", "r1", options: Self.fast))
        #expect(events?.count == 1)
        #expect(flaky.requests.count == 3)
    }

    @Test func invalidFrameIsADecodingErrorNotAReconnect() async throws {
        let transport = MockTransport { _, _ in
            .stream(status: 200, headers: [:], chunks: [RunStreamTests.frame("1", "ag_ui", "{not json")], error: nil)
        }
        let error = try await #require(throws: IntrospectionError.self) {
            try await collect(makeClient(transport).tasks.runs.stream("t1", "r1", options: Self.fast))
        }
        #expect(error.kind == .decoding)
        #expect(transport.requests.count == 1)
    }

    @Test func cancellingTheConsumerCancelsTheRequest() async throws {
        let transport = HangingTransport()
        let client = IntrospectionClient(
            configuration: .init(
                controlPlaneURL: URL(string: "https://cp.test")!,
                dataPlaneURL: URL(string: "https://dp.test")!,
                controlPlaneCredentials: BearerToken("t"),
                transport: transport
            ))
        let stream = client.tasks.runs.stream("t1", "r1", options: Self.fast)
        let consumer = Task {
            var count = 0
            for try await _ in stream { count += 1 }
            return count
        }
        try await transport.waitUntilFirstChunkSent()
        consumer.cancel()
        _ = try? await consumer.value
        try await transport.waitUntilTerminated()
        #expect(transport.attaches == 1)
    }
}

/// A transport whose stream sends one frame and then never ends on its own.
final class HangingTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _attaches = 0
    private var _sent = false
    private var _terminated = false

    var attaches: Int { lock.withLock { _attaches } }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        HTTPResponse(status: 500, headers: [:], body: Data())
    }

    func stream(_ request: HTTPRequest) async throws -> HTTPStreamResponse {
        lock.withLock { _attaches += 1 }
        let bytes = AsyncThrowingStream<Data, any Error> { continuation in
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { self?._terminated = true }
            }
            continuation.yield(RunStreamTests.content("1", "x"))
            self.lock.withLock { self._sent = true }
        }
        return HTTPStreamResponse(status: 200, headers: [:], bytes: bytes)
    }

    func waitUntilFirstChunkSent() async throws {
        for _ in 0..<500 where !lock.withLock({ _sent }) {
            try await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    func waitUntilTerminated() async throws {
        for _ in 0..<500 where !lock.withLock({ _terminated }) {
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        #expect(lock.withLock { _terminated }, "the underlying byte stream was not cancelled")
    }
}
