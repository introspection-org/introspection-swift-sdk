import Foundation
import Testing

@testable import IntrospectionSDK

@Suite struct RunStreamContractTests {
    struct Scenario: Decodable, Sendable {
        let name: String
        let streams: [String]
        let statuses: [String]
        let cursors: [String]
        let deltas: [String]
        let error: String?
        let textError: String?

        enum CodingKeys: String, CodingKey {
            case name, streams, statuses, cursors, deltas, error
            case textError = "text_error"
        }
    }

    static let scenarios: [Scenario] = {
        let url = Bundle.module.url(forResource: "run-stream-contract", withExtension: "json", subdirectory: "Fixtures")!
        return try! JSONDecoder().decode([Scenario].self, from: Data(contentsOf: url))
    }()

    @Test(arguments: scenarios) func sharedContract(_ scenario: Scenario) async throws {
        let transport = ContractTransport(scenario)
        let http = HTTPClient(
            baseURL: URL(string: "https://dp.test")!, credentials: BearerToken("fixture"), transport: transport)
        var events: [AGUIEvent] = []
        var failure: IntrospectionError?
        do {
            for try await event in RunStream.events(
                http: http, taskId: "t", runId: "run-1", options: .init(maxReconnects: 2, backoff: 0.001))
            {
                events.append(event)
            }
        } catch let error as IntrospectionError { failure = error }
        #expect(events.compactMap(\.delta) == scenario.deltas)
        #expect(failure?.kind == scenario.error.map { $0 == "run_failed" ? .runFailed : .streamIncomplete })
        #expect(await transport.cursors == scenario.cursors)
        #expect(await transport.reads == scenario.statuses.count)
        #expect(!events.contains { $0.raw["result"]?["reason"]?.stringValue == "stream_close" })
    }

    @Test(arguments: scenarios.filter { $0.textError != nil || $0.name == "text_chunk" })
    func textOutcome(_ scenario: Scenario) async throws {
        let transport = ContractTransport(scenario)
        let http = HTTPClient(baseURL: URL(string: "https://dp.test")!, credentials: BearerToken("fixture"), transport: transport)
        let handle = RunHandle(task: nil, run: TaskRun(id: "run-1", taskId: "t", status: .running), runs: TaskRunsAPI(http: http))
        if let expected = scenario.textError {
            let error = try await #require(throws: IntrospectionError.self) { try await handle.text() }
            #expect(error.kind == (expected == "run_failed" ? .runFailed : .streamIncomplete))
        } else {
            #expect(try await handle.text() == "chunk")
        }
    }
}

private actor ContractTransport: HTTPTransport {
    let scenario: RunStreamContractTests.Scenario
    var cursors: [String] = []
    var reads = 0
    init(_ scenario: RunStreamContractTests.Scenario) { self.scenario = scenario }

    func send(_ request: HTTPRequest) throws -> HTTPResponse {
        #expect(request.url.path == "/v1/tasks/t/runs/run-1")
        let status = scenario.statuses[min(reads, scenario.statuses.count - 1)]
        reads += 1
        return .json(#"{"id":"run-1","task_id":"t","status":"\#(status)"}"#)
    }

    func stream(_ request: HTTPRequest) -> HTTPStreamResponse {
        #expect(request.url.path == "/v1/tasks/t/runs/run-1/stream")
        let body = scenario.streams[min(cursors.count, scenario.streams.count - 1)]
        cursors.append(request.headers["Last-Event-ID"] ?? "missing")
        return HTTPStreamResponse(
            status: 200, headers: [:],
            bytes: AsyncThrowingStream {
                $0.yield(Data(body.utf8))
                $0.finish()
            })
    }
}
