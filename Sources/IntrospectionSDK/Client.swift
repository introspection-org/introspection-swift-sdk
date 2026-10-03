import Foundation
import Logging

/// Anything that holds a Data Plane connection: the root client, and a
/// `Runner` opened from a runtime. Data Plane resources (`tasks`, `files`,
/// `conversations`, ...) are extensions on this protocol, so both expose the
/// same surface.
public protocol DataPlaneConnection: Sendable {
    var dataPlane: HTTPClient { get }
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

        public init(
            controlPlaneURL: URL,
            dataPlaneURL: URL? = nil,
            controlPlaneCredentials: (any CredentialProvider)? = nil,
            dataPlaneCredentials: (any CredentialProvider)? = nil,
            transport: any HTTPTransport = URLSessionTransport(),
            options: HTTPClient.Options = HTTPClient.Options()
        ) {
            self.controlPlaneURL = controlPlaneURL
            self.dataPlaneURL = dataPlaneURL
            self.controlPlaneCredentials = controlPlaneCredentials
            self.dataPlaneCredentials = dataPlaneCredentials
            self.transport = transport
            self.options = options
        }
    }

    public let configuration: Configuration
    /// The Control Plane HTTP client.
    public let controlPlane: HTTPClient
    /// The Data Plane HTTP client.
    public let dataPlane: HTTPClient

    public init(configuration: Configuration) {
        self.configuration = configuration
        let options = configuration.options
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
    public static let version = "0.2.0"  // x-release-please-version
    /// The same `User-Agent` the Rust and TypeScript SDKs send.
    public static let userAgent = "introspection-sdk/\(version)"
    /// The default logger: discards everything until the app passes its own.
    public static let silentLogger = Logger(label: "dev.introspection.sdk", factory: { _ in SwiftLogNoOpLogHandler() })
}
