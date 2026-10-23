import Foundation
import Testing

@testable import IntrospectionSDK

// Compares the requests in Sources with the Control Plane and Data Plane OpenAPI documents, which
// carry the cloud's own classification of every route (`x-introspection`). See
// Contract/ContractCheck.swift for what fails.
//
// The sweep reads staging, so it is skipped unless `INTROSPECTION_API_CONTRACT=1`
// (.github/workflows/api-contract.yml sets it). Each plane serves its own `/openapi.json`: the
// Control Plane's is on api.staging.introspection.dev, and the Data Plane's is under
// `STAGING_DP_URL` (an organization variable in CI), since there are many Data Planes and none is
// the staging one by name. `INTROSPECTION_CP_OPENAPI` / `INTROSPECTION_DP_OPENAPI` name a local file
// to check instead, `INTROSPECTION_API_CONTRACT_REPORT` a file the report is also written to, and
// `INTROSPECTION_API_CONTRACT_MISSING=report` reports missing operations without failing on them,
// as pull requests do: a new cloud route must not block an unrelated change. A document that
// cannot be read fails the test before any report is written.
//
// Run: STAGING_DP_URL=<data plane URL> INTROSPECTION_API_CONTRACT=1 swift test --filter APIContractTests
@Suite struct APIContractTests {
    static let controlPlaneURL = "https://api.staging.introspection.dev/openapi.json"
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    /// `${STAGING_DP_URL}/openapi.json`; only read when no local Data Plane document is named.
    static func dataPlaneURL() throws -> String {
        let base = ProcessInfo.processInfo.environment["STAGING_DP_URL"] ?? ""
        guard !base.isEmpty else {
            throw IntrospectionError(
                kind: .invalidRequest, message: "STAGING_DP_URL is not set: it names the staging Data Plane whose /openapi.json is checked")
        }
        return (base.hasSuffix("/") ? String(base.dropLast()) : base) + "/openapi.json"
    }

    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["INTROSPECTION_API_CONTRACT"] == "1",
            "Set INTROSPECTION_API_CONTRACT=1 to compare Sources against the API reference"))
    func sourcesMatchTheReference() async throws {
        let controlPlane = try await OpenAPIDocument.load(
            plane: "controlplane", environmentKey: "INTROSPECTION_CP_OPENAPI", url: { Self.controlPlaneURL })
        let dataPlane = try await OpenAPIDocument.load(
            plane: "dataplane", environmentKey: "INTROSPECTION_DP_OPENAPI", url: Self.dataPlaneURL)
        let report = ContractCheck.run(documents: [controlPlane, dataPlane], sites: try CallSiteScanner.sources(root: Self.root).scan())
        print(report.text)
        if let path = ProcessInfo.processInfo.environment["INTROSPECTION_API_CONTRACT_REPORT"], !path.isEmpty {
            try report.text.write(toFile: path, atomically: true, encoding: .utf8)
        }
        let reportOnly = ProcessInfo.processInfo.environment["INTROSPECTION_API_CONTRACT_MISSING"] == "report"
        if !report.unknown.isEmpty || (!reportOnly && report.failed) {
            Issue.record("Sources have drifted from the API reference: \(report.summary)")
        }
    }

    // MARK: The check, on small inputs

    private static func sites(_ source: String) -> [CallSite] {
        CallSiteScanner(files: [SwiftFile(path: "Sources/Example.swift", source: source)]).scan()
    }

    private static func check(_ source: String, _ paths: JSONObject) -> ContractReport {
        ContractCheck.run(
            documents: [OpenAPIDocument(plane: "dataplane", document: ["paths": .object(paths)], source: "inline")], sites: sites(source))
    }

    // Operations as the documents mark them: unmarked is for every client.
    private static let sdk: JSONValue = ["x-introspection": ["clients": ["sdk"]]]
    private static let cli: JSONValue = ["x-introspection": ["clients": ["cli"]]]
    private static let noClient: JSONValue = ["x-introspection": ["clients": []]]
    private static let everyClient: JSONValue = ["operationId": "list_sprockets"]

    private static let source = """
        public struct WidgetsAPI {
            let http: HTTPClient

            private func path(_ id: String) -> String { "/v1/widgets/\\(pathSegment(id))" }

            private var base: String { "/v1/widgets" }

            public func list() -> Paginator<Widget> {
                http.paginate(base, query: Query())
            }

            public func get(_ id: String) async throws -> Widget {
                try await http.json("GET", path(id))
            }

            public func update(_ id: String, _ body: Widget) async throws -> Widget {
                let route = path(id)
                return try await http.json("PATCH", route, body: .encode(body), as: Widget.self)
            }

            public func raw(_ id: String) async throws {
                try await post("\\(path(id))/raw")
            }

            public func gone() async throws {
                try await http.empty("DELETE", "/v1/gadgets")
            }

            private func post(_ route: String) async throws {
                try await http.empty("POST", route)
            }
        }
        """

    @Test func readsRoutesThroughHelpersConstantsAndWrappers() {
        #expect(
            Set(Self.sites(Self.source).flatMap { site in site.paths.map { "\(site.method) \($0)" } }) == [
                "GET /v1/widgets", "GET /v1/widgets/{}", "PATCH /v1/widgets/{}", "POST /v1/widgets/{}/raw", "DELETE /v1/gadgets",
            ])
    }

    @Test func reportsMissingOperationsAndUnknownRoutes() {
        let paths: JSONObject = [
            "/v1/widgets": ["get": Self.sdk],
            "/v1/widgets/{widget_id}": ["get": Self.everyClient, "patch": Self.sdk],
            "/v1/widgets/{widget_id}/raw": ["post": ["x-introspection": ["clients": ["cli", "sdk"]]]],
            "/v1/sprockets": ["get": Self.everyClient, "post": Self.sdk],
            "/v1/cogs": ["get": Self.cli],
            "/health": ["get": Self.noClient],
        ]
        let report = Self.check(Self.source, paths)
        #expect(report.missing.sorted() == ["dataplane GET /v1/sprockets", "dataplane POST /v1/sprockets"])
        #expect(report.unknown.count == 1 && report.unknown[0].hasPrefix("DELETE /v1/gadgets"))
        #expect(report.failed)
        #expect(report.text.hasPrefix("API contract: drift: 2 missing operations, 1 unknown routes"))
    }

    @Test func aMatchingSurfaceIsClean() {
        let source = """
            public struct WidgetsAPI {
                let http: HTTPClient
                public func get(_ id: String) async throws -> Widget {
                    try await http.json("GET", "/v1/widgets/\\(pathSegment(id))", as: Widget.self)
                }
            }
            """
        let report = Self.check(
            source,
            [
                "/v1/widgets/{widget_id}": ["get": Self.everyClient], "/v1/cogs": ["get": Self.cli], "/health": ["get": Self.noClient],
            ])
        #expect(!report.failed, "\(report.text)")
    }
}
