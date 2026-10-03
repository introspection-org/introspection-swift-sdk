import Foundation
import XCTest
@testable import IntrospectionSDK

final class FederatedTests: XCTestCase {
    private actor Counter {
        var value = 0
        func next() -> Int { value += 1; return value }
    }

    func testFederatedClientExchangesOnceAndUsesReturnedDataPlane() async throws {
        let transport = MockTransport { request, _ in
            if request.url.path == "/v1/oauth/token" {
                return .response(.json(#"{"access_token":"dp-token","token_type":"Bearer","expires_in":3600,"dp_url":"https://dp.example"}"#))
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

        XCTAssertEqual(transport.requests.count, 2)
        let exchange = transport.requests[0].bodyString
        XCTAssertTrue(exchange.contains("grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Atoken-exchange"))
        XCTAssertTrue(exchange.contains("subject_token=supabase-1"))
        XCTAssertTrue(exchange.contains("client_id=intro_app_x"))
        XCTAssertTrue(exchange.contains("project=ark"))
        XCTAssertEqual(transport.requests[1].request.url.host, "dp.example")
        XCTAssertEqual(transport.requests[1].request.headers["Authorization"], "Bearer dp-token")
    }

    func testRejectedSubjectTokenSurfacesAsAuthentication() async {
        let transport = MockTransport { _, _ in .response(.json(#"{"detail":"Invalid subject_token"}"#, status: 401)) }
        do {
            _ = try await IntrospectionClient.federated(
                subjectToken: { "bad" }, clientID: "intro_app_x", project: "ark",
                controlPlaneURL: URL(string: "https://cp.test")!, transport: transport
            )
            XCTFail("expected failure")
        } catch let error as IntrospectionError {
            XCTAssertEqual(error.kind, .authentication)
            XCTAssertTrue(error.message.contains("Invalid subject_token"))
        } catch {
            XCTFail("\(error)")
        }
    }

    func testMissingDataPlaneURLIsAnError() async {
        let transport = MockTransport { _, _ in .response(.json(#"{"access_token":"t","expires_in":3600}"#)) }
        do {
            _ = try await IntrospectionClient.federated(
                subjectToken: { "s" }, clientID: "c", project: "p",
                controlPlaneURL: URL(string: "https://cp.test")!, transport: transport
            )
            XCTFail("expected failure")
        } catch let error as IntrospectionError {
            XCTAssertEqual(error.kind, .invalidRequest)
        } catch {
            XCTFail("\(error)")
        }
    }
}
