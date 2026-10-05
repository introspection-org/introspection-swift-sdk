# Custom events and telemetry

Send custom events and gen_ai traces with the opt-in telemetry product, and read the events back with this one.

## Add the telemetry product

Telemetry lives in a separate product, `IntrospectionTelemetry`, built on the OpenTelemetry Swift SDK. It is behind the `Telemetry` package trait: without the trait the product is empty and the OpenTelemetry packages are not resolved, so apps that only use the client never build them.

```swift
dependencies: [
    .package(url: "https://github.com/introspection-org/introspection-swift-sdk", branch: "main", traits: ["Telemetry"]),
],
targets: [
    .target(name: "App", dependencies: [
        .product(name: "IntrospectionSDK", package: "introspection-swift-sdk"),
        .product(name: "IntrospectionTelemetry", package: "introspection-swift-sdk"),
    ]),
]
```

## Log events and traces

`IntrospectionTelemetry` is the `init()` of the JavaScript and Python SDKs: one setup that exports custom events to `<base>/v1/logs` and gen_ai spans to `<base>/v1/traces`. Pass it this module's credentials so a session refreshes as it does for every other call:

```swift
import IntrospectionTelemetry

let telemetry = try IntrospectionTelemetry(credentials: auth.credentials, serviceName: "ark-ios")
try telemetry.logEvent("ark.feed.entry", attributes: ["entry_id": "e_1"], eventId: "feed-entry:e_1")
try telemetry.track("Button Clicked", properties: ["button_id": "submit"])
await telemetry.flush()
```

`IntrospectionTelemetry.bootstrap()` is the `init()` of the other SDKs: it configures both signals, registers them as the global OpenTelemetry providers and keeps them as `IntrospectionTelemetry.current`. It and `IntrospectionTelemetry.fromEnvironment()` read `INTROSPECTION_TOKEN`, `INTROSPECTION_BASE_OTEL_URL` (default `https://otel.introspection.dev`), `INTROSPECTION_SERVICE_NAME` (default `introspection-client`) and the `OTEL_BLRP_*` / `OTEL_BSP_*` batch settings. The module's own documentation covers spans, `withUserId` / `withConversation` / `withAgent` scoping and the standalone span processor.

The platform keeps telemetry only when the sending token grants `telemetry:write`, and drops it silently otherwise. API keys always grant it; a signed-in member's token grants it when its Application's `allowed_scopes` are unset or list `telemetry:write`.

## Read events back

Custom events are the ``IntrospectionEventName/track`` family; each row's ``IntrospectionEvent/track`` is a ``TrackPayload`` with the name and properties. Only the caller's own events are returned.

```swift
let entries = try await client.events.list(
    EventListParams(eventName: .track, lookback: .days(7), names: ["ark.feed.entry"])
).collect()
for event in entries {
    print(event.track?.name ?? "", event.track?.properties?["entry_id"] ?? .null)
}
```

``EventListParams/names`` sends up to 20 exact names, each at most 256 characters. The server accepts the filter from introspection-cloud#3172; a deployment without it ignores the parameter and returns every custom event, so filter on ``TrackPayload/name`` as well until then.
