import Foundation
import Testing

@testable import IntrospectionSDK

/// Fails to compile if either type stops exposing a namespace `DataPlaneResources` declares.
private func requireResources<T: DataPlaneResources>(_: T.Type) {}

/// One call per namespace, through the shared protocol only. Returns "METHOD path" for each request sent.
private func driveEveryNamespace(_ resources: some DataPlaneResources, _ transport: MockTransport) async -> [String] {
    let date = Date(timeIntervalSince1970: 1_790_000_000)
    _ = try? await resources.tasks.get("t1")
    _ = try? await resources.tasks.runs.get("t1", "r1")
    _ = try? await resources.files.get("f1")
    _ = try? await resources.conversations.get("c1")
    _ = try? await resources.events.get("e1")
    _ = try? await resources.metrics.query(MetricQueryRequest(view: .spans, metrics: [.count], from: date, to: date))
    _ = try? await resources.shares.get("s1")
    _ = try? await resources.automations.get("a1")
    _ = try? await resources.connections.get("c1")
    return transport.requests.map { "\($0.request.method) \($0.path)" }
}

private let everyNamespace = [
    "GET /v1/tasks/t1", "GET /v1/tasks/t1/runs/r1", "GET /v1/files/f1", "GET /v1/conversations/c1", "GET /v1/events/e1",
    "POST /v1/metrics", "GET /v1/shares/s1", "GET /v1/automations/a1",
    "GET /v1/connections/c1",
]

@Suite struct DataPlaneResourcesTests {
    @Test func theClientAndTheRunnerConform() {
        requireResources(IntrospectionClient.self)
        requireResources(Runner.self)
    }

    @Test func theClientReachesEveryNamespaceWithItsDataPlaneCredential() async throws {
        let transport = MockTransport(json: "{}")
        let sent = await driveEveryNamespace(makeClient(transport), transport)
        #expect(sent == everyNamespace)
        #expect(transport.requests.allSatisfy { $0.request.url.host == "dp.test" })
        #expect(transport.requests.allSatisfy { $0.request.headers["Authorization"] == "Bearer dp-token" })
    }

    @Test func theRunnerReachesEveryNamespaceWithItsSessionToken() async throws {
        let transport = MockTransport(json: "{}")
        let spec = RunnerSpec(
            sessionId: "s-1", deployment: RunnerDeployment(endpoint: "https://dp-runner.test"), sessionToken: "session-token",
        )
        let sent = await driveEveryNamespace(try Runner(spec: spec, transport: transport), transport)
        #expect(sent == everyNamespace)
        #expect(transport.requests.allSatisfy { $0.request.url.host == "dp-runner.test" })
        #expect(transport.requests.allSatisfy { $0.request.headers["Authorization"] == "Bearer session-token" })
    }

    @Test func theRunnerExposesAutomations() async throws {
        let transport = MockTransport(json: #"{"records": [], "count": 0}"#)
        let runner = try Runner(
            spec: RunnerSpec(sessionId: "s", deployment: RunnerDeployment(endpoint: "https://dp-runner.test"), sessionToken: "tok"),
            transport: transport)
        _ = try await runner.automations.list(AutomationListParams(taskId: "t1")).firstPage()
        #expect(transport.last?.request.url.absoluteString == "https://dp-runner.test/v1/automations?task_id=t1")
        #expect(transport.last?.request.headers["Authorization"] == "Bearer tok")
    }
}
