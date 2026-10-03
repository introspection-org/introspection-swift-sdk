import Foundation

/// Retry timing shared by unary requests and resumable streams: the server's
/// `Retry-After` is a floor, and the SDK adds capped exponential full jitter.
public enum Backoff {
    /// Cap on the jitter the SDK adds (seconds). The `Retry-After` floor is never capped.
    public static let maxJitter: TimeInterval = 10

    public static func delay(
        attempt: Int,
        retryAfter: TimeInterval?,
        base: TimeInterval,
        random: () -> Double = { Double.random(in: 0..<1) }
    ) -> TimeInterval {
        let room = min(base * pow(2, Double(max(0, attempt))), maxJitter)
        return (retryAfter ?? 0) + room * random()
    }

    /// Sleep that throws `CancellationError` when the task is cancelled.
    public static func sleep(_ seconds: TimeInterval) async throws {
        guard seconds > 0 else {
            try Task.checkCancellation()
            return
        }
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}
