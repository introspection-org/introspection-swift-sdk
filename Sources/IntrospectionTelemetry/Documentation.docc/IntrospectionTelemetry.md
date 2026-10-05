# ``IntrospectionTelemetry``

Custom events and gen_ai traces for Introspection over OpenTelemetry: the Swift counterpart of the JavaScript SDK's `/otel` entry point, Python's `introspection_sdk.otel` and Rust's `otel` feature.

## Overview

This module is opt-in. It builds only with the package's `Telemetry` trait, which also brings in the OpenTelemetry Swift SDK; the `IntrospectionSDK` client does not depend on it.

```swift
.package(url: "https://github.com/introspection-org/introspection-swift-sdk", branch: "main", traits: ["Telemetry"])
```

``IntrospectionTelemetry`` sets up both signals with one set of credentials, base URL and service name: an ``IntrospectionLogs`` that exports custom events to `<base>/v1/logs`, and a tracer provider whose ``IntrospectionSpanProcessor`` exports gen_ai spans to `<base>/v1/traces`.

```swift
import IntrospectionSDK
import IntrospectionTelemetry

let telemetry = try IntrospectionTelemetry.bootstrap()             // init(): reads the environment, registers globally
let telemetry = try IntrospectionTelemetry(credentials: auth.credentials, serviceName: "ark-ios")   // an app

try await IntrospectionTelemetry.withUserId("user_123") {
    try await IntrospectionTelemetry.withConversation { _ in
        try telemetry.logEvent("ark.feed.entry", attributes: ["entry_id": "e_1"], eventId: "feed-entry:e_1")
        try await telemetry.withGenAISpan(model: "gpt-5", provider: "openai") { span in
            span.setGenAIInputMessages([.user("Hi")])
            span.setGenAIOutputMessages([.assistant("Hello", finishReason: "stop")])
        }
    }
}
await telemetry.flush()
```

### Credentials

Every initializer takes the same credentials as the client. `credentials:` accepts any `CredentialProvider`, such as an `AuthClient`'s `credentials` or `client.dataPlane.credentials`, so a session refreshes after a 401 exactly as the client's calls do. `token:` takes a fixed token (nil reads `INTROSPECTION_TOKEN`) or a closure read on every request.

The platform keeps telemetry only when the token grants `telemetry:write`, and drops it silently otherwise. API keys always grant it; a signed-in member's token grants it when its Application's `allowed_scopes` are unset or list `telemetry:write`.

### Settings

An argument beats the environment variable, which beats the default; see ``TelemetryEnvironment``.

| Setting | Variable | Default |
| --- | --- | --- |
| Token | `INTROSPECTION_TOKEN` | required by `fromEnvironment()` |
| OTLP base URL | `INTROSPECTION_BASE_OTEL_URL` | `https://otel.introspection.dev` |
| `service.name` | `INTROSPECTION_SERVICE_NAME` | `introspection-client` |
| Log batching | `OTEL_BLRP_*` | 5000 ms, 30000 ms, 2048 queued, 100 per request |
| Span batching | `OTEL_BSP_*` | 5000 ms, 30000 ms, 2048 queued, 512 per request |
| Extra export headers | `OTEL_EXPORTER_OTLP_HEADERS` | none; never replaces `Authorization` |

Export is OTLP/HTTP with protobuf bodies (`application/x-protobuf`), through the OpenTelemetry Swift SDK's HTTP exporters, as in the other SDKs.

### Delivery

Records and spans are batched and sent in the background; call ``IntrospectionTelemetry/flush()`` before the app is suspended and ``IntrospectionTelemetry/shutdown()`` at exit. A failed export is logged to ``TelemetryOptions/logger`` and its batch is dropped; only an invalid event name throws.

## Topics

### Setup

- ``IntrospectionTelemetry``
- ``IntrospectionTelemetry/bootstrap(token:baseURL:serviceName:options:)``
- ``IntrospectionTelemetry/current``
- ``TelemetryOptions``
- ``TelemetryBatchOptions``
- ``TelemetryEnvironment``

### Custom events

- ``IntrospectionLogs``
- ``LogEventSeverity``
- ``EventIdentity``

### Traces

- ``IntrospectionSpanProcessor``
- ``GenAIMessage``
- ``GenAIMessagePart``

### Context

- ``TelemetryContext``
