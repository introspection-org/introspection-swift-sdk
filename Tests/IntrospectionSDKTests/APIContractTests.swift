import Foundation
import Testing

@testable import IntrospectionSDK

// Compares this SDK's request and response surface against the published API
// reference (the OpenAPI documents the Data Plane and Control Plane generate
// from themselves), so drift is checked against the API's own declaration
// rather than a second hand-maintained copy. A port of the Rust SDK's
// `tests/api_contract_test.rs`.
//
// Request bodies are compared by encoding a fully populated value, so what is
// checked is the wire name, not the Swift property name: a mistyped CodingKey
// would otherwise send a field the API rejects (bodies forbid undeclared
// fields) or silently drops. No fixture relies on a default; a new optional
// field has to be set here or the check cannot see it. Read models are
// compared by the keys their decoder asks for, and each must also decode a
// fully populated object built from the reference. List filters are compared
// by the query items a real call puts on the wire.
//
// An SDK key the reference does not declare always fails. A reference key the
// SDK lacks fails for bodies and read models, and is only reported for list
// filters, where which filters to expose is a product decision. An exemption
// naming a key the reference no longer has fails too, so it cannot hide
// nothing forever.
//
// Skipped unless `INTROSPECTION_API_CONTRACT=1`: it reaches the network and goes
// red when the API changes, which is a fact about the world rather than the
// commit under review, so it runs on a schedule, not on pull requests. Set
// `INTROSPECTION_DP_OPENAPI` / `INTROSPECTION_CP_OPENAPI` to a local file to check
// a reference that is not published yet.
//
// Run: INTROSPECTION_API_CONTRACT=1 swift test --filter APIContractTests
@Suite struct APIContractTests {
    static let dataPlaneURL = "https://docs.introspection.dev/openapi/dataplane.json"
    static let controlPlaneURL = "https://docs.introspection.dev/openapi/controlplane.json"

    private let drift = Drift()

    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["INTROSPECTION_API_CONTRACT"] == "1",
            "Set INTROSPECTION_API_CONTRACT=1 to compare the SDK against the published API reference"))
    func sdkSurfaceMatchesTheReference() async throws {
        let dp = try await OpenAPIReference.load(environmentKey: "INTROSPECTION_DP_OPENAPI", url: Self.dataPlaneURL)
        let cp = try await OpenAPIReference.load(environmentKey: "INTROSPECTION_CP_OPENAPI", url: Self.controlPlaneURL)

        checkRoutes(dp: dp, cp: cp)
        try await checkTasks(dp)
        try await checkFilesAndShares(dp)
        try await checkConversations(dp)
        try await checkEventsAndMetrics(dp)
        try await checkAutomations(dp)
        try await checkAnnotations(dp)
        try await checkDataPlaneRepositories(dp)
        try await checkRuntimesAndExperiments(cp)
        try await checkConnectors(cp)
        try await checkOrganization(cp)
        try await checkAuth(cp)

        for note in drift.notes { print("note: \(note)") }
        if drift.problems.isEmpty {
            print("SDK surface matches the reference (\(drift.surfaces) surfaces, \(dp.source) + \(cp.source))")
        } else {
            Issue.record(
                "the SDK surface has drifted from the reference:\n\n\(drift.problems.joined(separator: "\n\n"))\n\nreference: \(dp.source) + \(cp.source)"
            )
        }
    }

    /// The probe behind every read-model check, exercised without the network so it cannot pass by reading nothing.
    @Test func decodedKeysReadTheCodingKeys() throws {
        let keys = try decodedKeys(IntrospectionTask.self)
        #expect(keys.isSuperset(of: ["id", "is_archived", "conversation_metadata", "agent"]))
        #expect(try decodedKeys(TaskRun.self) == ["id", "task_id", "status", "created_at", "updated_at"])
        #expect(try wireKeys(TaskRepoRequest(repo: "a/b", ref: "main", depth: 1)) == ["repo", "ref", "depth"])
    }

    // MARK: Comparison

    private enum Kind {
        case body
        case readModel
        case filters
        case routes

        var extraMeans: String {
            switch self {
            case .body: return "sent here but not declared by the API (a body that forbids undeclared fields rejects it with a 422)"
            case .readModel: return "read here but not returned by the API (the SDK describes a response that no longer exists)"
            case .filters: return "sent as a query parameter the API does not accept"
            case .routes: return "called here but not served by the API"
            }
        }

        var missingMeans: String {
            switch self {
            case .body: return "accepted by the API but unavailable to callers of this SDK"
            case .readModel: return "returned by the API but not surfaced by this SDK"
            case .filters: return "accepted by the API but not exposed here"
            case .routes: return ""
            }
        }
    }

    /// Compare one surface. `exempt` names reference keys this SDK omits on purpose; `sdkOnly` names
    /// keys it reads on purpose although this reference does not declare them.
    private func compare(
        _ surface: String,
        _ kind: Kind,
        sdk: Set<String>,
        reference: Set<String>?,
        exempt: Set<String> = [],
        sdkOnly: Set<String> = [],
        missingIsFatal: Bool? = nil
    ) {
        drift.surfaces += 1
        guard let reference else {
            drift.problems.append("\(surface)\n  the reference does not declare this surface")
            return
        }
        let extra = sdk.subtracting(reference).subtracting(sdkOnly)
        let missing = reference.subtracting(sdk).subtracting(exempt)
        let stale = exempt.subtracting(reference).union(sdkOnly.intersection(reference))
        var lines: [String] = []
        if !extra.isEmpty { lines.append("  \(kind.extraMeans):\(Self.list(extra))") }
        if !missing.isEmpty {
            if missingIsFatal ?? (kind != .filters) {
                lines.append("  \(kind.missingMeans):\(Self.list(missing))")
            } else {
                drift.notes.append("\(surface): \(kind.missingMeans):\(Self.list(missing))")
            }
        }
        if !stale.isEmpty { lines.append("  exemption no longer matches the API (drop it):\(Self.list(stale))") }
        if !lines.isEmpty { drift.problems.append("\(surface)\n\(lines.joined(separator: "\n"))") }
    }

    private static func list(_ names: Set<String>) -> String {
        names.sorted().map { "\n      \($0)" }.joined()
    }

    private func body<T: Encodable>(
        _ surface: String, _ value: T, _ reference: OpenAPIReference, _ schema: String, exempt: Set<String> = [],
        sdkOnly: Set<String> = []
    ) throws {
        compare(surface, .body, sdk: try wireKeys(value), reference: reference.properties(schema), exempt: exempt, sdkOnly: sdkOnly)
    }

    /// A read model: the keys its decoder reads, and a decode of a fully populated reference object.
    private func readModel<T: Decodable>(
        _ surface: String, _ type: T.Type, _ reference: OpenAPIReference, _ schema: String, exempt: Set<String> = [],
        sdkOnly: Set<String> = []
    ) throws {
        compare(
            surface, .readModel, sdk: try decodedKeys(type), reference: reference.properties(schema), exempt: exempt, sdkOnly: sdkOnly)
        guard let sample = reference.sample(schema) else { return }
        do {
            _ = try sample.decode(T.self)
        } catch {
            drift.problems.append("\(surface)\n  does not decode a fully populated \(schema) from the reference: \(error)")
        }
    }

    private func filters(
        _ surface: String, _ reference: OpenAPIReference, _ method: String, _ path: String, exempt: Set<String> = [],
        sdkOnly: Set<String> = [], missingIsFatal: Bool = false, _ call: (IntrospectionClient) async throws -> Void
    ) async {
        let transport = MockTransport { _, _ in .response(.json(#"{"records":[],"count":0,"data":[]}"#)) }
        _ = try? await call(makeClient(transport))
        guard !transport.requests.isEmpty else {
            drift.problems.append("\(surface)\n  the call sent no request, so nothing was compared")
            return
        }
        let sent = Set(transport.requests.flatMap { $0.query.keys })
        compare(
            surface, .filters, sdk: sent, reference: reference.queryParameters(method, path), exempt: exempt,
            sdkOnly: sdkOnly, missingIsFatal: missingIsFatal)
    }

    /// The JSON body of the request `call` sends, for bodies the SDK assembles inside the call.
    private func sentBody(_ call: (IntrospectionClient) async throws -> Void) async -> Set<String> {
        let transport = MockTransport { _, _ in .response(.json("{}", status: 201)) }
        _ = try? await call(makeClient(transport))
        return Set(transport.requests.compactMap { $0.json?.objectValue }.flatMap(\.keys))
    }

    // MARK: Fixtures

    private let date = Date(timeIntervalSince1970: 1_767_225_600)
    private let object: JSONObject = ["key": "value"]

    // MARK: Routes

    private func checkRoutes(dp: OpenAPIReference, cp: OpenAPIReference) {
        let dataPlane = [
            "GET /v1/tasks", "POST /v1/tasks", "GET /v1/tasks/{task_id}", "PATCH /v1/tasks/{task_id}",
            "DELETE /v1/tasks/{task_id}", "POST /v1/tasks/{task_id}/archive", "POST /v1/tasks/{task_id}/unarchive",
            "POST /v1/tasks/{task_id}/runs", "GET /v1/tasks/{task_id}/runs/{run_id}",
            "POST /v1/tasks/{task_id}/runs/{run_id}/cancel", "GET /v1/tasks/{task_id}/runs/{run_id}/stream",
            "GET /v1/files", "POST /v1/files", "GET /v1/files/{file_id}", "PATCH /v1/files/{file_id}",
            "DELETE /v1/files/{file_id}", "GET /v1/files/{file_id}/content", "GET /v1/files/{file_id}/versions",
            "POST /v1/files/{file_id}/versions", "GET /v1/files/{file_id}/versions/{file_version_id}",
            "GET /v1/shares", "POST /v1/shares", "GET /v1/shares/{share_id}", "DELETE /v1/shares/{share_id}",
            "GET /v1/conversations", "GET /v1/conversations/{conversation_id}",
            "GET /v1/conversations/{conversation_id}/export", "GET /v1/conversations/{conversation_id}/items",
            "GET /v1/conversations/{conversation_id}/items/{item_id}", "GET /v1/conversations/{conversation_id}/turns",
            "GET /v1/events", "GET /v1/events/{event_id}", "POST /v1/metrics",
            "GET /v1/automations", "POST /v1/automations", "GET /v1/automations/{automation_id}",
            "PATCH /v1/automations/{automation_id}", "DELETE /v1/automations/{automation_id}",
            "POST /v1/automations/{automation_id}/trigger",
            "GET /v1/annotations", "POST /v1/annotations", "GET /v1/annotations/facets", "GET /v1/annotations/navigation",
            "GET /v1/project-labels", "POST /v1/project-labels", "GET /v1/project-labels/{slug}",
            "PATCH /v1/project-labels/{slug}",
            "GET /v1/repositories/{repository_id}/commits", "GET /v1/repositories/{repository_id}/commits/{sha}",
            "GET /v1/repositories/{repository_id}/contents", "GET /v1/repositories/{repository_id}/contents/{path}",
            "POST /v1/repositories/{repository_id}/merges",
        ]
        let controlPlane = [
            "GET /v1/runtimes", "GET /v1/runtimes/{runtime_id}", "POST /v1/runtimes/{runtime_id}/run",
            "GET /v1/experiments", "POST /v1/experiments", "GET /v1/experiments/{experiment_id}",
            "PATCH /v1/experiments/{experiment_id}", "DELETE /v1/experiments/{experiment_id}",
            "POST /v1/experiments/{experiment_id}/start", "POST /v1/experiments/{experiment_id}/end",
            "POST /v1/experiments/{experiment_id}/cancel", "POST /v1/experiments/{experiment_id}/run",
            "GET /v1/connectors", "POST /v1/connectors", "GET /v1/connectors/{connector_id}",
            "PATCH /v1/connectors/{connector_id}", "DELETE /v1/connectors/{connector_id}",
            "GET /v1/connectors/{connector_id}/apps", "GET /v1/connectors/custom/apps", "POST /v1/connectors/discover-oauth",
            "GET /v1/connectors/{connector_id}/connections", "POST /v1/connectors/{connector_id}/connections",
            "GET /v1/connectors/{connector_id}/connections/{connection_id}",
            "DELETE /v1/connectors/{connector_id}/connections/{connection_id}",
            "POST /v1/oauth/connections/authorize", "POST /v1/oauth/connections/token",
            "GET /v1/repositories", "GET /v1/repositories/{repository_id}", "GET /v1/organizations/current",
            "GET /v1/projects", "GET /v1/projects/{project}", "GET /v1/members", "POST /v1/members",
            "GET /v1/members/{member_id}", "PATCH /v1/members/{member_id}",
            "GET /v1/oidc/me", "GET /v1/recipes", "GET /v1/recipes/{recipe_id}",
            "POST /v1/oauth/token", "POST /v1/oauth/device/code", "GET /v1/oauth/authorize", "POST /v1/oauth/revoke",
            "POST /v1/tokens", "POST /v1/oauth/email/code",
        ]
        // Email-code sign-in is proposed for the Control Plane but not served yet.
        let unpublished: Set<String> = ["POST /v1/oauth/email/code"]
        func missing(_ routes: [String], _ reference: OpenAPIReference) -> Set<String> {
            Set(
                routes.filter { route in
                    let parts = route.split(separator: " ", maxSplits: 1).map(String.init)
                    return !reference.hasOperation(parts[0], parts[1])
                })
        }
        drift.surfaces += 1
        let absent = missing(dataPlane, dp).union(missing(controlPlane, cp))
        let unexpected = absent.subtracting(unpublished)
        let published = unpublished.subtracting(absent)
        if !unexpected.isEmpty { drift.problems.append("routes\n  \(Kind.routes.extraMeans):\(Self.list(unexpected))") }
        if !published.isEmpty { drift.problems.append("routes\n  listed as unpublished but now served (drop it):\(Self.list(published))") }
        if !absent.intersection(unpublished).isEmpty {
            drift.notes.append("routes: called here and not yet served:\(Self.list(absent.intersection(unpublished)))")
        }
    }

    // MARK: Tasks

    private func checkTasks(_ dp: OpenAPIReference) async throws {
        let file = TaskFileRef(id: "file-1", name: "notes.md", sizeBytes: 12)
        let repo = TaskRepoRequest(repo: "acme/app", ref: "main", depth: 1)
        let patch = TaskRecipePatch(
            patchFileId: "file-2", checkoutBaseCommitSha: "abc", checkoutRepositoryName: "acme/recipes", checkoutRecipeSubPath: "agent")
        let create = TaskCreate(
            prompt: "hi", title: "t", kind: .eval, agentName: "agent", runtimeId: "rt", bindingsRequired: false,
            recipeGitCommitSha: "abc", recipePatch: patch, repositories: [repo], idleTimeoutSeconds: 60,
            collectSandboxLogs: true, metadata: object, conversationMetadata: ["flow": "checkout"], tags: ["a:b"],
            files: [file], commands: true, compose: object, forkShareId: "share-1")
        try body("TaskCreate: POST /v1/tasks body", create, dp, "TaskCreate")
        try body("TaskFileRef: TaskCreate.files[]", file, dp, "TaskFileRef")
        try body("TaskRepoRequest: TaskCreate.repositories[]", repo, dp, "TaskRepoRequest")
        try body("TaskRecipePatch: TaskCreate.recipe_patch", patch, dp, "TaskRecipePatch")
        try body(
            "TaskUpdate: PATCH /v1/tasks/{id} body", TaskUpdate(title: "t", isArchived: true, metadata: object, tags: []), dp, "TaskUpdate")

        // A new turn and an interrupt resume are two calls on one body schema.
        let run = TaskRunCreate(
            prompt: TaskPrompt(text: "hi", images: ["aGk="]), kind: .steer, metadata: object, files: [file], deliveryId: "d1",
            runtimeId: "rt")
        let resume = TaskRunResume(resume: [.resolved("i1", payload: "yes")], metadata: object, deliveryId: "d1", runtimeId: "rt")
        compare(
            "TaskRunCreate + TaskRunResume: POST /v1/tasks/{id}/runs body", .body,
            sdk: try wireKeys(run).union(wireKeys(resume)), reference: dp.properties("TaskRunCreate"))
        try body("TaskPrompt: TaskRunCreate.prompt", TaskPrompt(text: "hi", images: ["aGk="]), dp, "TaskPrompt")
        try body(
            "TaskCancelOptions: POST /v1/tasks/{id}/runs/{run_id}/cancel body", TaskCancelOptions.drain(within: 30), dp, "TaskCancelRequest"
        )

        try readModel("IntrospectionTask: the task read model", IntrospectionTask.self, dp, "Task")
        try readModel("AgentInfo: Task.agent", AgentInfo.self, dp, "AgentInfo")
        try readModel("TaskRun: the run read model", TaskRun.self, dp, "TaskRun")
        try readModel("TaskCreateResponse: POST /v1/tasks response", TaskCreateResponse.self, dp, "TaskCreateResponse")
        try readModel("TaskRunResponse: POST /v1/tasks/{id}/runs response", TaskRunResponse.self, dp, "TaskRunResponse")
        try readModel("TaskCancelResponse: cancel response", TaskCancelResponse.self, dp, "TaskCancelResponse")

        let list = TaskListParams(
            limit: 1, next: "cursor", includeTotal: true, statuses: [.running], runtimeId: "rt", runtimeIds: ["rt"],
            updatedAfter: date, requireAutomationId: true, automationId: "a1", memberId: "m1", conversationId: "c1",
            conversationIds: ["c1"], tag: "a:b")
        await filters("task list filters: GET /v1/tasks", dp, "GET", "/v1/tasks") { _ = try await $0.tasks.list(list).firstPage() }
        // The stream resumes with a `Last-Event-ID` header rather than the `since` parameter.
        await filters("run stream options: GET /v1/tasks/{id}/runs/{run_id}/stream", dp, "GET", "/v1/tasks/{task_id}/runs/{run_id}/stream")
        {
            let options = RunStreamOptions(maxReconnects: 0, backoff: 0, timeout: 1, emitReconnectEvents: false, waitForStart: true)
            for try await _ in $0.tasks.runs.stream("t1", "r1", options: options) {}
        }
        await filters("task read options: GET /v1/tasks/{id}", dp, "GET", "/v1/tasks/{task_id}", missingIsFatal: true) {
            _ = try await $0.tasks.get("t1", include: [.agent])
        }
    }

    // MARK: Files and shares

    private func checkFilesAndShares(_ dp: OpenAPIReference) async throws {
        try readModel("File: the file read model", File.self, dp, "File")
        try body("FileUpdate: PATCH /v1/files/{id} body", FileUpdate(name: "n", metadata: object, tags: []), dp, "FileUpdate")
        let list = FileListParams(
            limit: 1, next: "cursor", includeTotal: true, includeVersions: true, shareIds: ["s1"], name: "n",
            nameContains: "n", fileType: .upload, category: .memory, contentFormat: .markdown, versioned: true,
            storagePath: "p", taskId: "t1", conversationId: "c1", memberId: "m1", tag: "a:b", createdAfter: date,
            createdBefore: date, updatedAfter: date, updatedBefore: date, metadata: ["status": "open"])
        // Sent before the server publishes it (introspection-cloud#3123); the stale check flags it once it does.
        await filters("file list filters: GET /v1/files", dp, "GET", "/v1/files", sdkOnly: ["metadata"]) {
            _ = try await $0.files.list(list).firstPage()
        }
        await filters(
            "file version filters: GET /v1/files/{id}/versions", dp, "GET", "/v1/files/{file_id}/versions", missingIsFatal: true
        ) {
            _ = try await $0.files.versions.list("f1", FileVersionListParams(limit: 1, next: "cursor", includeTotal: true)).firstPage()
        }
        await filters("file read options: GET /v1/files/{id}", dp, "GET", "/v1/files/{file_id}", missingIsFatal: true) {
            _ = try await $0.files.get("f1", shareId: "s1")
        }
        await filters("file content options: GET /v1/files/{id}/content", dp, "GET", "/v1/files/{file_id}/content", missingIsFatal: true) {
            _ = try await $0.files.download("f1", shareId: "s1")
        }

        try readModel("ResourceShare: the share read model", ResourceShare.self, dp, "ResourceShare")
        try body(
            "ShareCreate: POST /v1/shares body", ShareCreate(resourceType: .file, resourceId: "f1", grantedMemberId: "m1"), dp,
            "ShareCreate")
        let shares = ShareListParams(
            limit: 1, next: "cursor", resourceType: .file, resourceId: "f1", grantedMemberId: "m1", createdByMe: true, grantedToMe: true)
        await filters("share list filters: GET /v1/shares", dp, "GET", "/v1/shares") { _ = try await $0.shares.list(shares).firstPage() }
    }

    // MARK: Conversations

    private func checkConversations(_ dp: OpenAPIReference) async throws {
        // `Conversation`, `GenAiSpan` and the turn resources declare no properties in the reference, so
        // comparing them would pass by doing nothing. Their list envelopes and nested blocks are declared.
        try readModel("GenAISpanList: GET /v1/conversations/{id}/items and export envelope", GenAISpanList.self, dp, "GenAiSpanList")
        try readModel("ConversationUsage: Conversation.usage", ConversationUsage.self, dp, "ConversationUsage")
        try readModel("ConversationCost: Conversation.cost", ConversationCost.self, dp, "ConversationCost")
        try readModel("ConversationMetrics: Conversation.metrics", ConversationMetrics.self, dp, "ConversationMetrics")

        // `lookback` is left out: it conflicts with `start`/`end`, and all three lower into `start_date`/`end_date`.
        let list = ConversationListParams(
            limit: 1, next: "cursor", order: .asc, start: date, end: date, sort: .cost, shareIds: ["s1"],
            conversationId: "c1", conversationIds: ["c1"], traceId: "tr", annotationId: "an", model: "m", agentName: "a",
            status: .ok, serviceName: "svc", serviceNames: ["svc"], environment: "production", runtimeId: "rt",
            runtimeGroupId: "rg", experimentId: "ex", recipeGitCommitSha: "abc", resolution: "resolved",
            sentiment: "positive", ownerKey: "user:1", metadata: ["flow": "checkout"])
        await filters("conversation list filters: GET /v1/conversations", dp, "GET", "/v1/conversations") {
            _ = try await $0.conversations.list(list).firstPage()
        }
        await filters(
            "conversation read options: GET /v1/conversations/{id}", dp, "GET", "/v1/conversations/{conversation_id}",
            missingIsFatal: true
        ) { _ = try await $0.conversations.get("c1", shareId: "s1", annotationId: "an") }
        let items = ConversationItemListParams(
            limit: 1, next: "cursor", include: [.events], agent: "a", serviceName: "svc", operationName: "chat", traceId: "tr",
            spanId: "sp", startDate: date, endDate: date, lookbackDays: 7, shareId: "s1", annotationId: "an", fromCompaction: true)
        await filters(
            "conversation item filters: GET /v1/conversations/{id}/items", dp, "GET", "/v1/conversations/{conversation_id}/items",
            missingIsFatal: true
        ) { _ = try await $0.conversations.items.list("c1", items).firstPage() }
        await filters(
            "conversation item read options: GET /v1/conversations/{id}/items/{item_id}", dp, "GET",
            "/v1/conversations/{conversation_id}/items/{item_id}", missingIsFatal: true
        ) { _ = try await $0.conversations.items.get("c1", "i1", include: [.events], shareId: "s1", annotationId: "an") }
        let export = ConversationExportParams(
            agent: "a", serviceName: "svc", operationName: "chat", lookbackDays: 7, shareId: "s1", annotationId: "an",
            startDate: date, endDate: date, fromCompaction: true)
        await filters(
            "conversation export filters: GET /v1/conversations/{id}/export", dp, "GET", "/v1/conversations/{conversation_id}/export",
            missingIsFatal: true
        ) { _ = try await $0.conversations.exportJSON("c1", export) }
        let turns = ConversationTurnListParams(
            limit: 1, next: "cursor", agent: "a", beforeTraceId: "tr0", traceId: "tr", lookbackDays: 7, shareId: "s1", annotationId: "an")
        await filters(
            "conversation turn filters: GET /v1/conversations/{id}/turns", dp, "GET", "/v1/conversations/{conversation_id}/turns",
            missingIsFatal: true
        ) { _ = try await $0.conversations.turns("c1", turns).firstPage() }
    }

    // MARK: Events and metrics

    private func checkEventsAndMetrics(_ dp: OpenAPIReference) async throws {
        compare(
            "IntrospectionEventName: the event families", .readModel, sdk: Set(IntrospectionEventName.allCases.map(\.rawValue)),
            reference: dp.enumValues("IntrospectionEventName").map(Set.init))
        // One family stands in for all: the envelope is shared, so a field added or dropped moves every family at once.
        try readModel("IntrospectionEvent: the common event envelope", IntrospectionEvent.self, dp, "FeedbackEvent")
        try readModel("AnnotationPayload", AnnotationPayload.self, dp, "AnnotationPayload")
        try readModel("FeedbackPayload", FeedbackPayload.self, dp, "FeedbackPayload")
        try readModel("ObservationPayload", ObservationPayload.self, dp, "ObservationPayload")
        try readModel("PatternPayload", PatternPayload.self, dp, "PatternPayload")
        try readModel("PatternAssignmentPayload", PatternAssignmentPayload.self, dp, "PatternAssignmentPayload")
        try readModel("ClusteringRunPayload", ClusteringRunPayload.self, dp, "ClusteringRunPayload")
        try readModel("JudgementPayload", JudgementPayload.self, dp, "JudgementPayload")
        try readModel("TrackPayload", TrackPayload.self, dp, "TrackPayload")
        try readModel("AutomationTriggeredPayload", AutomationTriggeredPayload.self, dp, "AutomationTriggered")
        try readModel("AutomationSkippedPayload", AutomationSkippedPayload.self, dp, "AutomationSkipped")

        // `lookback` is left out for the same reason as on the conversation list.
        let events = EventListParams(
            eventName: .observation, limit: 1, next: "cursor", sort: .createdAt, order: .desc, start: date, end: date,
            conversationId: "c1", conversationIds: ["c1"], serviceName: "svc", environment: "production", runtimeGroupId: "rg",
            traceId: "tr", spanId: "sp", ownerKey: "user:1", eventIds: ["e1"], runtimeGroupUnattributed: true, lens: "l",
            patternId: "p1", includeSuperseded: true, status: "open", judgeId: "j1", issueId: "is1", latestRequests: true,
            requestId: "r1", assigneeId: "m1", automationId: "a1", taskId: "t1")
        await filters("event list filters: GET /v1/events", dp, "GET", "/v1/events", missingIsFatal: true) {
            _ = try await $0.events.list(events).firstPage()
        }

        let spec = MetricSpec(.avg, measure: "duration_ms")
        let filter = MetricFilter("model", .eq, "gpt")
        let time = MetricTimeDimension(granularity: .oneHour, bins: 24)
        let order = MetricOrderBy(type: .metric, direction: .desc, metricIndex: 0, field: "model")
        let having = MetricHaving(metricIndex: 0, .gt, 1)
        let config = MetricQueryConfig(rowLimit: 10, seriesLimit: 5)
        let query = MetricQueryRequest(
            view: .spans, metrics: [spec], from: date, to: date, dimensions: [MetricDimension("model")], filters: [filter],
            timeDimension: time, orderBy: [order], having: [having], config: config)
        try body("MetricQueryRequest: POST /v1/metrics body", query, dp, "MetricQueryRequest")
        try body("MetricSpec", spec, dp, "MetricSpec")
        try body("MetricDimension", MetricDimension("model"), dp, "MetricDimension")
        try body("MetricFilter", filter, dp, "MetricFilter")
        try body("MetricTimeDimension", time, dp, "MetricTimeDimension")
        try body("MetricOrderBy", order, dp, "MetricOrderBy")
        try body("MetricHaving", having, dp, "MetricHaving")
        try body("MetricQueryConfig", config, dp, "MetricQueryConfig")
        try readModel("MetricQueryResponse: POST /v1/metrics response", MetricQueryResponse.self, dp, "MetricQueryResponse")
        try readModel("MetricResultRow", MetricResultRow.self, dp, "MetricResultRow")
        try readModel("MetricResultValue", MetricResultValue.self, dp, "MetricResultValue")
        try readModel("MetricDimensionValue", MetricDimensionValue.self, dp, "MetricDimensionValue")
        try readModel("MetricQueryMeta", MetricQueryMeta.self, dp, "MetricQueryMeta")
        try readModel("MetricEffectiveWindow", MetricEffectiveWindow.self, dp, "EffectiveWindow")
    }

    // MARK: Automations

    private func checkAutomations(_ dp: OpenAPIReference) async throws {
        // introspection-cloud#3154 drops `agent_member_id`; drop the exemption once the reference does.
        try readModel("Automation: the automation read model", Automation.self, dp, "Automation", exempt: ["agent_member_id"])
        let create = AutomationCreate(
            name: "n", triggerType: .cron, description: "d", cronSchedule: "0 * * * *", kind: .observationSynthesis, prompt: "p",
            runtimeGroupId: "rg", taskId: "t1", nextTriggerAt: date, metadata: object, enabled: true)
        try body("AutomationCreate: POST /v1/automations body", create, dp, "AutomationCreate")
        let update = AutomationUpdate(
            name: "n", description: "d", cronSchedule: "0 * * * *", prompt: "p", runtimeGroupId: "rg", taskId: "t1", nextTriggerAt: date,
            metadata: object, enabled: true)
        try body("AutomationUpdate: PATCH /v1/automations/{id} body", update, dp, "AutomationUpdate")
        try readModel(
            "AutomationTriggerResponse: POST /v1/automations/{id}/trigger response", AutomationTriggerResponse.self, dp,
            "AutomationTriggerResponse")
        let list = AutomationListParams(
            limit: 1, next: "cursor", kind: .observationClustering, enabled: true, scheduled: true, taskId: "t1")
        // Sent before the server publishes it (introspection-cloud#3137); drop `sdkOnly` once it does.
        await filters(
            "automation list filters: GET /v1/automations", dp, "GET", "/v1/automations", sdkOnly: ["task_id"], missingIsFatal: true
        ) {
            _ = try await $0.automations.list(list).firstPage()
        }
    }

    // MARK: Annotations and project labels

    private func checkAnnotations(_ dp: OpenAPIReference) async throws {
        let target = AnnotationTarget(traceId: "tr", spanId: "sp")
        let created = await sentBody { client in
            _ = try await client.annotations.create(target, .labels(["bug"], comment: "c"), eventId: "e1")
            _ = try await client.annotations.create(target, .assignees(["m1"]), eventId: "e2")
        }
        compare("AnnotationCreate: POST /v1/annotations body", .body, sdk: created, reference: dp.properties("AnnotationCreate"))
        try readModel("AnnotationState: the annotation read model", AnnotationState.self, dp, "AnnotationState")
        try readModel("AnnotationFacet", AnnotationFacet.self, dp, "AnnotationFacet")
        try readModel("AnnotationNavigation", AnnotationNavigation.self, dp, "AnnotationNavigation")
        let list = AnnotationListParams(
            annotatedByMemberId: "m1", assigneeMemberId: "m2", traceId: "tr", spanId: "sp", conversationId: "c1", labels: ["bug"],
            status: .assigned, includeTotal: true, limit: 1, next: "cursor")
        await filters("annotation list filters: GET /v1/annotations", dp, "GET", "/v1/annotations", missingIsFatal: true) {
            _ = try await $0.annotations.list(list).firstPage()
        }
        await filters(
            "annotation navigation filters: GET /v1/annotations/navigation", dp, "GET", "/v1/annotations/navigation", missingIsFatal: true
        ) {
            _ = try await $0.annotations.navigation(
                target, annotatedByMemberId: "m1", assigneeMemberId: "m2", labels: ["bug"], status: .assigned)
        }

        try readModel("ProjectLabel: the project label read model", ProjectLabel.self, dp, "ProjectLabel")
        try body(
            "ProjectLabelCreate: POST /v1/project-labels body", ProjectLabelCreate(slug: "bug", color: "#f97316", description: "d"), dp,
            "ProjectLabelCreate")
        try body("ProjectLabelUpdate: PATCH /v1/project-labels/{slug} body", ProjectLabelUpdate(description: "d"), dp, "ProjectLabelUpdate")
        await filters("project label filters: GET /v1/project-labels", dp, "GET", "/v1/project-labels", missingIsFatal: true) {
            _ = try await $0.projectLabels.list(ProjectLabelListParams(search: "b", limit: 1, next: "cursor")).firstPage()
        }
    }

    // MARK: Repository contents (Data Plane)

    private func checkDataPlaneRepositories(_ dp: OpenAPIReference) async throws {
        try readModel("RepositoryCommit", RepositoryCommit.self, dp, "RepositoryCommit")
        try readModel("RepositoryCommitPerson", RepositoryCommitPerson.self, dp, "RepositoryCommitPerson")
        try readModel("RepositoryCommitDetail", RepositoryCommitDetail.self, dp, "RepositoryCommitDetail")
        try readModel("RepositoryCommitFile", RepositoryCommitFile.self, dp, "RepositoryCommitFile")
        try readModel("RepositoryEntry", RepositoryEntry.self, dp, "RepositoryEntry")
        // `type` is the discriminator `RepositoryContent` reads before choosing a shape.
        try readModel("RepositoryDirectory", RepositoryDirectory.self, dp, "RepositoryDirectory", exempt: ["type"])
        try readModel("RepositoryContent (file): GET /v1/repositories/{id}/contents/{path}", RepositoryContent.self, dp, "RepositoryFile")
        try readModel("RepositoryMerge: POST /v1/repositories/{id}/merges response", RepositoryMerge.self, dp, "RepositoryMergeCommit")
        try body(
            "RepositoryMergeCreate: POST /v1/repositories/{id}/merges body",
            RepositoryMergeCreate(base: "main", head: "dev", commitMessage: "m"), dp, "RepositoryMergeCreate")
        await filters(
            "repository commit filters: GET /v1/repositories/{id}/commits", dp, "GET", "/v1/repositories/{repository_id}/commits",
            missingIsFatal: true
        ) {
            _ = try await $0.repositories.commits("r1", RepositoryCommitsParams(sha: "main", path: "src", limit: 1, cursor: "cursor"))
                .firstPage()
        }
        await filters(
            "repository content options: GET /v1/repositories/{id}/contents/{path}", dp, "GET",
            "/v1/repositories/{repository_id}/contents/{path}", missingIsFatal: true
        ) { _ = try await $0.repositories.contents.get("r1", path: "src", ref: "main", limit: 1, cursor: "cursor") }
    }

    // MARK: Runtimes and experiments

    private func checkRuntimesAndExperiments(_ cp: OpenAPIReference) async throws {
        try readModel("Runtime: the runtime read model", Runtime.self, cp, "Runtime")
        try readModel("RuntimeImageBuildMetadata", RuntimeImageBuildMetadata.self, cp, "RuntimeImageBuildMetadata")
        try readModel("RuntimeMcpRequirement", RuntimeMcpRequirement.self, cp, "RuntimeMcpRequirement")
        await filters("runtime list filters: GET /v1/runtimes", cp, "GET", "/v1/runtimes", missingIsFatal: true) {
            _ = try await $0.runtimes.list(
                RuntimeListParams(project: "p", runtime: "rg", recipeId: "rc", environment: .staging, limit: 1, next: "cursor")
            )
            .firstPage()
        }
        await filters("runtime read options: GET /v1/runtimes/{id}", cp, "GET", "/v1/runtimes/{runtime_id}", missingIsFatal: true) {
            _ = try await $0.runtimes.get("rt", project: "p", include: [.mcpRequirements])
        }

        let identity = RunnerIdentity(
            userId: "u1", anonymousId: "a1", conversationId: "c1", tags: ["a:b"], metadata: ["plan": "enterprise"])
        let library = RunCallerLibrary(name: "swift", version: "1")
        let page = RunCallerPage(path: "/", referrer: "r", search: "?q", title: "t", url: "https://example.com")
        let caller = RunCaller(ip: "127.0.0.1", userAgent: "ua", locale: "en", library: library, page: page)
        let run = RunRequest(
            identity: identity, caller: caller, agentName: "agent", ttlSeconds: 600, scope: "tasks:write", environment: .staging,
            recipeId: "rc", bindingsRequired: false)
        try body("RunRequest: POST /v1/runtimes/{id}/run body", run, cp, "RunRequest")
        // Member metadata is sent before the server publishes it (introspection-cloud#3144); the stale check flags it once it does.
        try body("RunnerIdentity: RunRequest.identity", identity, cp, "RunnerIdentity", sdkOnly: ["metadata"])
        try body("RunCaller: RunRequest.caller", caller, cp, "CallerContext")
        try body("RunCallerLibrary: RunCaller.library", library, cp, "CallerLibrary")
        try body("RunCallerPage: RunCaller.page", page, cp, "CallerPage")
        try readModel("RunnerSpec: POST /v1/runtimes/{id}/run response", RunnerSpec.self, cp, "RunnerSpec")
        try readModel("RunnerDeployment: RunnerSpec.deployment", RunnerDeployment.self, cp, "RunnerDeployment")
        try readModel("RunnerContext: RunnerSpec.runtime_context", RunnerContext.self, cp, "RunnerContextSummary")
        // `project_id` is the deprecated spelling of `project`; this SDK sends the current one.
        await filters(
            "runner options: POST /v1/runtimes/{id}/run", cp, "POST", "/v1/runtimes/{runtime_id}/run", exempt: ["project_id"],
            missingIsFatal: true
        ) {
            _ = try await $0.runtimes.openRunner("rt", project: "p")
        }

        let guardBounds = ExperimentGoalGuard(min: 0.1, max: 0.9)
        let judge = ExperimentGoalComponent(source: "judge", judgeId: "j1", judgeDefinitionHash: "h", weight: 1, guard: guardBounds)
        let telemetry = ExperimentGoalComponent(
            source: "telemetry", column: "duration_ms", aggregation: "avg", weight: 1, guard: guardBounds)
        let goal = ExperimentGoal(kind: "composite", direction: .maximize, components: [judge])
        let arm = ExperimentArmCreate(runtimeId: "rt", armLabel: "a", agentOverrides: ["agent": "other"])
        let create = ExperimentCreate(
            project: "p", runtime: "rg", name: "n", goalJson: goal, arms: [arm], description: "d", environment: .staging,
            scoringIntervalSeconds: 60, hashKeyFields: ["user_id"], sampleRate: 0.5)
        try body("ExperimentCreate: POST /v1/experiments body", create, cp, "ExperimentCreate")
        try body("ExperimentGoal: ExperimentCreate.goal_json", goal, cp, "ExperimentGoalSpec")
        try body("ExperimentArmCreate: ExperimentCreate.arms[]", arm, cp, "ExperimentArmCreate")
        try body("ExperimentGoalGuard", guardBounds, cp, "ExperimentGoalGuard")
        let components = [cp.properties("JudgeGoalComponent"), cp.properties("TelemetryGoalComponent")].compactMap { $0 }
        compare(
            "ExperimentGoalComponent: judge and telemetry components", .body,
            sdk: try wireKeys(judge).union(wireKeys(telemetry)),
            reference: components.isEmpty ? nil : components.reduce(Set()) { $0.union($1) })
        let update = ExperimentUpdate(
            name: "n", description: "d", goalJson: goal, scoringIntervalSeconds: 60, hashKeyFields: ["user_id"], sampleRate: 0.5)
        try body("ExperimentUpdate: PATCH /v1/experiments/{id} body", update, cp, "ExperimentUpdate")
        try readModel("Experiment: the experiment read model", Experiment.self, cp, "Experiment")
        try readModel("ExperimentArm: Experiment.arms[]", ExperimentArm.self, cp, "ExperimentArm")
        try readModel("ExperimentGoal: Experiment.goal_json", ExperimentGoal.self, cp, "ExperimentGoal")
        let experiments = ExperimentListParams(
            project: "p", runtime: "rg", environment: .staging, status: .running, limit: 1, next: "cursor")
        await filters("experiment list filters: GET /v1/experiments", cp, "GET", "/v1/experiments", missingIsFatal: true) {
            _ = try await $0.experiments.list(experiments).firstPage()
        }
    }

    // MARK: Connectors and connections

    private func checkConnectors(_ cp: OpenAPIReference) async throws {
        try readModel("Connector: the connector read model", Connector.self, cp, "ConnectorResponse")
        let create = ConnectorCreate(
            name: "n", provider: "github", authMode: .oauthStored, slug: "gh", environment: .staging, agentMemberId: "m1",
            authorizationEndpoint: "https://a", tokenEndpoint: "https://t", scopes: ["repo"], apiHosts: ["api.github.com"],
            clientId: "cid", clientSecret: "cs", signingSecret: "ss", metadata: object, issuer: "https://i",
            personServerMode: .managed, personServerUrl: "https://p", approvalPolicy: .human, applicationId: "app",
            assertionAudience: "aud", webhookUrl: "https://w")
        try body("ConnectorCreate: POST /v1/connectors body", create, cp, "ConnectorCreate")
        let update = ConnectorUpdate(
            name: "n", agentMemberId: "m1", scopes: ["repo"], apiHosts: ["api.github.com"], status: .active, metadata: object,
            webhookUrl: "https://w", clientSecret: "cs", signingSecret: "ss")
        try body("ConnectorUpdate: PATCH /v1/connectors/{id} body", update, cp, "ConnectorUpdate")
        await filters("connector list filters: GET /v1/connectors", cp, "GET", "/v1/connectors", missingIsFatal: true) {
            _ = try await $0.connectors.list(ConnectorListParams(project: "p", limit: 1, next: "cursor")).firstPage()
        }
        await filters(
            "connector app filters: GET /v1/connectors/{id}/apps", cp, "GET", "/v1/connectors/{connector_id}/apps", missingIsFatal: true
        ) {
            _ = try await $0.connectors.listApps("cn", query: "q", limit: 1, project: "p")
        }
        await filters("custom app search: GET /v1/connectors/custom/apps", cp, "GET", "/v1/connectors/custom/apps", missingIsFatal: true) {
            _ = try await $0.connectors.searchCustomApps(query: "q", limit: 1)
        }
        let discover = await sentBody { _ = try await $0.connectors.discoverOAuth(issuer: "https://i", project: "p") }
        compare(
            "ConnectorOAuthDiscoveryRequest: POST /v1/connectors/discover-oauth body", .body, sdk: discover,
            reference: cp.properties("ConnectorOAuthDiscoveryRequest"))
        try readModel(
            "ConnectorOAuthDiscovery: POST /v1/connectors/discover-oauth response", ConnectorOAuthDiscovery.self, cp,
            "ConnectorOAuthDiscoveryResponse")

        let binding = ConnectorAuthorizeBinding(environment: .staging, mcpServerId: "mcp", url: "https://m", name: "n", headers: ["h": "v"])
        let authorize = ConnectorAuthorizeParams(
            app: "app", allowProgressiveScopes: true, identity: RunnerIdentity(userId: "u1"), runtime: "rg", binding: binding,
            subject: .user, returnUrl: "https://r", expiresIn: 600)
        try body(
            "ConnectorAuthorizeParams: POST /v1/oauth/connections/authorize body",
            ConnectorAuthorizeBody(connectorId: "cn", params: authorize), cp, "ConnectAuthorizeRequest")
        try body("ConnectorAuthorizeBinding: ConnectAuthorizeRequest.binding", binding, cp, "ConnectBindingRequest")
        try readModel(
            "ConnectorAuthorization: POST /v1/oauth/connections/authorize response", ConnectorAuthorization.self, cp,
            "ConnectAuthorizeResponse")

        try readModel("Connection: the connection read model", Connection.self, cp, "ConnectionResponse")
        let connection = ConnectionCreate(
            accessToken: "at", subjectType: .app, scopesGranted: ["repo"], refreshToken: "rt", tokenExpiresAt: date)
        try body("ConnectionCreate: POST /v1/connectors/{id}/connections body", connection, cp, "ConnectionCreate")
        await filters(
            "connection list filters: GET /v1/connectors/{id}/connections", cp, "GET", "/v1/connectors/{connector_id}/connections",
            missingIsFatal: true
        ) { _ = try await $0.connectors.connections.list("cn", ConnectionListParams(limit: 1, next: "cursor")).firstPage() }
        let constraints = ConnectionMissionConstraints(
            host: "api.github.com", resource: "repo", limits: object, windowStart: date, windowEnd: date, payloadBinding: "sha256")
        let token = ConnectionTokenParams(connectionId: "cx", subject: .user, action: "push", requestedPermissions: constraints)
        try body(
            "ConnectionTokenParams: POST /v1/oauth/connections/token body", ConnectionTokenBody(connectorId: "cn", params: token), cp,
            "BrokerTokenRequest")
        try body("ConnectionMissionConstraints: BrokerTokenRequest.requested_permissions", constraints, cp, "MissionConstraints")
        // The `authorization_pending` 202 is not declared by the reference; its 200 is.
        try readModel("ConnectionToken: POST /v1/oauth/connections/token response", ConnectionToken.self, cp, "BrokerTokenResponse")
    }

    // MARK: Organization, projects, members, recipes, repositories

    private func checkOrganization(_ cp: OpenAPIReference) async throws {
        try readModel("Organization: GET /v1/organizations/current", Organization.self, cp, "OrganizationResponse")
        try readModel("Project: the project read model", Project.self, cp, "ProjectResponse")
        await filters("project list filters: GET /v1/projects", cp, "GET", "/v1/projects", missingIsFatal: true) {
            _ = try await $0.projects.list(ProjectListParams(project: "p", limit: 1, next: "cursor")).firstPage()
        }
        // Member metadata is sent before the server publishes it (introspection-cloud#3144); the stale check flags it once it does.
        try readModel("Member: the member read model", Member.self, cp, "Member", sdkOnly: ["metadata"])
        try readModel("CurrentMember: GET /v1/oidc/me", CurrentMember.self, cp, "OIDCMeResponse")
        let members = MemberListParams(
            memberType: .customer, connectorId: "cn", applicationIdpId: "idp", tag: "a:b", metadata: ["plan": "enterprise"],
            ids: ["m1"], externalUserIds: ["u1"], project: "p", limit: 1, next: "cursor")
        await filters("member list filters: GET /v1/members", cp, "GET", "/v1/members", sdkOnly: ["metadata"], missingIsFatal: true) {
            _ = try await $0.members.list(members).firstPage()
        }
        // The invite route reads only these; the rest of the shared member schema is ignored on create.
        try body(
            "MemberCreate: POST /v1/members body",
            MemberCreate(email: "a@example.com", name: "Ana Lopez", role: "member", tags: ["a:b"], metadata: ["plan": "enterprise"]),
            cp, "MemberCreate",
            exempt: [
                "external_user_id", "image_url", "member_type", "is_deactivated", "application_idp_id", "connector_id", "integration_id",
            ],
            sdkOnly: ["metadata"])
        try body(
            "MemberUpdate: PATCH /v1/members/{id} body",
            MemberUpdate(
                name: "Ana Lopez", imageUrl: "https://example.com/a.png", role: "admin", tags: ["a:b"], metadata: ["plan": "team"]),
            cp, "MemberUpdate", sdkOnly: ["metadata"])
        await filters("member read options: GET /v1/members/{id}", cp, "GET", "/v1/members/{member_id}", missingIsFatal: true) {
            _ = try await $0.members.get("m1", project: "p")
        }

        try readModel("Recipe: the recipe read model", Recipe.self, cp, "Recipe")
        try readModel("RecipeValidation: Recipe.validation", RecipeValidation.self, cp, "RecipeValidation")
        try readModel("RecipeValidationDiagnostic", RecipeValidationDiagnostic.self, cp, "RecipeValidationDiagnostic")
        try readModel("RecipeMcpServer: Recipe.mcp_servers[]", RecipeMcpServer.self, cp, "RecipeMcpServer")
        try readModel("RecipeMcpServer.Tools", RecipeMcpServer.Tools.self, cp, "RecipeMcpTools")
        await filters("recipe list filters: GET /v1/recipes", cp, "GET", "/v1/recipes", missingIsFatal: true) {
            _ = try await $0.recipes.list(RecipeListParams(project: "p", name: "n", repositoryId: "r1", limit: 1, next: "cursor"))
                .firstPage()
        }

        try readModel("Repository: the repository read model", Repository.self, cp, "RepositoryResponse")
        await filters("repository list filters: GET /v1/repositories", cp, "GET", "/v1/repositories", missingIsFatal: true) {
            _ = try await $0.repositories.list(project: "p", slug: "acme/app")
        }
    }

    // MARK: Auth

    private func checkAuth(_ cp: OpenAPIReference) async throws {
        // `OAuthToken` also decodes third-party OIDC token responses (`OIDC.exchangeCode`), where `id_token` is the point.
        try readModel("OAuthToken: POST /v1/oauth/token response", OAuthToken.self, cp, "OAuthTokenResponse", sdkOnly: ["id_token"])
        try readModel("DeviceAuthorization: POST /v1/oauth/device/code response", DeviceAuthorization.self, cp, "DeviceCodeResponse")
        let token = DataPlaneTokenRequest(
            project: "p", expiresHours: 1, expiresMinutes: 30, includeRefreshToken: true, environment: "staging")
        try body("DataPlaneTokenRequest: POST /v1/tokens body", token, cp, "TokenRequest")
        try readModel("DataPlaneToken: POST /v1/tokens response", DataPlaneToken.self, cp, "TokenResponse")

        // Every grant this SDK sends, together: the token endpoint takes one form for all of them.
        let grants = await sentForm { client in
            let auth = client.auth
            _ = try? await auth.clientCredentials(clientId: "c", clientSecret: "s", project: "p", scope: "*")
            _ = try? await auth.tokenExchange(subjectToken: "t", clientId: "c", project: "p", scope: "*")
            _ = try? await auth.jwtBearer(assertion: "a", clientId: "c", project: "p", resource: "r")
            _ = try? await auth.authorizationCode(code: "c", clientId: "c", redirectURI: "https://r", codeVerifier: "v")
            _ = try? await auth.refresh(refreshToken: "r", clientId: "c", sessionId: "s", orgId: "o")
            _ = try? await auth.deviceToken(deviceCode: "d")
        }
        compare(
            "OAuth grants: POST /v1/oauth/token form", .body, sdk: grants, reference: cp.properties("Body_oauth_token_v1_oauth_token_post"))
        let device = await sentForm { _ = try await $0.auth.deviceAuthorization(project: "p", capabilities: ["tasks"]) }
        compare(
            "device authorization: POST /v1/oauth/device/code form", .body, sdk: device,
            reference: cp.properties("Body_oauth_device_code_v1_oauth_device_code_post"))
        let revoke = await sentForm { try await $0.auth.revoke(sessionId: "s", orgId: "o") }
        compare(
            "session revoke: POST /v1/oauth/revoke form", .body, sdk: revoke,
            reference: cp.properties("Body_oauth_revoke_v1_oauth_revoke_post"))

        let authorize = AuthAPI(controlPlaneURL: URL(string: "https://cp.test")!).authorizeURL(
            clientID: "c", redirectURI: "https://r", project: "p", state: "s", codeChallenge: "x")
        let sent = Set(URLComponents(url: authorize, resolvingAgainstBaseURL: false)?.queryItems?.map(\.name) ?? [])
        compare(
            "hosted login: GET /v1/oauth/authorize query parameters", .filters, sdk: sent,
            reference: cp.queryParameters("GET", "/v1/oauth/authorize"))
    }

    /// The form fields of every request `call` sends.
    private func sentForm(_ call: (IntrospectionClient) async throws -> Void) async -> Set<String> {
        let transport = MockTransport { _, _ in
            .response(.json(#"{"access_token":"t","device_code":"d","user_code":"u","verification_uri":"v","expires_in":1}"#))
        }
        _ = try? await call(makeClient(transport))
        let pairs = transport.requests.flatMap { $0.bodyString.split(separator: "&") }
        return Set(pairs.compactMap { $0.split(separator: "=", maxSplits: 1).first.map(String.init) })
    }
}

/// What one comparison run found, accumulated across the checks.
private final class Drift {
    var problems: [String] = []
    var notes: [String] = []
    var surfaces = 0
}
