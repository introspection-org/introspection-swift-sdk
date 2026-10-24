import Foundation
import Testing

@testable import IntrospectionSDK

@Suite struct HARTransportTests {
    private func entry(_ method: String, _ url: String, body: String? = nil, status: Int = 200, response: String = "{}") -> HAR.Entry {
        HAR.Entry(
            startedDateTime: "2026-10-23T20:56:54Z",
            request: HAR.Request(method: method, url: url, postData: body.map { HAR.PostData(mimeType: "application/json", text: $0) }),
            response: HAR.Response(status: status, content: HAR.Content(mimeType: "application/json", text: response)))
    }

    private func request(_ method: String, _ url: String, json: String? = nil) -> HTTPRequest {
        HTTPRequest(
            method: method, url: URL(string: url)!, headers: json == nil ? [:] : ["Content-Type": "application/json"],
            body: json.map { Data($0.utf8) })
    }

    @Test func identicalRequestsAnswerInRecordedOrder() async throws {
        let transport = HARTransport(
            replaying: HAR(
                log: HAR.Log(entries: [
                    entry("GET", "http://localhost:8002/v1/tasks/t", response: #"{"status":"running"}"#),
                    entry("GET", "http://localhost:8002/v1/tasks/t", response: #"{"status":"idle"}"#),
                ])))
        let first = try await transport.send(request("GET", "http://localhost:8002/v1/tasks/t"))
        let second = try await transport.send(request("GET", "http://localhost:8002/v1/tasks/t"))
        #expect(String(decoding: first.body, as: UTF8.self).contains("running"))
        #expect(String(decoding: second.body, as: UTF8.self).contains("idle"))
        #expect(transport.consumption == (2, 2))
        await #expect(throws: ReplayMiss.self) { try await transport.send(request("GET", "http://localhost:8002/v1/tasks/t")) }
    }

    @Test func bodiesMatchAsParsedJSONAndQueriesAsSets() async throws {
        let transport = HARTransport(
            replaying: HAR(
                log: HAR.Log(entries: [
                    entry(
                        "POST", "http://localhost:8002/v1/metrics?b=2&a=1",
                        body: #"{"from_timestamp":"2026-01-01T00:00:00Z","view":"conversations"}"#)
                ])))
        let response = try await transport.send(
            request(
                "POST", "http://localhost:8002/v1/metrics?a=1&b=2",
                json: #"{ "view": "conversations", "from_timestamp": "2026-01-01T00:00:00.000Z" }"#))
        #expect(response.status == 200)
        #expect(transport.unconsumed.isEmpty)
    }

    @Test func aChangedBodyFailsNamingTheDifference() async throws {
        let transport = HARTransport(
            replaying: HAR(
                log: HAR.Log(entries: [entry("POST", "http://localhost:8000/v1/recipes", body: #"{"name":"walk","git_ref":"main"}"#)])))
        let error = await #expect(throws: ReplayMiss.self) {
            try await transport.send(request("POST", "http://localhost:8000/v1/recipes", json: #"{"name":"walk","gitRef":"main"}"#))
        }
        let detail = error?.miss.detail ?? ""
        #expect(detail.contains(#"$.git_ref: recorded "main", not sent"#))
        #expect(detail.contains(#"$.gitRef: not recorded, sent "main""#))
        #expect(transport.misses.count == 1)
    }

    @Test func scrubbingRedactsCredentialsAsTheJSWalkDoes() {
        // Assembled, so no secret scanner mistakes the fixture for a leaked token.
        let jwtShaped = ["eyJhbGciOiJSUzI1NiJ9", "eyJzdWIiOiJ3YWxrIn0", "c2lnbmF0dXJlLXZhbHVl"].joined(separator: ".")
        let scrubbed = Scrub.entry(
            HAR.Entry(
                startedDateTime: "",
                request: HAR.Request(
                    method: "POST", url: "http://localhost:8000/v1/oauth/token",
                    headers: [HAR.Header(name: "Authorization", value: "Bearer x")],
                    postData: HAR.PostData(mimeType: "application/x-www-form-urlencoded", text: "client_secret=abc&project=p")),
                response: HAR.Response(
                    status: 200,
                    content: HAR.Content(
                        text: #"{"access_token":"\#(jwtShaped)","secret":"s3cret"}"#))))
        #expect(scrubbed.request.headers.first?.value == "REDACTED")
        #expect(scrubbed.request.postData?.text == "client_secret=REDACTED_SECRET&project=p")
        #expect(scrubbed.response.content.text == #"{"access_token":"REDACTED_JWT","secret":"REDACTED_SECRET"}"#)
    }
}
