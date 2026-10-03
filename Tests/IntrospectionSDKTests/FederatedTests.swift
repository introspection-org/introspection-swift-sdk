import Foundation
import Testing

@testable import IntrospectionSDK

@Suite struct FederatedTests {
    private actor Counter {
        var value = 0
        func next() -> Int { value += 1; return value }
    }

    @Test func federatedClientExchangesOnceAndUsesReturnedDataPlane() async throws {
        let transport = MockTransport { request, _ in
            if request.url.path == "/v1/oauth/token" {
                return .response(
                    .json(#"{"access_token":"dp-token","token_type":"Bearer","expires_in":3600,"dp_url":"https://dp.example"}"#))
            }
            return .response(.json(#"{"records":[],"count":0}"#))
        }
        let issued = Counter()
        let client = try await IntrospectionClient.federated(
            subjectToken: { "supabase-\(await issued.next())" },
            clientID: "intro_app_x",
            project: "ark",
            controlPlaneURL: URL(string: "https://cp.test")!,
            transport: transport
        )
        _ = try await client.tasks.list().firstPage()

        #expect(transport.requests.count == 2)
        let exchange = transport.requests[0].bodyString
        #expect(exchange.contains("grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Atoken-exchange"))
        #expect(exchange.contains("subject_token=supabase-1"))
        #expect(exchange.contains("client_id=intro_app_x"))
        #expect(exchange.contains("project=ark"))
        #expect(transport.requests[1].request.url.host == "dp.example")
        #expect(transport.requests[1].request.headers["Authorization"] == "Bearer dp-token")
    }

    @Test func rejectedSubjectTokenSurfacesAsAuthentication() async throws {
        let transport = MockTransport { _, _ in .response(.json(#"{"detail":"Invalid subject_token"}"#, status: 401)) }
        let error = try await #require(throws: IntrospectionError.self) {
            try await IntrospectionClient.federated(
                subjectToken: { "bad" }, clientID: "intro_app_x", project: "ark",
                controlPlaneURL: URL(string: "https://cp.test")!, transport: transport
            )
        }
        #expect(error.kind == .authentication)
        #expect(error.message.contains("Invalid subject_token"))
    }

    @Test func missingDataPlaneURLIsAnError() async throws {
        let transport = MockTransport { _, _ in .response(.json(#"{"access_token":"t","expires_in":3600}"#)) }
        let error = try await #require(throws: IntrospectionError.self) {
            try await IntrospectionClient.federated(
                subjectToken: { "s" }, clientID: "c", project: "p",
                controlPlaneURL: URL(string: "https://cp.test")!, transport: transport
            )
        }
        #expect(error.kind == .invalidRequest)
    }
}
