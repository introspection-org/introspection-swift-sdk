import Foundation
import InlineSnapshotTesting
import IntrospectionSDK
import Synchronization
import Testing

/// The SDK end-to-end walk: one ordered scenario from a clean project to a graded eval, every step an SDK
/// call, replaying the recording the JS SDK's walk made against a local stack (introspection-cloud
/// `docs/design/sdk-end-to-end-walk.md`). The steps, their order and their names are the design doc's, the same in every SDK.
///
/// Replay (the default `swift test`) needs no stack, keys or network. A live run needs a signed-in
/// `introspection login` (or `INTROSPECTION_CP_SESSION`) against the target:
///
///     WALK_MODE=record swift test --filter WalkTests        # writes Tests/recordings/walk/recording.har
///     WALK_MODE=passthrough swift test --filter WalkTests   # live, records nothing
@Suite("SDK end-to-end walk")
struct WalkTests {
    // Replay runs only against a recording that reaches the teardown; live runs always run.
    @Test(.enabled(if: WalkMode.current != .replay || WalkPaths.completeRecording() != nil))
    func walk() async throws {
        let walk = try Walk(mode: WalkMode.current)
        let report = try await walk.run()
        let failed = report.steps.filter { $0.status == "failed" }.map { "\($0.n): \($0.name)" }
        #expect(failed.isEmpty, "failed steps: \(failed)")
        #expect(
            walk.transport.misses.isEmpty,
            "requests with no recorded answer:\n\(walk.transport.misses.map(\.description).joined(separator: "\n"))")
    }
}

/// The routes called through ``Raw``.
final class RawCallLog: Sendable {
    private let calls = Mutex<[WalkReport.Request]>([])

    func log(_ method: String, _ path: String) {
        calls.withLock { $0.append(WalkReport.Request(method: method, url: nil, path: routeTemplate(path))) }
    }

    /// Each route once, in the order first called.
    var routes: [WalkReport.Request] {
        calls.withLock { calls in
            var seen = Set<WalkReport.Request>()
            return calls.filter { seen.insert($0).inserted }
        }
    }
}

func check(_ condition: Bool, _ message: @autoclosure () -> String) throws {
    if !condition { throw WalkError(message()) }
}

/// The walk's shared state: the steps run in order, each reading what the ones before it made.
final class Walk {
    let mode: HARTransport.Mode
    let settings: WalkSettings
    let transport: HARTransport
    let rawLog = RawCallLog()
    /// Inline snapshots that did not match in the running step: each records an issue rather than throwing.
    private var snapshotMismatches = 0
    /// The signed-in owner: creates the project and the service account.
    let owner: IntrospectionClient
    var member: IntrospectionClient!
    var memberToken = ""
    /// The walk's own service account in its own project, from step 2 on.
    var sa: IntrospectionClient!
    /// The same credentials on a transport the recording never sees: polls in a live run.
    var saQuiet: IntrospectionClient!
    var recipeDir: URL?

    var loginProject: Project!
    var project: Project!
    var originalDescription: String?
    var application: Application!
    var repository: Repository!
    var recipe: Recipe!
    var pinnedRecipe: Recipe!
    var connector: Connector!
    var runtime: Runtime!
    var runtimeV2: Runtime!
    var endpoint: Endpoint!
    var runner: Runner!
    var inputFile: File!
    var task: IntrospectionTask!
    var conversationId = ""
    var outputFile: File!
    var evalTask: IntrospectionTask!
    var judge: Judge!
    var experiment: Experiment!
    var automation: Automation!

    init(mode: HARTransport.Mode) throws {
        self.mode = mode
        settings = try WalkSettings.load(mode)
        if mode == .replay {
            guard let har = WalkPaths.completeRecording() else { throw WalkError("no complete recording at \(WalkPaths.har.path)") }
            transport = HARTransport(replaying: har)
        } else {
            transport = HARTransport(live: mode)
        }
        // The owner authenticates with the Control Plane session cookie, as the JS walk's `cpSession` does.
        owner = IntrospectionClient(
            configuration: .init(
                controlPlaneURL: settings.baseApiUrl, transport: transport,
                options: .init(additionalHeaders: ["Cookie": "intro_cp_session=\(settings.cpSession)"])))
    }

    func client(token: String, dataPlaneURL: URL?, quiet: Bool = false) -> IntrospectionClient {
        IntrospectionClient(
            controlPlaneURL: settings.baseApiUrl, dataPlaneURL: dataPlaneURL, credentials: BearerToken(token),
            transport: quiet ? URLSessionTransport() : transport)
    }

    func raw(_ http: HTTPClient) -> Raw {
        let log = rawLog
        return Raw(http: http) { log.log($0, $1) }
    }

    var projectId: String { project.id }

    /// Each step in the design doc's order and with its name. A step after a failed one skips rather than
    /// failing on its missing input, so one failure reads as one.
    func run() async throws -> WalkReport {
        let steps: [(Int, String, (() async throws -> Void)?)] = [
            (0, "a project of its own, created empty on the login's deployment", step0CleanSlate),
            (1, "project — read, list, update; a sibling created and deleted", step1Project),
            (2, "application — a service account, its secret, and the token that names the Data Plane", step2Application),
            (3, "repository — a hosted repository the walk pushes the recipe into", step3Repository),
            (4, "recipe — create from the repository at a pinned commit, read, list, update", step4Recipe),
            (5, "credential and variable — a write-only secret and a value the sandbox reads", step5CredentialAndVariable),
            (6, "connector — the public MCP reference server, discovered", step6Connector),
            (7, "runtime — created from the recipe and baked", step7Runtime),
            (8, "connection and endpoint — the grant binds hello-mcp to the runtime", step8ConnectionAndEndpoint),
            (9, "files in — an upload the task will find under /workspace/files", step9FilesIn),
            (10, "task — a runner on the runtime, one turn that calls the MCP and leaves a file", step10Task),
            (11, "evidence — the output file, the conversation and its items", step11Evidence),
            // The CLI serves its login's project; pending a project flag, as in the JS walk.
            (12, "the dev lane — introspection dev serves a local MCP into a development task", nil),
            (13, "telemetry reads — metrics, a tag, a share, an annotation, events", step13TelemetryReads),
            (14, "eval — a trial on the runtime, graded by the recipe's judge; an experiment over two versions", step14Eval),
            (15, "commands — exec and download inside the eval's sandbox", step15Commands),
            (16, "automations — a manual automation, triggered", step16Automations),
            (17, "access — Avery's work, read by Blake, Casey, Drew and Emery", step17Access),
            (18, "members and keys — the owner's reads, a development API key, the organisation", step18MembersAndKeys),
            (19, "teardown — everything the walk created, in reverse", step19Teardown),
        ]
        if mode != .replay {
            recipeDir = try prepareRecipe(url: settings.recipeRepositoryUrl, ref: settings.recipeGitRef, agent: settings.agent)
        }
        var report = WalkReport()
        var failed: String?
        for (n, name, body) in steps {
            guard let body, failed == nil else {
                report.steps.append(.init(n: n, name: name, status: "skipped"))
                continue
            }
            snapshotMismatches = 0
            do {
                try await body()
                let passed = snapshotMismatches == 0
                report.steps.append(.init(n: n, name: name, status: passed ? "passed" : "failed"))
                if !passed { failed = name }
            } catch {
                Issue.record(error, "step \(n): \(name)")
                report.steps.append(.init(n: n, name: name, status: "failed"))
                failed = name
            }
        }
        if let recipeDir { try? FileManager.default.removeItem(at: recipeDir) }
        try finish(&report)
        return report
    }

    private func finish(_ report: inout WalkReport) throws {
        let (total, consumed) = transport.consumption
        report.entries = .init(total: total, consumed: mode == .replay ? consumed : total)
        report.unconsumed = mode == .replay ? transport.unconsumed.map { .init(method: $0.method, url: $0.url, path: nil) } : []
        report.rawCalls = rawLog.routes
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(report)
        try FileManager.default.createDirectory(at: WalkPaths.report.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: WalkPaths.report)
        print("walk report (\(WalkPaths.report.path)):\n\(String(decoding: data, as: UTF8.self))")
        if mode == .record {
            try FileManager.default.createDirectory(at: WalkPaths.recordingDir, withIntermediateDirectories: true)
            try encoder.encode(transport.recording).write(to: WalkPaths.har)
        }
    }

    /// `assertInlineSnapshot(of: value, as: .json)` at the caller's line, counting a mismatch (or a snapshot
    /// recorded for the first time) against the running step.
    func snap(
        _ value: JSONValue, matches expected: (() -> String)? = nil, fileID: StaticString = #fileID,
        file filePath: StaticString = #filePath,
        function: StaticString = #function, line: UInt = #line, column: UInt = #column
    ) {
        var actual: String?
        Snapshotting<JSONValue, String>.json.snapshot(value).run { actual = $0 }
        if expected?() != actual { snapshotMismatches += 1 }
        assertInlineSnapshot(
            of: value, as: .json, matches: expected, fileID: fileID, file: filePath, function: function, line: line, column: column)
    }

    func expectNotFound(_ read: () async throws -> some Any, _ what: String) async throws {
        try check(try await isNotFound(read), "\(what) is still found")
    }
}
