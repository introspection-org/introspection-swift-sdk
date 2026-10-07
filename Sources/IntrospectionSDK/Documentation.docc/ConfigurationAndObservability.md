# Configuration and observability

Read settings from the environment or files, log what the SDK does, and connect its requests to your traces.

## Read configuration with swift-configuration

Enable the `Configuration` package trait to read the client's settings through [swift-configuration](https://github.com/apple/swift-configuration). Values can then come from environment variables, files or command-line arguments:

```swift
.package(url: "https://github.com/introspection-org/introspection-swift-sdk", branch: "main", traits: ["Configuration"])
```

```swift
import Configuration
import IntrospectionSDK

let config = ConfigReader(provider: EnvironmentVariablesProvider())
let client = IntrospectionClient(configuration: try .init(config: config))
```

With environment variables, the keys are the ones the Rust SDK reads: `INTROSPECTION_TOKEN` (secret, required), `INTROSPECTION_BASE_API_URL`, `INTROSPECTION_DATAPLANE_URL` and `INTROSPECTION_RUNTIME`. Without the trait, the package does not depend on swift-configuration at all.

Apps rarely use this: an iOS app has no environment, and its credential comes from sign-in. See <doc:Authentication>.

## Logging

The SDK logs through [swift-log](https://github.com/apple/swift-log) and is silent until you pass a logger:

```swift
var logger = Logger(label: "com.example.app.introspection")
logger.logLevel = .debug
let client = IntrospectionClient(configuration: .init(
    controlPlaneURL: baseURL,
    controlPlaneCredentials: BearerToken(apiKey),
    options: .init(logger: logger)
))
```

It logs each request's method, path, status and request id at `debug`, retries at `notice`, and credential refreshes. Tokens, prompts and response bodies are never logged.

## Tracing

Every request carries the W3C trace context (`traceparent`, `tracestate`, `baggage`) of the current task when your app bootstraps an instrument through [swift-distributed-tracing](https://github.com/apple/swift-distributed-tracing). The platform's APIs continue that trace, so their spans join yours. Without an instrument, nothing is added.

Every request also sends `User-Agent: introspection-swift-sdk/<version>`, naming this library and its release. Override it with ``HTTPClient/Options/userAgent``.
