import Foundation
import Testing

@testable import IntrospectionSDK

// Compares the requests in Sources with the Control Plane and Data Plane OpenAPI documents, which
// carry the cloud's own classification of every route (`x-introspection`). See
// Contract/ContractCheck.swift for what fails.
//
// The sweep reads staging, so it is skipped unless `INTROSPECTION_API_CONTRACT=1`
// (.github/workflows/api-contract.yml sets it). `INTROSPECTION_CP_OPENAPI` / `INTROSPECTION_DP_OPENAPI`
// name a local file to check instead, `INTROSPECTION_API_CONTRACT_REPORT` a file the report is also
// written to, and `INTROSPECTION_API_CONTRACT_MISSING=report` reports missing operations without
// failing on them, as pull requests do: a new cloud route must not block an unrelated change.
//
// Run: INTROSPECTION_API_CONTRACT=1 swift test --filter APIContractTests
@Suite struct APIContractTests {
    static let controlPlaneURL = "https://api.staging.introspection.dev/openapi/controlplane.json"
    static let dataPlaneURL = "https://api.staging.introspection.dev/openapi/dataplane.json"
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["INTROSPECTION_API_CONTRACT"] == "1",
            "Set INTROSPECTION_API_CONTRACT=1 to compare Sources against the API reference"))
    func sourcesMatchTheReference() async throws {
        let controlPlane = try await OpenAPIDocument.load(
            plane: "controlplane", environmentKey: "INTROSPECTION_CP_OPENAPI", url: Self.controlPlaneURL)
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

    private static let sdk: JSONValue = ["x-introspection": ["visibility": "public", "clients": ["sdk"]]]

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
            "/v1/widgets/{widget_id}": ["get": Self.sdk, "patch": Self.sdk],
            "/v1/widgets/{widget_id}/raw": ["post": Self.sdk],
            "/v1/sprockets": ["get": Self.sdk],
            "/v1/cogs": ["get": ["x-introspection": ["visibility": "public", "clients": ["cli"]]]],
        ]
        let report = Self.check(Self.source, paths)
        #expect(report.missing == ["dataplane GET /v1/sprockets"])
        #expect(report.unknown.count == 1 && report.unknown[0].hasPrefix("DELETE /v1/gadgets"))
        #expect(report.failed)
        #expect(report.text.hasPrefix("API contract: drift: 1 missing operations, 1 unknown routes"))
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
        let report = Self.check(source, ["/v1/widgets/{widget_id}": ["get": Self.sdk], "/v1/cogs": ["get": [:]]])
        #expect(!report.failed, "\(report.text)")
    }
}
