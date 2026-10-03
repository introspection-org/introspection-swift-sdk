import Foundation

/// Recovery bounds for a run's resumable AG-UI stream.
public struct RunStreamOptions: Sendable, Hashable {
    /// Consecutive reconnects with no forward progress before the stream throws.
    /// Reset whenever a reconnect delivers a new event. Does not bound `429` readiness waits.
    public var maxReconnects: Int
    /// Base step (seconds) of the capped exponential reconnect and readiness backoff.
    public var backoff: TimeInterval
    /// Wall-clock deadline (seconds) after which no further reconnect or readiness wait is attempted.
    public var timeout: TimeInterval
    /// Yield a `CUSTOM` event named `introspection.reconnect` on each reconnect or readiness wait.
    public var emitReconnectEvents: Bool
    /// The server's `wait_for_start`: `true` (its default) holds the attach open until the
    /// run is live; `false` answers a not-yet-attachable run with `429`, which this stream waits out.
    public var waitForStart: Bool?

    public init(
        maxReconnects: Int = 5,
        backoff: TimeInterval = 0.5,
        timeout: TimeInterval = 300,
        emitReconnectEvents: Bool = false,
        waitForStart: Bool? = nil
    ) {
        self.maxReconnects = maxReconnects
        self.backoff = backoff
        self.timeout = timeout
        self.emitReconnectEvents = emitReconnectEvents
        self.waitForStart = waitForStart
    }
}

extension AGUIEvent {
    /// The `CUSTOM` event name this SDK uses for reconnect markers.
    public static let reconnectEventName = CustomEventNames.reconnect
    /// The `CUSTOM` event name the server sends when a disconnect outlived its replay buffer.
    public static let resumeGapEventName = CustomEventNames.resumeGap

    /// Whether this is an SDK reconnect marker (see `RunStreamOptions.emitReconnectEvents`).
    public var isReconnectMarker: Bool { eventType == .custom && name == Self.reconnectEventName }

    /// Whether this is the server's `resume_gap` marker: some events were lost across a reconnect.
    public var isResumeGap: Bool { eventType == .custom && name == Self.resumeGapEventName }
}

/// The resumable AG-UI stream of one run, a port of the JS SDK's `streamResumable`.
///
/// A severed stream re-attaches with `Last-Event-ID` set to the last numeric frame id,
/// so the server replays what was missed. A `429` (run not attachable yet) is a readiness
/// wait that honours `Retry-After` and is bounded by the timeout, not the reconnect budget.
/// A clean end of the body ends the sequence; cancelling the consumer cancels the request.
enum RunStream {
    static func events(
        http: HTTPClient,
        taskId: String,
        runId: String,
        options: RunStreamOptions
    ) -> AsyncThrowingStream<AGUIEvent, Error> {
        AsyncThrowingStream { continuation in
            let worker = Task {
                do {
                    try await run(http: http, taskId: taskId, runId: runId, options: options) { event in
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in worker.cancel() }
        }
    }

    static func run(
        http: HTTPClient,
        taskId: String,
        runId: String,
        options: RunStreamOptions,
        emit: (AGUIEvent) -> Void
    ) async throws {
        let path = "/v1/tasks/\(pathSegment(taskId))/runs/\(pathSegment(runId))/stream"
        var query = Query()
        query.add("wait_for_start", options.waitForStart)
        let deadline = Date().addingTimeInterval(options.timeout)
        // Control frames carry non-numeric `c-...` ids that are not resume cursors.
        var lastEventId: String?
        var reconnects = 0
        var readinessWaits = 0

        while true {
            try Task.checkCancellation()

            // Attach, honouring the 429 readiness contract.
            let response: HTTPStreamResponse
            do {
                var headers: [String: String] = [:]
                if let lastEventId { headers["Last-Event-ID"] = lastEventId }
                response = try await http.stream("GET", path, query: query, headers: headers)
            } catch {
                if error is CancellationError || Task.isCancelled { throw CancellationError() }
                let introspectionError = error as? IntrospectionError
                if let introspectionError, isFatalAttachError(introspectionError) { throw error }
                let isRateLimit = introspectionError?.kind == .rateLimited
                if isRateLimit { readinessWaits += 1 } else { reconnects += 1 }
                if reconnects > options.maxReconnects || Date() >= deadline { throw error }
                let attempt = isRateLimit ? readinessWaits : reconnects
                let retryAfter = isRateLimit ? introspectionError?.retryAfter : nil
                if options.emitReconnectEvents {
                    emit(
                        .custom(
                            AGUIEvent.reconnectEventName,
                            value: [
                                "reason": isRateLimit ? "readiness" : "connect_error",
                                "attempt": .number(Double(attempt)),
                                "lastEventId": lastEventId.map(JSONValue.string) ?? .null,
                                "phase": isRateLimit
                                    ? (introspectionError?.body?["status"]?.stringValue).map(JSONValue.string) ?? .null : .null,
                                "retryAfterMs": retryAfter.map { .number(($0 * 1000).rounded()) } ?? .null,
                            ]))
                }
                let delay = Backoff.delay(attempt: attempt, retryAfter: retryAfter, base: options.backoff)
                try await Backoff.sleep(min(delay, deadline.timeIntervalSinceNow))
                continue
            }

            // Consume to end of body, tracking the resume cursor.
            var progressed = false
            do {
                var parser = SSEParser()
                for try await chunk in response.bytes {
                    for frame in parser.push(chunk) {
                        if let id = frame.id, isResumeCursor(id) { lastEventId = id }
                        guard frame.event == "ag_ui" else { continue }
                        let event: AGUIEvent
                        do {
                            event = try JSONCoding.decoder.decode(AGUIEvent.self, from: Data(frame.data.utf8))
                        } catch {
                            throw IntrospectionError(
                                kind: .decoding, message: "Invalid AG-UI frame: \(error)",
                                status: response.status, requestId: response.headers["x-request-id"], underlying: error
                            )
                        }
                        progressed = true
                        emit(event)
                    }
                }
                // A cancelled consumer ends the byte stream early; that is not the turn finishing.
                try Task.checkCancellation()
                return
            } catch {
                if error is CancellationError || Task.isCancelled { throw CancellationError() }
                if let introspectionError = error as? IntrospectionError, introspectionError.kind == .decoding { throw error }
                // Forward progress resets the budget, so a long turn with intermittent drops recovers.
                reconnects = progressed ? 0 : reconnects + 1
                if reconnects > options.maxReconnects || Date() >= deadline { throw error }
                if options.emitReconnectEvents {
                    emit(
                        .custom(
                            AGUIEvent.reconnectEventName,
                            value: [
                                "reason": "severed",
                                "attempt": .number(Double(reconnects)),
                                "lastEventId": lastEventId.map(JSONValue.string) ?? .null,
                            ]))
                }
                let delay = Backoff.delay(attempt: reconnects, retryAfter: nil, base: options.backoff)
                try await Backoff.sleep(min(delay, deadline.timeIntervalSinceNow))
            }
        }
    }

    /// Only an all-digit id is a content-frame sequence the server can resume from.
    static func isResumeCursor(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.allSatisfy { $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9") }
    }

    /// Client errors a reconnect cannot fix. The JS SDK retries these too; failing fast
    /// avoids spending the budget on a missing task or a rejected credential.
    static func isFatalAttachError(_ error: IntrospectionError) -> Bool {
        switch error.kind {
        case .authentication, .runnerExpired, .insufficientScope, .forbidden, .notFound, .validation, .invalidRequest, .cancelled:
            return true
        default:
            return false
        }
    }
}
