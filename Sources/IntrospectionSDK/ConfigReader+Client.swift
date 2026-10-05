#if Configuration
import Configuration
import Foundation

extension IntrospectionClient.Configuration {
    /// Read the client configuration through swift-configuration, so it can come from
    /// environment variables, files or arguments. Requires the `Configuration` package trait.
    ///
    /// ## Configuration keys
    /// With `EnvironmentVariablesProvider` these are the same variables the Rust SDK reads.
    /// - `introspection.token` (`INTROSPECTION_TOKEN`, string, secret, required): an API key or bearer token.
    /// - `introspection.base_api_url` (`INTROSPECTION_BASE_API_URL`, string, default `https://api.introspection.dev`):
    ///   the Control Plane.
    /// - `introspection.dataplane_url` (`INTROSPECTION_DATAPLANE_URL`, string, optional): the Data Plane, when it is
    ///   not the Control Plane host.
    ///
    /// ```swift
    /// let config = ConfigReader(provider: EnvironmentVariablesProvider())
    /// let client = IntrospectionClient(configuration: try .init(config: config))
    /// ```
    public init(
        config: ConfigReader, transport: any HTTPTransport = URLSessionTransport(), options: HTTPClient.Options = .init()
    )
        throws
    {
        let token = try config.requiredString(forKey: ["introspection", "token"], isSecret: true)
        let controlPlane = config.string(forKey: ["introspection", "base_api_url"], default: "https://api.introspection.dev")
        guard let controlPlaneURL = URL(string: controlPlane) else {
            throw IntrospectionError(kind: .invalidRequest, message: "introspection.base_api_url is not a URL: '\(controlPlane)'")
        }
        let dataPlaneURL = try config.string(forKey: ["introspection", "dataplane_url"]).map { value in
            guard let url = URL(string: value) else {
                throw IntrospectionError(kind: .invalidRequest, message: "introspection.dataplane_url is not a URL: '\(value)'")
            }
            return url
        }
        self.init(
            controlPlaneURL: controlPlaneURL,
            dataPlaneURL: dataPlaneURL,
            controlPlaneCredentials: BearerToken(token),
            transport: transport,
            options: options
        )
    }
}
#endif
