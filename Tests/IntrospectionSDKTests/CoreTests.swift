import Foundation
import Testing

@testable import IntrospectionSDK

@Suite struct CoreTests {
    @Test func jsonValueRoundTripKeepsKeys() throws {
        let value: JSONValue = ["workspace_id": "w1", "count": 3, "nested": ["a_b": true, "list": [1, "x", nil]]]
        let data = try JSONCoding.encoder.encode(value)
        let decoded = try JSONCoding.decoder.decode(JSONValue.self, from: data)
        #expect(decoded == value)
        #expect(decoded["workspace_id"]?.stringValue == "w1")
        #expect(decoded["nested"]?["a_b"]?.boolValue == true)
    }

    @Test func iso8601Shapes() {
        #expect(ISO8601.parse("2026-10-03T12:00:00Z") != nil)
        #expect(ISO8601.parse("2026-10-03T12:00:00.123456Z") != nil)
        #expect(ISO8601.parse("2026-10-03T12:00:00.1+02:00") != nil)
        #expect(ISO8601.parse("2026-10-03T12:00:00") != nil)
        #expect(ISO8601.parse("2026-10-03 12:00:00.5") != nil)
        #expect(ISO8601.parse("2026-10-03T12:00:00.500Z") == ISO8601.parse("2026-10-03T12:00:00.5Z"))
    }

    @Test func errorMapping() {
        let body = Data(#"{"detail":[{"loc":["body","name"],"msg":"field required"}],"code":"invalid_request"}"#.utf8)
        let error = IntrospectionError.fromResponse(status: 422, headers: ["x-request-id": "r1"], body: body)
        #expect(error.kind == .validation)
        #expect(error.message == "body.name: field required")
        #expect(error.requestId == "r1")
        let scope = IntrospectionError.fromResponse(
            status: 403, headers: [:], body: Data(#"{"detail":"no","code":"insufficient_scope","missing_capability":"tasks:write"}"#.utf8)
        )
        #expect(scope.kind == .insufficientScope(missingCapability: "tasks:write"))
        #expect(
            IntrospectionError.fromResponse(status: 401, headers: [:], body: Data(#"{"code":"runner_expired"}"#.utf8)).kind
                == .runnerExpired)
        #expect(IntrospectionError.parseRetryAfter("3") == 3)
        #expect(IntrospectionError.parseRetryAfter("-2") == 0)
        #expect(IntrospectionError.parseRetryAfter("Wed, 21 Oct 2099 07:28:00 GMT") != nil)
    }

    @Test func retriesRateLimitThenSucceeds() async throws {
        let transport = MockTransport { _, index in
            index == 0
                ? .response(.json(#"{"detail":"slow down"}"#, status: 429, headers: ["retry-after": "0"]))
                : .response(.json(#"{"ok":true}"#))
        }
        let client = makeClient(transport)
        let value = try await client.dataPlane.json("POST", "/v1/x", body: .json(Data("{}".utf8)), as: JSONValue.self)
        #expect(value["ok"]?.boolValue == true)
        #expect(transport.requests.count == 2)
    }

    @Test func doesNotRetryPostOn503() async throws {
        let transport = MockTransport { _, _ in .response(.json(#"{"detail":"down"}"#, status: 503)) }
        let client = makeClient(transport)
        let error = try await #require(throws: IntrospectionError.self) {
            try await client.dataPlane.json("POST", "/v1/x", as: JSONValue.self)
        }
        #expect(error.kind == .unavailable)
        #expect(transport.requests.count == 1)
    }

    @Test func refreshOn401RetriesOnce() async throws {
        actor Counter: CredentialProvider {
            var token = "old"
            func authorization() async throws -> String? { "Bearer \(token)" }
            func refreshAfterUnauthorized(rejected _: String?) async throws -> Bool { token = "new"; return true }
        }
        let transport = MockTransport { request, _ in
            request.headers["Authorization"] == "Bearer new" ? .response(.json("{}")) : .response(.json("{}", status: 401))
        }
        let http = HTTPClient(baseURL: URL(string: "https://dp.test")!, credentials: Counter(), transport: transport)
        _ = try await http.json("GET", "/v1/tasks/1", as: JSONValue.self)
        #expect(transport.requests.count == 2)
    }

    @Test func userAgentNamesThisLibraryAndTheReleasePleaseVersion() throws {
        let versionFile = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("version.txt")
        let release = try String(contentsOf: versionFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(IntrospectionSDK.userAgent == "introspection-swift-sdk/\(release)")
    }

    @Test func everyRequestCarriesTheSDKUserAgentUnlessOverridden() async throws {
        let transport = MockTransport { _, _ in .response(.json("{}")) }
        _ = try await HTTPClient(baseURL: URL(string: "https://dp.test")!, transport: transport).json("GET", "/v1/x", as: JSONValue.self)
        #expect(transport.last?.request.headers["User-Agent"] == "introspection-swift-sdk/\(IntrospectionSDK.version)")

        let custom = HTTPClient(
            baseURL: URL(string: "https://dp.test")!, transport: transport,
            options: .init(additionalHeaders: ["user-agent": "ark/1.0"]))
        _ = try await custom.json("GET", "/v1/x", as: JSONValue.self)
        #expect(transport.last?.request.headers["user-agent"] == "ark/1.0")
        #expect(transport.last?.request.headers["User-Agent"] == nil)
    }

    @Test func paginatorWalksCursorsAndStopsOnRepeat() async throws {
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
        #expect(items == [1, 2, 3])
    }

    @Test func urlEncodingOfPathAndQuery() {
        let http = HTTPClient(baseURL: URL(string: "https://dp.test/base/")!)
        var query = Query()
        query.add("name_contains", "a b&c")
        query.add("tag", ["x", "y"])
        let url = http.url("/v1/files/\(pathSegment("a/b"))", query: query)
        #expect(url.absoluteString == "https://dp.test/base/v1/files/a%2Fb?name_contains=a%20b%26c&tag=x&tag=y")
    }

    @Test func sseParser() {
        var parser = SSEParser()
        var frames = parser.push(Data("id: 1\nevent: ag_ui\ndata: {\"a\":1}\n".utf8))
        #expect(frames.isEmpty)
        frames = parser.push(Data("\r\n: comment\n\nevent: heartbeat\ndata:\n\ndata: a\ndata: b\n\nevent: partial\n".utf8))
        #expect(
            frames == [
                SSEFrame(event: "ag_ui", data: "{\"a\":1}", id: "1"),
                SSEFrame(event: "heartbeat", data: ""),
                SSEFrame(event: "message", data: "a\nb"),
            ])
    }

    @Test func multipartAndForm() {
        var form = MultipartFormData(boundary: "B")
        form.append(name: "name", value: "x")
        form.append(name: "file", filename: "a.txt", contentType: "text/plain", data: Data("hi".utf8))
        #expect(
            String(decoding: form.data, as: UTF8.self)
                == "--B\r\nContent-Disposition: form-data; name=\"name\"\r\n\r\nx\r\n--B\r\nContent-Disposition: form-data; name=\"file\"; filename=\"a.txt\"\r\nContent-Type: text/plain\r\n\r\nhi\r\n--B--\r\n"
        )
        let (body, type) = RequestBody.form([("grant_type", "refresh_token"), ("a", "b c+")]).encoded()
        #expect(type == "application/x-www-form-urlencoded")
        #expect(String(decoding: body!, as: UTF8.self) == "grant_type=refresh_token&a=b+c%2B")
    }
}
