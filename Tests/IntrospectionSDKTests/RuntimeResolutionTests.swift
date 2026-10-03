import Foundation
import XCTest

@testable import IntrospectionSDK

final class RuntimeResolutionTests: XCTestCase {
    func testResolvesTheFirstReadyRuntimeThroughTheDataPlane() async throws {
        let transport = MockTransport { _, _ in
            .response(
                .json(
                    #"{"jsonrpc":"2.0","id":1,"result":{"content":[],"structuredContent":{"runtimes":["#
                        + #"{"runtime_id":"r-new","runtime_name":"ark","image_build_status":"building"},"#
                        + #"{"runtime_id":"r-ready","runtime_name":"ark","image_build_status":"ready"}]}}}"#))
        }
        let client = makeClient(transport)
        let runtimeId = try await client.resolveRuntimeId("ark")

        XCTAssertEqual(runtimeId, "r-ready")
        let request = try XCTUnwrap(transport.last)
        XCTAssertEqual(request.request.url.host, "dp.test")
        XCTAssertEqual(request.path, "/v1/mcp")
        XCTAssertEqual(request.json?["method"], "tools/call")
        XCTAssertEqual(request.json?["params"]?["name"], "list_runtimes")
        XCTAssertEqual(request.json?["params"]?["arguments"]?["runtime"], "ark")
    }

    func testFallsBackToTheFirstRuntimeAndReportsNoneWhenEmpty() async throws {
        let rows = MockTransport { _, index in
            index == 0
                ? .response(
                    .json(
                        #"{"jsonrpc":"2.0","id":1,"result":{"structuredContent":{"runtimes":[{"runtime_id":"r1","image_build_status":"pending"}]}}}"#
                    ))
                : .response(.json(#"{"jsonrpc":"2.0","id":1,"result":{"structuredContent":{"runtimes":[]}}}"#))
        }
        let client = makeClient(rows)
        let first = try await client.resolveRuntimeId("ark")
        let none = try await client.resolveRuntimeId("missing")
        XCTAssertEqual(first, "r1")
        XCTAssertNil(none)
    }

    func testJSONRPCErrorIsSurfaced() async {
        let transport = MockTransport { _, _ in
            .response(.json(#"{"jsonrpc":"2.0","id":1,"error":{"code":-32602,"message":"unknown tool"}}"#))
        }
        do {
            _ = try await makeClient(transport).listRuntimes("ark")
            XCTFail("expected failure")
        } catch let error as IntrospectionError {
            XCTAssertEqual(error.message, "unknown tool")
            XCTAssertEqual(error.code, "-32602")
        } catch {
            XCTFail("\(error)")
        }
    }
}
