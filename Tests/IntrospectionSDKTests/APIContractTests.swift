import Foundation
import Testing

@testable import IntrospectionSDK

// Compares the requests in Sources with the Control Plane and Data Plane OpenAPI documents, which
// carry the cloud's own classification of every route (`x-introspection`). See
// Contract/ContractCheck.swift for what fails and what only warns.
//
// The sweep is skipped unless `INTROSPECTION_API_CONTRACT=1`: it reads staging and goes red when the
// API moves, which is a fact about the world rather than the commit under review, so it runs nightly
// (.github/workflows/api-contract.yml), not on pull requests. `INTROSPECTION_CP_OPENAPI` /
// `INTROSPECTION_DP_OPENAPI` name a local file to check instead, such as the saved copies in
// api-reference/, and `INTROSPECTION_API_CONTRACT_REPORT` a file the report is also written to.
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
        let report = ContractCheck.run(documents: [controlPlane, dataPlane], index: try .sources(root: Self.root))
        print(report.text)
        if let path = ProcessInfo.processInfo.environment["INTROSPECTION_API_CONTRACT_REPORT"], !path.isEmpty {
            try report.text.write(toFile: path, atomically: true, encoding: .utf8)
        }
        if report.failed { Issue.record("Sources have drifted from the API reference: \(report.summary)") }
    }

    // MARK: The check, on small inputs

    private static func check(_ source: String, _ document: JSONObject) throws -> ContractReport {
        let index = SwiftTypeIndex(files: [SwiftFile(path: "Sources/Example.swift", source: source)])
        let data = try JSONCoding.encoder.encode(JSONValue.object(document))
        return ContractCheck.run(documents: [try .parse(plane: "dataplane", data: data, source: "inline")], index: index)
    }

    private static let widget: JSONObject = [
        "type": "object", "required": ["id", "name"],
        "properties": [
            "id": ["type": "string"], "name": ["type": "string"], "size": ["anyOf": [["type": "integer"], ["type": "null"]]],
            "tags": ["type": "array", "items": ["type": "string"]],
        ],
    ]

    private static func document(_ paths: JSONObject) -> JSONObject {
        ["openapi": "3.1.0", "paths": .object(paths), "components": ["schemas": ["Widget": .object(widget)]]]
    }

    private static let sdk: JSONValue = ["visibility": "public", "clients": ["sdk"]]
    private static let widgetResponse: JSONValue = [
        "200": ["content": ["application/json": ["schema": ["$ref": "#/components/schemas/Widget"]]]]
    ]

    private static let source = """
        public typealias JSONObject = [String: JSONValue]

        public struct Widget: Codable {
            public let id: String
            public var name: String
            public var size: Int?
            public var tags: [String]?
        }

        public struct Page<Item: Decodable & Sendable>: Decodable {
            public let records: [Item]
            public let next: String?
            public let hasMore: Bool?
            private enum CodingKeys: String, CodingKey {
                case records, next
                case hasMore = "has_more"
            }
        }

        public struct WidgetListParams {
            public var limit: Int?
            var query: Query {
                var query = Query()
                query.add("limit", limit)
                return query
            }
        }

        public struct WidgetsAPI {
            let http: HTTPClient

            private func path(_ id: String) -> String { "/v1/widgets/\\(pathSegment(id))" }

            public func list(_ params: WidgetListParams = WidgetListParams()) -> Paginator<Widget> {
                http.paginate("/v1/widgets", query: params.query)
            }

            public func get(_ id: String) async throws -> Widget {
                try await http.json("GET", path(id))
            }

            public func update(_ id: String, _ body: Widget) async throws -> Widget {
                try await http.json("PATCH", path(id), body: .encode(body), as: Widget.self)
            }

            public func raw(_ id: String, _ body: JSONObject) async throws {
                try await http.empty("POST", "/v1/widgets/\\(pathSegment(id))/raw", body: .encode(body))
            }

            public func gone() async throws {
                try await http.empty("DELETE", "/v1/gadgets")
            }
        }
        """

    @Test func readsRoutesBodiesQueriesAndResponsesFromSource() throws {
        let index = SwiftTypeIndex(files: [SwiftFile(path: "Sources/Example.swift", source: Self.source)])
        let sites = CallSiteScanner(index: index).scan()
        #expect(
            Set(sites.flatMap { site in site.paths.map { "\(site.method) \($0)" } }) == [
                "GET /v1/widgets", "GET /v1/widgets/{}", "PATCH /v1/widgets/{}", "POST /v1/widgets/{}/raw", "DELETE /v1/gadgets",
            ])
        let list = try #require(sites.first { $0.paths == ["/v1/widgets"] })
        #expect(Set(list.query.keys) == ["limit", "next"])
        #expect(list.query["limit"]?.shape == .integer)
        guard case let .json(.object(_, page)) = list.response else {
            Issue.record("the list response is \(list.response)")
            return
        }
        #expect(page["records"]?.shape.element.map { if case .object = $0 { true } else { false } } == true)
        let update = try #require(sites.first { $0.method == "PATCH" })
        guard case let .json(.object(_, fields)) = update.body else {
            Issue.record("the update body is \(update.body)")
            return
        }
        #expect(fields["id"] == ShapeField(shape: .string, required: true))
        #expect(fields["size"] == ShapeField(shape: .integer, required: false))
    }

    @Test func reportsEachKindOfDrift() throws {
        let paths: JSONObject = [
            "/v1/widgets": [
                "get": [
                    "x-introspection": Self.sdk,
                    "parameters": [
                        ["name": "limit", "in": "query", "schema": ["type": "integer"]],
                        ["name": "next", "in": "query", "schema": ["type": "string"]],
                        ["name": "lane", "in": "query", "schema": ["type": "string"], "x-introspection": ["clients": []]],
                        ["name": "order", "in": "query", "schema": ["type": "string"]],
                    ],
                    "responses": [
                        "200": [
                            "content": [
                                "application/json": [
                                    "schema": [
                                        "type": "object", "required": ["records"],
                                        "properties": [
                                            "records": ["type": "array", "items": ["$ref": "#/components/schemas/Widget"]],
                                            "next": ["type": "string"], "count": ["type": "integer"],
                                        ],
                                    ]
                                ]
                            ]
                        ]
                    ],
                ]
            ],
            "/v1/widgets/{widget_id}": [
                "get": ["x-introspection": Self.sdk, "responses": Self.widgetResponse],
                "patch": [
                    "x-introspection": Self.sdk, "responses": Self.widgetResponse,
                    "requestBody": [
                        "required": true,
                        "content": [
                            "application/json": [
                                "schema": [
                                    "type": "object", "required": ["name"],
                                    "properties": ["name": ["type": "string"], "size": ["type": "string"]],
                                ]
                            ]
                        ],
                    ],
                ],
            ],
            "/v1/widgets/{widget_id}/raw": [
                "post": [
                    "x-introspection": Self.sdk, "responses": ["204": ["description": "done"]],
                    "requestBody": ["content": ["application/json": ["schema": ["$ref": "#/components/schemas/Widget"]]]],
                ]
            ],
            "/v1/sprockets": ["get": ["x-introspection": Self.sdk, "responses": Self.widgetResponse]],
            "/v1/cogs": ["get": ["x-introspection": ["visibility": "public", "clients": ["cli"]], "responses": Self.widgetResponse]],
        ]
        let report = try Self.check(Self.source, Self.document(paths))
        #expect(report.missing == ["dataplane GET /v1/sprockets"])
        #expect(report.unknown.count == 1 && report.unknown[0].hasPrefix("DELETE /v1/gadgets"))
        let details = Set(report.differences.map { "\($0.operation) \($0.detail)" })
        #expect(details.contains("dataplane GET /v1/widgets query.order: accepted by the API, not sent here"))
        #expect(!details.contains { $0.contains("query.lane") })
        #expect(details.contains("dataplane PATCH /v1/widgets/{widget_id} body.id: sent here, not declared by the API"))
        #expect(details.contains("dataplane PATCH /v1/widgets/{widget_id} body.size: type: SDK integer, reference string"))
        #expect(details.contains("dataplane GET /v1/widgets response.has_more: read here, not returned by the API"))
        let warnings = report.warnings.map { "\($0.operation) \($0.detail)" }
        #expect(warnings.contains { $0.hasPrefix("dataplane POST /v1/widgets/{widget_id}/raw body:") })
        #expect(report.failed)
        #expect(report.text.contains("Warning: SDK has no concrete types (1):"))
    }

    @Test func aMatchingSurfaceIsClean() throws {
        let source = """
            public struct Widget: Codable {
                public let id: String
                public var name: String
                public var size: Int?
                public var tags: [String]?
            }

            public struct WidgetsAPI {
                let http: HTTPClient
                public func get(_ id: String) async throws -> Widget {
                    try await http.json("GET", "/v1/widgets/\\(pathSegment(id))", as: Widget.self)
                }
            }
            """
        let paths: JSONObject = ["/v1/widgets/{widget_id}": ["get": ["x-introspection": Self.sdk, "responses": Self.widgetResponse]]]
        let report = try Self.check(source, Self.document(paths))
        #expect(!report.failed, "\(report.text)")
        #expect(report.warnings.isEmpty)
    }

    @Test(arguments: [
        ("[String: Int]", Shape.map(.integer)), ("[Widget]?", Shape.array(.untyped("type `Widget` is not declared in Sources"))),
        ("Optional<Date>", Shape.string), ("JSONObject", Shape.map(.any)),
    ])
    func readsSwiftTypes(text: String, expected: Shape) {
        let index = SwiftTypeIndex(files: [SwiftFile(path: "Sources/A.swift", source: "public typealias JSONObject = [String: JSONValue]")])
        #expect(index.shape(text, .decode) == expected)
    }

    @Test func readsHandWrittenCoding() {
        let source = """
            public struct Status: RawRepresentable, Codable {
                public let rawValue: String
                public init(from decoder: any Decoder) throws { rawValue = try decoder.singleString() }
                public func encode(to encoder: any Encoder) throws { try encoder.encodeSingle(rawValue) }
            }
            public struct Event: Decodable {
                public let kind: Status
                public let at: Date?
                private enum CodingKeys: String, CodingKey { case kind = "type", at = "created_at" }
                public init(from decoder: any Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    kind = try container.decode(Status.self, forKey: .kind)
                    at = try container.decodeIfPresent(Date.self, forKey: .at)
                }
            }
            """
        let index = SwiftTypeIndex(files: [SwiftFile(path: "Sources/A.swift", source: source)])
        #expect(index.shape("Status", .encode) == .string)
        #expect(
            index.shape("Event", .decode)
                == .object(
                    name: "Event",
                    fields: ["type": ShapeField(shape: .string, required: true), "created_at": ShapeField(shape: .string, required: false)])
        )
    }
}
