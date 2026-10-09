import Foundation
import Testing

@testable import IntrospectionSDK

private let connectionJSON = #"""
    {"id": "0199a000-0000-7000-8000-0000000000c1", "member_id": "m-1", "app": "gmail", "account_name": "ada@example.com",
     "healthy": true, "created_at": "2026-10-06T12:00:00Z"}
    """#

private func runner(_ transport: MockTransport, runtimeGroupId: String? = "rg-1") throws -> Runner {
    let spec = RunnerSpec(
        sessionId: "s-1", deployment: RunnerDeployment(endpoint: "https://dp-runner.test"), sessionToken: "session-token",
        runtimeContext: RunnerContext(runtimeId: "rt-1", runtimeGroupId: runtimeGroupId))
    return try Runner(spec: spec, transport: transport)
}

@Suite struct AppConnectionsTests {
    @Test func listDecodesAPageOfConnections() async throws {
        let transport = MockTransport(
            json: #"""
                {"records": [\#(connectionJSON),
                  {"id": "c2", "member_id": "m-1", "app": "slack", "account_name": null, "healthy": false,
                   "created_at": "2026-10-06T12:00:00Z"}], "count": 2, "next": "n2"}
                """#)
        let page = try await runner(transport).connections.list().firstPage()

        #expect(transport.last?.request.method == "GET")
        #expect(transport.last?.request.url.absoluteString == "https://dp-runner.test/v1/connections")
        #expect(transport.last?.request.headers["Authorization"] == "Bearer session-token")
        let created = Date(timeIntervalSince1970: 1_791_288_000)
        #expect(
            page.records == [
                AppConnection(
                    id: "0199a000-0000-7000-8000-0000000000c1", memberId: "m-1", app: "gmail", healthy: true, createdAt: created,
                    accountName: "ada@example.com"),
                AppConnection(id: "c2", memberId: "m-1", app: "slack", healthy: false, createdAt: created),
            ])
        #expect(page.next == "n2")
    }

    @Test func listSendsItsFilters() async throws {
        let transport = MockTransport(json: #"{"records": [], "count": 0}"#)
        _ = try await makeClient(transport).connections.list(memberId: "m-2", app: "gmail", limit: 10, next: "c1").firstPage()
        let query = try #require(transport.last?.query)
        #expect(transport.last?.path == "/v1/connections")
        #expect(query == ["member_id": ["m-2"], "app": ["gmail"], "limit": ["10"], "next": ["c1"]])
    }

    @Test func createOnARunnerSendsItsRuntimeGroup() async throws {
        let transport = MockTransport(
            status: 201,
            json: #"""
                {"authorize_url": "https://pipedream.com/_static/connect.html?token=ctok_1&app=gmail", "expires_in": 600,
                 "expires_at": "2026-10-06T12:10:00Z"}
                """#)
        let page = try await runner(transport).connections.create(app: "gmail")

        #expect(transport.last?.request.method == "POST")
        #expect(transport.last?.path == "/v1/connections")
        #expect(transport.last?.request.headers["Content-Type"] == "application/json")
        #expect(transport.last?.json == ["app": "gmail", "runtime": "rg-1"])
        #expect(page.authorizeUrl == "https://pipedream.com/_static/connect.html?token=ctok_1&app=gmail")
        #expect(page.expiresIn == 600)
        #expect(page.expiresAt == Date(timeIntervalSince1970: 1_791_288_600))
    }

    @Test func anExplicitRuntimeWinsOverTheRunners() async throws {
        let transport = MockTransport(json: #"{"authorize_url": "https://connect.test/p", "expires_in": 600, "expires_at": null}"#)
        let page = try await runner(transport).connections.create(app: "gmail", runtime: "ark")
        #expect(transport.last?.json == ["app": "gmail", "runtime": "ark"])
        #expect(page == ConnectPage(authorizeUrl: "https://connect.test/p", expiresIn: 600))
    }

    @Test func createOnTheClientTakesTheRuntime() async throws {
        let transport = MockTransport(json: #"{"authorize_url": "https://connect.test/p", "expires_in": 600}"#)
        _ = try await makeClient(transport).connections.create(app: "gmail", runtime: "ark")
        #expect(transport.last?.request.url.absoluteString == "https://dp.test/v1/connections")
        #expect(transport.last?.json == ["app": "gmail", "runtime": "ark"])
    }

    @Test func createSendsTheAppsReturnLink() async throws {
        let transport = MockTransport(json: #"{"authorize_url": "https://connect.test/p", "expires_in": 600}"#)
        _ = try await makeClient(transport).connections.create(
            app: "gmail", runtime: "ark", returnURL: URL(string: "ark://connected"))
        #expect(transport.last?.json == ["app": "gmail", "runtime": "ark", "return_url": "ark://connected"])
    }

    @Test(arguments: [false, true])
    func createWithoutAnyRuntimeFailsBeforeSending(onRunner: Bool) async throws {
        let transport = MockTransport(json: "{}")
        let connections = onRunner ? try runner(transport, runtimeGroupId: nil).connections : makeClient(transport).connections
        let error = try await #require(throws: IntrospectionError.self) {
            try await connections.create(app: "gmail")
        }
        #expect(error.kind == .invalidRequest)
        #expect(transport.requests.isEmpty)
    }

    @Test func getReadsOneConnection() async throws {
        let transport = MockTransport(json: connectionJSON)
        let connection = try await runner(transport).connections.get("0199a000-0000-7000-8000-0000000000c1")
        #expect(transport.last?.request.method == "GET")
        #expect(transport.last?.path == "/v1/connections/0199a000-0000-7000-8000-0000000000c1")
        #expect(connection.app == "gmail")
        #expect(connection.accountName == "ada@example.com")
    }

    @Test func deleteRemovesOneConnectionById() async throws {
        let transport = MockTransport { _, _ in .response(HTTPResponse(status: 204, headers: [:], body: Data())) }
        try await makeClient(transport).connections.delete("a/b")
        #expect(transport.last?.request.method == "DELETE")
        #expect(transport.last?.request.url.absoluteString == "https://dp.test/v1/connections/a%2Fb")
        #expect(transport.last?.request.body == nil)
    }

    @Test func aCredentialWithoutTheScopeIsForbidden() async throws {
        let transport = MockTransport(status: 403, json: #"{"detail": "Missing scope connections:read"}"#)
        let error = try await #require(throws: IntrospectionError.self) {
            try await runner(transport).connections.get("c1")
        }
        #expect(error.kind == .forbidden)
    }
}
