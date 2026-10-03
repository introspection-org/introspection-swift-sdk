import Foundation
import XCTest

@testable import IntrospectionSDK

final class RunStreamTests: XCTestCase {
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

    func collect(_ stream: AsyncThrowingStream<AGUIEvent, Error>) async throws -> [AGUIEvent] {
        var events: [AGUIEvent] = []
        for try await event in stream { events.append(event) }
        return events
    }

    func testParsesAGUIFramesAndSkipsHeartbeats() async throws {
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
        XCTAssertEqual(events.map(\.type), ["RUN_STARTED", "CUSTOM", "RUN_FINISHED"])
        XCTAssertEqual(events[0].runId, "r1")
        XCTAssertTrue(events[1].isResumeGap)
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.last?.path, "/v1/tasks/t1/runs/current/stream")
        XCTAssertNil(transport.last?.request.headers["Last-Event-ID"])
        XCTAssertNil(transport.last?.query["wait_for_start"])
    }

    func testReconnectsWithLastNumericEventIdAfterSever() async throws {
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
        XCTAssertEqual(events.compactMap(\.delta), ["a", "b", "c"])
        let marker = try XCTUnwrap(events.first(where: \.isReconnectMarker))
        XCTAssertEqual(marker.value?["reason"], "severed")
        XCTAssertEqual(marker.value?["attempt"], 0)
        XCTAssertEqual(marker.value?["lastEventId"], "2")
        XCTAssertEqual(events.last?.eventType, .runFinished)
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(transport.requests[1].request.headers["Last-Event-ID"], "2")
        XCTAssertEqual(transport.requests[1].query["wait_for_start"], ["false"])
    }

    func testReadinessWaitsHonourRetryAfterAndDoNotSpendReconnectBudget() async throws {
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
        XCTAssertEqual(markers.count, 4)
        XCTAssertEqual(markers.map { $0.value?["attempt"]?.intValue }, [1, 2, 3, 4])
        XCTAssertEqual(markers[0].value?["reason"], "readiness")
        XCTAssertEqual(markers[0].value?["phase"], "provisioning")
        XCTAssertEqual(markers[0].value?["retryAfterMs"], 0)
        XCTAssertEqual(events.compactMap(\.delta), ["hi"])
        XCTAssertEqual(transport.requests.count, 5)
    }

    func testReadinessIsBoundedByTimeout() async {
        let transport = MockTransport { _, _ in
            .response(.json(#"{"status":"queued"}"#, status: 429, headers: ["retry-after": "0"]))
        }
        let client = makeClient(transport)
        let options = RunStreamOptions(backoff: 0.001, timeout: 0.05)
        do {
            _ = try await collect(client.tasks.runs.stream("t1", "r1", options: options))
            XCTFail("expected the deadline to end the readiness wait")
        } catch let error as IntrospectionError {
            XCTAssertEqual(error.kind, .rateLimited)
            XCTAssertGreaterThan(transport.requests.count, 1)
        } catch { XCTFail("\(error)") }
    }

    func testReconnectBudgetExhaustionThrows() async {
        let transport = MockTransport { _, _ in
            .stream(status: 200, headers: [:], chunks: [RunStreamTests.frame(nil, "heartbeat", "{}")], error: Severed())
        }
        let client = makeClient(transport)
        let options = RunStreamOptions(maxReconnects: 2, backoff: 0.001)
        do {
            _ = try await collect(client.tasks.runs.stream("t1", "r1", options: options))
            XCTFail("expected exhaustion")
        } catch is Severed {
            // Initial attach plus two reconnects, none of which made progress.
            XCTAssertEqual(transport.requests.count, 3)
        } catch { XCTFail("\(error)") }
    }

    func testProgressResetsReconnectBudget() async throws {
        let transport = MockTransport { _, index in
            if index < 4 {
                return .stream(status: 200, headers: [:], chunks: [RunStreamTests.content("\(index + 1)", "x")], error: Severed())
            }
            return .stream(status: 200, headers: [:], chunks: [RunStreamTests.finished], error: nil)
        }
        let client = makeClient(transport)
        let options = RunStreamOptions(maxReconnects: 1, backoff: 0.001)
        let events = try await collect(client.tasks.runs.stream("t1", "r1", options: options))
        XCTAssertEqual(events.count, 5)
        XCTAssertEqual(transport.requests.map { $0.request.headers["Last-Event-ID"] }, [nil, "1", "2", "3", "4"])
    }

    func testConnectErrorsCountAndNotFoundFailsFast() async {
        let transport = MockTransport { _, _ in .response(.json(#"{"detail":"Task not found"}"#, status: 404)) }
        let client = makeClient(transport)
        do {
            _ = try await collect(client.tasks.runs.stream("t1", "r1", options: Self.fast))
            XCTFail("expected not found")
        } catch let error as IntrospectionError {
            XCTAssertEqual(error.kind, .notFound)
            XCTAssertEqual(transport.requests.count, 1)
        } catch { XCTFail("\(error)") }

        let flaky = MockTransport { _, index in
            index < 2
                ? .response(.json(#"{"detail":"down"}"#, status: 503))
                : .stream(status: 200, headers: [:], chunks: [RunStreamTests.finished], error: nil)
        }
        let events = try? await collect(makeClient(flaky).tasks.runs.stream("t1", "r1", options: Self.fast))
        XCTAssertEqual(events?.count, 1)
        XCTAssertEqual(flaky.requests.count, 3)
    }

    func testInvalidFrameIsADecodingErrorNotAReconnect() async {
        let transport = MockTransport { _, _ in
            .stream(status: 200, headers: [:], chunks: [RunStreamTests.frame("1", "ag_ui", "{not json")], error: nil)
        }
        do {
            _ = try await collect(makeClient(transport).tasks.runs.stream("t1", "r1", options: Self.fast))
            XCTFail("expected decoding error")
        } catch let error as IntrospectionError {
            XCTAssertEqual(error.kind, .decoding)
            XCTAssertEqual(transport.requests.count, 1)
        } catch { XCTFail("\(error)") }
    }

    func testCancellingTheConsumerCancelsTheRequest() async throws {
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
        XCTAssertEqual(transport.attaches, 1)
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
        let bytes = AsyncThrowingStream<Data, Error> { continuation in
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
        XCTAssertTrue(lock.withLock { _terminated }, "the underlying byte stream was not cancelled")
    }
}
