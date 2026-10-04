import Foundation
import Testing

@testable import IntrospectionSDK

/// Run stream recovery against a real deployment: the connection is severed
/// mid-run by `SeveringTransport` and the SDK recovers the rest of the answer.
/// Skipped unless `INTROSPECTION_LIVE=1` and `INTROSPECTION_TOKEN` (an API key)
/// are set; `INTROSPECTION_RUNTIME` and `INTROSPECTION_PROJECT` as for
/// `LiveIdentityTests`.
///
/// The past-buffer case also needs `INTROSPECTION_LIVE_SMALL_REPLAY_BUFFER=1`, and
/// is meaningful only when the target data plane shrinks the runtime's replay
/// buffer with `SANDBOX_STREAM_REPLAY_MAX_BYTES` (for example `4096`), so a
/// disconnect of a few seconds outlives it.
@Suite(.enabled(if: Live.isEnabled, "Live tests run only with INTROSPECTION_LIVE=1"))
struct LiveStreamRecoveryTests {
    /// Long enough that the run is still streaming when the connection drops.
    private let prompt = "Write the integers from 1 to 200, one per line, with no other text."
    private let severAfter = 10

    @Test(Live.requires("INTROSPECTION_TOKEN"))
    func reconnectWithinTheReplayBufferResumesWithoutLoss() async throws {
        let transport = SeveringTransport(URLSessionTransport(), severAfter: severAfter)
        let result = try await runSevered(transport)

        #expect(transport.severed, "the run ended before \(severAfter) deltas; the sever never happened")
        #expect(result.events.contains { $0.isReconnectMarker && $0.value?["reason"]?.stringValue == "severed" })
        if !Live.smallReplayBuffer {
            #expect(!result.events.contains { $0.eventType == .messagesSnapshot }, "a reconnect within the buffer is a replay")
        }
        let ids = contentIds(transport.frames)
        #expect(ids == Array(1...UInt64(ids.count)), "content frame ids repeat or skip across the reconnect: \(ids)")
        #expect(result.text == result.stored)
    }

    @Test(Live.requires("INTROSPECTION_TOKEN", "INTROSPECTION_LIVE_SMALL_REPLAY_BUFFER"))
    func reconnectPastTheReplayBufferRecoversFromOneSnapshot() async throws {
        // Long enough for the run to outgrow a small buffer while no client is attached.
        let transport = SeveringTransport(URLSessionTransport(), severAfter: severAfter, reconnectDelay: .seconds(10))
        let result = try await runSevered(transport)

        #expect(transport.severed, "the run ended before \(severAfter) deltas; the sever never happened")
        let snapshots = result.events.filter { $0.eventType == .messagesSnapshot }
        try #require(
            snapshots.count == 1,
            "expected one MESSAGES_SNAPSHOT, got \(snapshots.count); does the plane set SANDBOX_STREAM_REPLAY_MAX_BYTES?")

        let reconnect = transport.frames.filter { $0.attach > 1 && isContent($0) }
        #expect(reconnect.first?.event.eventType == .messagesSnapshot, "the snapshot opens the reconnect")
        let liveIds = reconnect.compactMap { $0.id.flatMap(UInt64.init) }
        if let first = liveIds.first {
            #expect(liveIds == Array(first..<(first + UInt64(liveIds.count))), "frames after the snapshot repeat or skip: \(liveIds)")
        }
        let beforeSever = transport.frames.filter { $0.attach == 1 && $0.event.eventType == .textMessageContent }
            .compactMap(\.event.delta).joined()
        let snapshotText = assistantText([snapshots[0]])
        #expect(snapshotText.hasPrefix(beforeSever))
        #expect(snapshotText.count > beforeSever.count, "the snapshot carries output produced while disconnected")
        #expect(result.text == result.stored)
    }

    // MARK: Helpers

    private struct SeveredRun {
        let events: [AGUIEvent]
        /// The assistant text the SDK reassembled from the stream.
        let text: String
        /// The assistant text of the run's stored conversation.
        let stored: String
    }

    private func runSevered(_ transport: SeveringTransport) async throws -> SeveredRun {
        let client = IntrospectionClient(
            controlPlaneURL: try controlPlaneURL(), credentials: BearerToken(try setting("INTROSPECTION_TOKEN")), transport: transport)
        let project = Live.value("INTROSPECTION_PROJECT")
        let runner = try await client.runtime(try await runtime(client, project: project), project: project).run(
            identity: RunnerIdentity(userId: "swift-sdk-live-\(UUID().uuidString.lowercased())"),
            ttlSeconds: 900
        )
        defer { runner.close() }

        let run = try await runner.tasks.start(
            prompt: prompt, TaskCreate(title: "swift-sdk-live:stream-recovery", tags: ["swift-sdk-live"]))
        var events: [AGUIEvent] = []
        for try await event in run.stream(options: RunStreamOptions(timeout: 600, emitReconnectEvents: true)) {
            events.append(event)
        }
        #expect(events.last?.eventType == .runFinished)
        let text = assistantText(events)
        #expect(!text.isEmpty, "no assistant text")

        let stored = try await storedAnswer(runner, conversationId: run.task?.conversationId ?? run.run.taskId)
        try await runner.tasks.archive(run.run.taskId)
        return SeveredRun(events: events, text: trimmed(text), stored: trimmed(stored))
    }

    /// The answer as the conversation stores it, read once telemetry has caught up.
    private func storedAnswer(_ runner: Runner, conversationId: String) async throws -> String {
        let deadline = Date().addingTimeInterval(180)
        while true {
            if let span = try? await runner.conversations.retrieve(conversationId: conversationId) {
                let text = span.outputMessages.filter { $0.role == .assistant }
                    .flatMap(\.parts)
                    .compactMap { part -> String? in
                        if case let .text(text) = part { return text.content }
                        return nil
                    }
                    .joined()
                if !text.isEmpty { return text }
            }
            if Date() >= deadline { try Test.cancel("The conversation was not stored within 180s") }
            try await Task.sleep(for: .seconds(3))
        }
    }

    private func setting(_ name: String) throws -> String {
        guard let value = Live.value(name) else { try Test.cancel("\(name) is not set") }
        return value
    }

    private func controlPlaneURL() throws -> URL {
        let raw = try Live.value("INTROSPECTION_BASE_API_URL") ?? setting("INTROSPECTION_BASE_URL")
        guard let url = URL(string: raw) else { try Test.cancel("Invalid Control Plane URL: \(raw)") }
        return url
    }

    private func runtime(_ client: IntrospectionClient, project: String?) async throws -> String {
        if let runtime = Live.value("INTROSPECTION_RUNTIME") { return runtime }
        let page = try await client.runtimes.list(RuntimeListParams(project: project, limit: 1)).firstPage()
        guard let first = page.records.first else { try Test.cancel("The project has no runtimes and INTROSPECTION_RUNTIME is not set") }
        return first.id
    }
}

/// The severing transport itself, against a scripted stream, so the live suite is
/// not the first place it runs.
@Suite struct SeveringTransportTests {
    @Test func seversTheFirstAttachAndLetsTheSDKResume() async throws {
        let mock = MockTransport { request, index in
            let cursor = Int(request.headers["Last-Event-ID"] ?? "0") ?? 0
            let ids = index == 0 ? Array(1...6) : Array((cursor + 1)...6)
            var chunks = ids.map { RunStreamTests.content(String($0), "d\($0) ") }
            chunks.append(RunStreamTests.finished)
            return .stream(status: 200, headers: [:], chunks: chunks, error: nil)
        }
        let transport = SeveringTransport(mock, severAfter: 2)
        let client = IntrospectionClient(
            configuration: .init(
                controlPlaneURL: URL(string: "https://cp.test")!, controlPlaneCredentials: BearerToken("t"), transport: transport))
        let options = RunStreamOptions(backoff: 0.001, emitReconnectEvents: true)

        var events: [AGUIEvent] = []
        for try await event in client.tasks.runs.stream("t1", "r1", options: options) { events.append(event) }

        #expect(transport.severed)
        #expect(transport.attaches == 2)
        #expect(mock.requests.last?.request.headers["Last-Event-ID"] == "2")
        #expect(events.contains { $0.isReconnectMarker && $0.value?["reason"]?.stringValue == "severed" })
        #expect(assistantText(events) == "d1 d2 d3 d4 d5 d6 ")
        #expect(contentIds(transport.frames) == Array(1...6))
    }
}

/// Assistant text as `RunHandle.text` assembles it: a snapshot replaces what was read.
private func assistantText(_ events: [AGUIEvent]) -> String {
    var text = ""
    for event in events {
        switch event.eventType {
        case .messagesSnapshot:
            text = (event.raw["messages"]?.arrayValue ?? [])
                .filter { $0["role"]?.stringValue == "assistant" }
                .compactMap { $0["content"]?.stringValue }
                .joined()
        case .textMessageContent:
            text += event.delta ?? ""
        default:
            break
        }
    }
    return text
}

private func isContent(_ frame: SeveringTransport.Frame) -> Bool {
    ![.runStarted, .runFinished, .runError].contains(frame.event.eventType) && frame.id.flatMap(UInt64.init) != nil
}

/// The content-frame ids every attach delivered, in order.
private func contentIds(_ frames: [SeveringTransport.Frame]) -> [UInt64] {
    frames.filter(isContent).compactMap { $0.id.flatMap(UInt64.init) }
}

private func trimmed(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
}

extension Live {
    /// Set when the target plane's runtime replay buffer is small enough for a short disconnect to outlive it.
    static var smallReplayBuffer: Bool { value("INTROSPECTION_LIVE_SMALL_REPLAY_BUFFER") == "1" }
}
