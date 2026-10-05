#if Telemetry
import IntrospectionSDK

/// The core SDK's `HTTPClient`; the module and its `IntrospectionSDK` enum share a name, and OpenTelemetry has an
/// `HTTPClient` of its own.
typealias CoreHTTPClient = HTTPClient
#endif
