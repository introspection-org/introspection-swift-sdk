import Foundation

/// Anything that holds a Data Plane connection: the root client, and a
/// `Runner` opened from a runtime. Data Plane resources (`tasks`, `files`,
/// `conversations`, ...) are extensions on this protocol, so both expose the
/// same surface.
public protocol DataPlaneConnection: Sendable {
    var dataPlane: HTTPClient { get }
    /// Names the runtime version on task creates and runs when the token is not a runner.
    var runtimeSelector: RuntimeSelector? { get }
}

extension DataPlaneConnection {
    public var runtimeSelector: RuntimeSelector? { nil }
}

/// Entry point to the Introspection API.
///
/// The Control Plane (identity, organizations, projects, runtimes,
/// connectors) and the Data Plane (tasks, runs, files, conversations, events,
/// automations) are separate hosts with separate credentials:
///
/// ```swift
/// let client = IntrospectionClient(
///     controlPlaneURL: URL(string: "https://api.introspection.dev")!,
///     dataPlaneURL: URL(string: "https://dp.example.com")!,
///     credentials: BearerToken(apiKey)
/// )
/// let run = try await client.tasks.start(prompt: "Summarize my week")
/// for try await event in run.stream() { print(event.type) }
/// ```
public final class IntrospectionClient: DataPlaneConnection {
    public struct Configuration: Sendable {
        public var controlPlaneURL: URL
        /// Defaults to `controlPlaneURL`, which suits a single-host self-hosted install.
        public var dataPlaneURL: URL?
        public var controlPlaneCredentials: (any CredentialProvider)?
        /// Defaults to `controlPlaneCredentials`.
        public var dataPlaneCredentials: (any CredentialProvider)?
        public var transport: any HTTPTransport
        public var options: HTTPClient.Options
        public var userAgent: String?
        /// Runtime group slug or id that task creates and runs bind to when the
        /// token is not a runner (a federated member's, for example). Resolved on
        /// the Data Plane and cached; ignored for runner tokens by the server.
        public var runtime: String?

        public init(
            controlPlaneURL: URL,
            dataPlaneURL: URL? = nil,
            controlPlaneCredentials: (any CredentialProvider)? = nil,
            dataPlaneCredentials: (any CredentialProvider)? = nil,
            transport: any HTTPTransport = URLSessionTransport(),
            options: HTTPClient.Options = HTTPClient.Options(),
            userAgent: String? = "introspection-swift/\(IntrospectionSDK.version)",
            runtime: String? = nil
        ) {
            self.controlPlaneURL = controlPlaneURL
            self.dataPlaneURL = dataPlaneURL
            self.controlPlaneCredentials = controlPlaneCredentials
            self.dataPlaneCredentials = dataPlaneCredentials
            self.transport = transport
            self.options = options
            self.userAgent = userAgent
            self.runtime = runtime
        }
    }

    public let configuration: Configuration
    /// The Control Plane HTTP client.
    public let controlPlane: HTTPClient
    /// The Data Plane HTTP client.
    public let dataPlane: HTTPClient
    public let runtimeSelector: RuntimeSelector?

    public init(configuration: Configuration) {
        self.configuration = configuration
        var options = configuration.options
        if let userAgent = configuration.userAgent, options.additionalHeaders["User-Agent"] == nil {
            options.additionalHeaders["User-Agent"] = userAgent
        }
        controlPlane = HTTPClient(
            baseURL: configuration.controlPlaneURL,
            credentials: configuration.controlPlaneCredentials,
            transport: configuration.transport,
            options: options
        )
        dataPlane = HTTPClient(
            baseURL: configuration.dataPlaneURL ?? configuration.controlPlaneURL,
            credentials: configuration.dataPlaneCredentials ?? configuration.controlPlaneCredentials,
            transport: configuration.transport,
            options: options
        )
        let dataPlane = self.dataPlane
        runtimeSelector = configuration.runtime.map { runtime in
            RuntimeSelector(runtime: runtime) { try await dataPlane.resolveRuntimeId($0) }
        }
    }

    public convenience init(
        controlPlaneURL: URL,
        dataPlaneURL: URL? = nil,
        credentials: (any CredentialProvider)? = nil,
        transport: any HTTPTransport = URLSessionTransport()
    ) {
        self.init(
            configuration: Configuration(
                controlPlaneURL: controlPlaneURL,
                dataPlaneURL: dataPlaneURL,
                controlPlaneCredentials: credentials,
                transport: transport
            ))
    }
}

public enum IntrospectionSDK {
    public static let version = "0.1.0"  // x-release-please-version
}
