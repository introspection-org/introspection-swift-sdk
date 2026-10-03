import Foundation

/// A runtime deployment as the Data Plane lists it.
public struct DataPlaneRuntime: Codable, Sendable, Hashable {
    /// The runtime version id a task create takes as `runtime_id`.
    public let runtimeId: String
    public let runtimeName: String?
    /// `ready` once the runtime's image is built.
    public let imageBuildStatus: String?

    public init(runtimeId: String, runtimeName: String? = nil, imageBuildStatus: String? = nil) {
        self.runtimeId = runtimeId
        self.runtimeName = runtimeName
        self.imageBuildStatus = imageBuildStatus
    }

    enum CodingKeys: String, CodingKey {
        case runtimeId = "runtime_id"
        case runtimeName = "runtime_name"
        case imageBuildStatus = "image_build_status"
    }
}

extension DataPlaneConnection {
    /// List the project's runtime deployments for a runtime group slug or id, through
    /// the Data Plane alone.
    ///
    /// A token that is not a runner (a federated `customer` member's, for example)
    /// cannot reach the Control Plane's runtime routes and must name a runtime
    /// version on every task create. This reads the Data Plane's `list_runtimes`
    /// tool (`POST /v1/mcp`, `tasks:write`), which needs the MCP tasks server
    /// enabled on the deployment.
    public func listRuntimes(_ runtime: String? = nil) async throws -> [DataPlaneRuntime] {
        var arguments: JSONObject = [:]
        if let runtime { arguments["runtime"] = .string(runtime) }
        let request: JSONValue = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/call",
            "params": ["name": "list_runtimes", "arguments": .object(arguments)],
        ]
        let response = try await dataPlane.json(
            "POST", "/v1/mcp", body: .encode(request), headers: ["Accept": "application/json"], as: JSONValue.self
        )
        if let error = response["error"] {
            throw IntrospectionError(
                kind: .invalidRequest,
                message: error["message"]?.stringValue ?? "list_runtimes failed",
                code: error["code"]?.intValue.map(String.init),
                body: error
            )
        }
        let rows = response["result"]?["structuredContent"]?["runtimes"] ?? response["result"]?["structured_content"]?["runtimes"]
        return try (rows ?? []).decode([DataPlaneRuntime].self)
    }

    /// The runtime version a new task for this runtime group should use: the first
    /// with a ready image, else the newest, matching the Data Plane's own resolution
    /// for `task_run`. Nil when the project has no such runtime.
    public func resolveRuntimeId(_ runtime: String) async throws -> String? {
        let runtimes = try await listRuntimes(runtime)
        return (runtimes.first { $0.imageBuildStatus == "ready" } ?? runtimes.first)?.runtimeId
    }
}
