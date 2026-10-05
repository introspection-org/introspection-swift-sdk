# Logging custom events

Record what happens in your app under names of your own, and read the events back by name.

## Log an event

``IntrospectionClient/eventLogger`` writes custom events with the client's Data Plane credentials. Each event is an OpenTelemetry log record whose `event.name` is your name and whose attributes land under `properties.*`, the same record the JavaScript (`logEvent`), Python and Rust SDKs write:

```swift
try client.eventLogger.logEvent(
    "ark.feed.entry",
    attributes: ["entry_id": .string(entry.id), "score": 0.9],
    eventId: "feed-entry:\(entry.id)"
)

// The Segment-style alias, at INFO:
try client.eventLogger.track("Button Clicked", properties: ["button_id": "submit"])
```

`logEvent` also takes a `timestamp` (default now), an ``EventIdentity`` (each field set replaces the one in ``EventLogger/Configuration/identity``) and a ``LogEventSeverity`` (default `INFO`). A `nil` attribute is omitted; arrays and objects are sent as JSON strings. Pass a stable `eventId` when the same event may be logged more than once: readers dedupe on it. Without one, the SDK generates an id.

A name that is empty or starts with `introspection.` or `gen_ai.` throws an ``IntrospectionError`` with kind `invalidRequest`: those namespaces belong to the platform and to the OpenTelemetry GenAI conventions. Nothing else ever throws.

## Delivery

Events are queued in memory and sent as OTLP/HTTP JSON to `<otelURL>/v1/logs`, in batches: as soon as ``EventLogger/Configuration/maxBatchSize`` events are waiting, or ``EventLogger/Configuration/flushInterval`` after the first unsent one. `logEvent` never waits for the network. A request that fails is logged to the client's `logger` and its events are dropped, so re-log with the same `eventId` if an event must arrive.

The queue lives in memory, so flush it before the app is suspended:

```swift
.onChange(of: scenePhase) { _, phase in
    if phase == .background { Task { await client.eventLogger.flush() } }
}
```

The collector defaults to `https://otel.introspection.dev`. Set ``IntrospectionClient/Configuration/otelURL`` (or `otelURL:` on ``AuthClient/client(dataPlaneURL:options:otelURL:eventLogging:)``, or `INTROSPECTION_BASE_OTEL_URL` with the `Configuration` trait) for another deployment. A ``Runner`` logs through `EventLogger(otelURL:connection:)`.

## Which tokens can write events

The platform keeps an event only when the sending token grants `telemetry:write`. It answers success either way and drops the records, so the SDK cannot tell; check that events arrive when you first wire this up.

- API keys and service-account tokens always carry `telemetry:write`.
- A signed-in member's token (``AuthClient``, email code, hosted login, federated exchange) carries what its Application's `allowed_scopes` grant. Unset, they include `telemetry:write`; an explicit list must name `telemetry:write` for that app's events to be kept.

The platform stamps the event's owner from the verified token and replaces any `identity.*` attribute the token's identity contradicts.

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
