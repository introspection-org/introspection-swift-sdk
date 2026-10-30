import Foundation
import Testing

@testable import IntrospectionSDK

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Answers by the request's path, so a test shares no state with the others running beside it.
private final class StubProtocol: URLProtocol {
    override class func canInit(with _: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let client, let url = request.url else { return }
        switch url.path {
        case "/fail":
            client.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        case "/cancelled":
            client.urlProtocol(self, didFailWithError: URLError(.cancelled))
            return
        #if canImport(Darwin)
        // swift-corelibs-foundation does not implement `wasRedirectedTo`.
        case "/followable":
            let response = HTTPURLResponse(
                url: url, statusCode: 307, httpVersion: nil, headerFields: ["Location": "https://stub.example.com/ok"])!
            client.urlProtocol(
                self, wasRedirectedTo: URLRequest(url: URL(string: "https://stub.example.com/ok")!), redirectResponse: response)
            client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        #endif
        case "/redirect":
            let response = HTTPURLResponse(
                url: url, statusCode: 307, httpVersion: nil, headerFields: ["Location": "https://idp.example.com/out"])!
            client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        default:
            let response = HTTPURLResponse(url: url, statusCode: 201, httpVersion: nil, headerFields: ["X-Echo": request.httpMethod ?? ""])!
            client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(self, didLoad: Data("first,second".utf8))
        }
        client.urlProtocolDidFinishLoading(self)
    }
}

@Suite struct URLSessionTransportTests {
    private func transport() -> URLSessionTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSessionTransport(configuration: configuration)
    }

    private func request(_ path: String, followRedirects: Bool = true) -> HTTPRequest {
        var request = HTTPRequest(method: "POST", url: URL(string: "https://stub.example.com\(path)")!)
        request.followRedirects = followRedirects
        return request
    }

    @Test func sendReturnsTheStatusLowercasedHeadersAndBody() async throws {
        let response = try await transport().send(request("/ok"))
        #expect(response.status == 201)
        #expect(response.headers["x-echo"] == "POST")
        #expect(String(decoding: response.body, as: UTF8.self) == "first,second")
    }

    @Test func aRequestThatKeepsItsRedirectStillGetsAnAnswer() async throws {
        let response = try await transport().send(request("/redirect", followRedirects: false))
        #expect(response.status == 307)
        #expect(response.headers["location"] == "https://idp.example.com/out")
    }

    #if canImport(Darwin)
    @Test func aRefusedRedirectIsNotFollowed() async throws {
        let response = try await transport().send(request("/followable", followRedirects: false))
        #expect(response.status == 307)
        #expect(response.headers["x-echo"] == nil)
    }
    #endif

    @Test func aFailedConnectionIsANetworkError() async {
        await #expect {
            _ = try await transport().send(request("/fail"))
        } throws: { error in
            (error as? IntrospectionError)?.kind == .network
        }
    }

    @Test func aCancelledRequestIsACancellation() async {
        await #expect(throws: CancellationError.self) {
            _ = try await transport().send(request("/cancelled"))
        }
    }

    @Test func streamDeliversTheHeadThenTheBody() async throws {
        let response = try await transport().stream(request("/ok"))
        #expect(response.status == 201)
        #expect(response.headers["x-echo"] == "POST")
        #expect(String(decoding: try await response.collect(), as: UTF8.self) == "first,second")
    }

    @Test func aFailedStreamThrows() async {
        await #expect {
            _ = try await transport().stream(request("/fail"))
        } throws: { error in
            (error as? IntrospectionError)?.kind == .network
        }
    }
}
