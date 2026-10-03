import Foundation
import XCTest
@testable import IntrospectionSDK

final class CoreTests: XCTestCase {
    func testJSONValueRoundTripKeepsKeys() throws {
        let value: JSONValue = ["workspace_id": "w1", "count": 3, "nested": ["a_b": true, "list": [1, "x", nil]]]
        let data = try JSONCoding.encoder.encode(value)
        let decoded = try JSONCoding.decoder.decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded, value)
        XCTAssertEqual(decoded["workspace_id"]?.stringValue, "w1")
        XCTAssertEqual(decoded["nested"]?["a_b"]?.boolValue, true)
    }

    func testISO8601Shapes() {
        XCTAssertNotNil(ISO8601.parse("2026-10-03T12:00:00Z"))
        XCTAssertNotNil(ISO8601.parse("2026-10-03T12:00:00.123456Z"))
        XCTAssertNotNil(ISO8601.parse("2026-10-03T12:00:00.1+02:00"))
        XCTAssertNotNil(ISO8601.parse("2026-10-03T12:00:00"))
        XCTAssertNotNil(ISO8601.parse("2026-10-03 12:00:00.5"))
        XCTAssertEqual(
            ISO8601.parse("2026-10-03T12:00:00.500Z"),
            ISO8601.parse("2026-10-03T12:00:00.5Z")
        )
    }

    func testErrorMapping() {
        let body = Data(#"{"detail":[{"loc":["body","name"],"msg":"field required"}],"code":"invalid_request"}"#.utf8)
        let error = IntrospectionError.fromResponse(status: 422, headers: ["x-request-id": "r1"], body: body)
        XCTAssertEqual(error.kind, .validation)
        XCTAssertEqual(error.message, "body.name: field required")
        XCTAssertEqual(error.requestId, "r1")
        let scope = IntrospectionError.fromResponse(
            status: 403, headers: [:], body: Data(#"{"detail":"no","code":"insufficient_scope","missing_capability":"tasks:write"}"#.utf8)
        )
        XCTAssertEqual(scope.kind, .insufficientScope(missingCapability: "tasks:write"))
        XCTAssertEqual(IntrospectionError.fromResponse(status: 401, headers: [:], body: Data(#"{"code":"runner_expired"}"#.utf8)).kind, .runnerExpired)
        XCTAssertEqual(IntrospectionError.parseRetryAfter("3"), 3)
        XCTAssertEqual(IntrospectionError.parseRetryAfter("-2"), 0)
        XCTAssertNotNil(IntrospectionError.parseRetryAfter("Wed, 21 Oct 2099 07:28:00 GMT"))
    }

    func testRetriesRateLimitThenSucceeds() async throws {
        let transport = MockTransport { _, index in
            index == 0
                ? .response(.json(#"{"detail":"slow down"}"#, status: 429, headers: ["retry-after": "0"]))
                : .response(.json(#"{"ok":true}"#))
        }
        let client = makeClient(transport)
        let value = try await client.dataPlane.json("POST", "/v1/x", body: .json(Data("{}".utf8)), as: JSONValue.self)
        XCTAssertEqual(value["ok"]?.boolValue, true)
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testDoesNotRetryPostOn503() async {
        let transport = MockTransport { _, _ in .response(.json(#"{"detail":"down"}"#, status: 503)) }
        let client = makeClient(transport)
        do {
            _ = try await client.dataPlane.json("POST", "/v1/x", as: JSONValue.self)
            XCTFail("expected error")
        } catch let error as IntrospectionError {
            XCTAssertEqual(error.kind, .unavailable)
            XCTAssertEqual(transport.requests.count, 1)
        } catch { XCTFail("\(error)") }
    }

    func testRefreshOn401RetriesOnce() async throws {
        actor Counter: CredentialProvider {
            var token = "old"
            func authorization() async throws -> String? { "Bearer \(token)" }
            func refreshAfterUnauthorized() async throws -> Bool { token = "new"; return true }
        }
        let transport = MockTransport { request, _ in
            request.headers["Authorization"] == "Bearer new" ? .response(.json("{}")) : .response(.json("{}", status: 401))
        }
        let http = HTTPClient(baseURL: URL(string: "https://dp.test")!, credentials: Counter(), transport: transport)
        _ = try await http.json("GET", "/v1/tasks/1", as: JSONValue.self)
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testPaginatorWalksCursorsAndStopsOnRepeat() async throws {
        let transport = MockTransport { request, _ in
            let next = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "next" }?.value
            switch next {
            case nil: return .response(.json(#"{"records":[1,2],"count":2,"next":"c1"}"#))
            case "c1": return .response(.json(#"{"records":[3],"count":1,"next":"c1"}"#))
            default: return .response(.json(#"{"records":[],"count":0}"#))
            }
        }
        let client = makeClient(transport)
        let items = try await client.dataPlane.paginate("/v1/things", as: Int.self).collect()
        XCTAssertEqual(items, [1, 2, 3])
    }

    func testURLEncodingOfPathAndQuery() {
        let http = HTTPClient(baseURL: URL(string: "https://dp.test/base/")!)
        var query = Query()
        query.add("name_contains", "a b&c")
        query.add("tag", ["x", "y"])
        let url = http.url("/v1/files/\(pathSegment("a/b"))", query: query)
        XCTAssertEqual(url.absoluteString, "https://dp.test/base/v1/files/a%2Fb?name_contains=a%20b%26c&tag=x&tag=y")
    }

    func testSSEParser() {
        var parser = SSEParser()
        var frames = parser.push(Data("id: 1\nevent: ag_ui\ndata: {\"a\":1}\n".utf8))
        XCTAssertTrue(frames.isEmpty)
        frames = parser.push(Data("\r\n: comment\n\nevent: heartbeat\ndata:\n\ndata: a\ndata: b\n\nevent: partial\n".utf8))
        XCTAssertEqual(frames, [
            SSEFrame(event: "ag_ui", data: "{\"a\":1}", id: "1"),
            SSEFrame(event: "heartbeat", data: ""),
            SSEFrame(event: "message", data: "a\nb"),
        ])
    }

    func testMultipartAndForm() {
        var form = MultipartFormData(boundary: "B")
        form.append(name: "name", value: "x")
        form.append(name: "file", filename: "a.txt", contentType: "text/plain", data: Data("hi".utf8))
        XCTAssertEqual(
            String(decoding: form.data, as: UTF8.self),
            "--B\r\nContent-Disposition: form-data; name=\"name\"\r\n\r\nx\r\n--B\r\nContent-Disposition: form-data; name=\"file\"; filename=\"a.txt\"\r\nContent-Type: text/plain\r\n\r\nhi\r\n--B--\r\n"
        )
        let (body, type) = RequestBody.form([("grant_type", "refresh_token"), ("a", "b c+")]).encoded()
        XCTAssertEqual(type, "application/x-www-form-urlencoded")
        XCTAssertEqual(String(decoding: body!, as: UTF8.self), "grant_type=refresh_token&a=b+c%2B")
    }
}
