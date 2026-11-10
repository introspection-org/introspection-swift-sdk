import Foundation
import InlineSnapshotTesting
import IntrospectionSDK
import Testing

@testable import IntrospectionWalk

/// The SDK end-to-end walk (`Tests/IntrospectionWalk`) under Swift Testing: inline snapshots go through
/// `assertInlineSnapshot`, so `SNAPSHOT_TESTING_RECORD=failed` re-records them in place.
@Suite("SDK end-to-end walk")
struct WalkTests {
    // Replay runs only against a recording that reaches the teardown; live runs always run.
    @Test(.enabled(if: WalkMode.current != .replay || WalkPaths.completeRecording() != nil))
    func walk() async throws {
        let walk = try Walk(mode: WalkMode.current) { value, expected, site in
            assertInlineSnapshot(
                of: value, as: .json, matches: expected, fileID: site.fileID, file: site.filePath, function: site.function,
                line: site.line, column: site.column)
        }
        let report = try await walk.run()
        for failure in walk.failures { Issue.record(Comment(rawValue: failure)) }
        let failed = report.steps.filter { $0.status == "failed" }.map { "\($0.n): \($0.name)" }
        #expect(failed.isEmpty, "failed steps: \(failed)")
        #expect(
            walk.transport.misses.isEmpty,
            "requests with no recorded answer:\n\(walk.transport.misses.map(\.description).joined(separator: "\n"))")
    }
}
