<div align="center">
  <a href="https://introspection.dev">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset=".github/images/logo-dark.svg">
      <source media="(prefers-color-scheme: light)" srcset=".github/images/logo-light.svg">
      <img alt="Introspection" src=".github/images/logo-light.svg" width="30%">
    </picture>
  </a>
</div>

<h4 align="center">The infrastructure for long-horizon vertical agents.</h4>

<div align="center">
  <a href="https://introspection.dev"><img src="https://img.shields.io/badge/website-introspection.dev-blue" alt="Website"></a>
  <a href="https://github.com/introspection-org/introspection-swift-sdk/releases/latest"><img src="https://img.shields.io/github/v/release/introspection-org/introspection-swift-sdk?label=%20" alt="Latest release"></a>
  <a href="https://www.apache.org/licenses/LICENSE-2.0"><img src="https://img.shields.io/badge/license-Apache%202.0-green" alt="License"></a>
  <a href="https://x.com/IntrospectionAI"><img src="https://img.shields.io/twitter/follow/IntrospectionAI" alt="Follow on X"></a>
</div>

[Introspection](https://introspection.dev) is the infrastructure for
long-horizon vertical agents, powered by Pi. Define an agent as a
[Recipe](https://pi.recipes) — agents, skills, policies, and evals in plain
source you own in Git — deploy it to a governed per-customer Runtime, and
improve it in production with conversations, observations, judges, and
experiments.

This is the Swift SDK: run tasks against a deployed runtime from an app or a
server, stream their output, and read back tasks, files and conversations.
The opt-in `IntrospectionTelemetry` product sends custom events and gen_ai
traces over OpenTelemetry.
It supports iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2 and Linux.

## Install

In `Package.swift`, add the package and the products you use. Telemetry is
opt-in: its product is empty unless the `Telemetry` trait is enabled, and with
the trait off the OpenTelemetry packages are not even resolved.

```swift
dependencies: [
    // Core only:
    .package(url: "https://github.com/introspection-org/introspection-swift-sdk", branch: "main"),
    // Core and telemetry:
    // .package(url: "https://github.com/introspection-org/introspection-swift-sdk", branch: "main", traits: ["Telemetry"]),
],
targets: [
    .target(name: "App", dependencies: [
        .product(name: "IntrospectionSDK", package: "introspection-swift-sdk"),
        // With the Telemetry trait:
        // .product(name: "IntrospectionTelemetry", package: "introspection-swift-sdk"),
    ]),
]
```

In Xcode, use File > Add Package Dependencies with the repository URL and the
"Branch" rule set to `main`. The product picker lists both `IntrospectionSDK`
and `IntrospectionTelemetry`; add `IntrospectionTelemetry` only together with
the `Telemetry` trait. If your Xcode cannot set package traits for an app
target, depend on the SDK through a local Swift package whose `Package.swift`
passes `traits: ["Telemetry"]`, and add that package to the app.

### Products and traits

| Product | Module | Contains |
| --- | --- | --- |
| `IntrospectionSDK` | `IntrospectionSDK` | The client: sign-in, runtimes and runners, tasks and run streams, files, conversations, events (including reading custom events back), metrics, automations, and the Control Plane resources. No OpenTelemetry dependency. |
| `IntrospectionTelemetry` | `IntrospectionTelemetry` | Opt-in, needs the `Telemetry` trait. Custom events (`logEvent`, `track`, `feedback`, `identify`) and gen_ai traces over OTLP/HTTP, on the [OpenTelemetry Swift SDK](https://github.com/open-telemetry/opentelemetry-swift). |

| Trait | Adds |
| --- | --- |
| `Configuration` | `IntrospectionClient.Configuration(config:)`, read through [swift-configuration](https://github.com/apple/swift-configuration) |
| `Telemetry` | The `IntrospectionTelemetry` module and its OpenTelemetry dependencies |

## Run a task

```swift
import IntrospectionSDK

let client = IntrospectionClient(
    controlPlaneURL: URL(string: "https://api.introspection.dev")!,
    credentials: BearerToken(apiKey)
)
let runner = try await client.runtimes("customer-agent").run(identity: .init(userId: "user_123"))

let handle = try await runner.tasks.start(prompt: "Say hello in one sentence.")
for try await event in handle.stream() where event.eventType == .textMessageContent {
    print(event.delta ?? "", terminator: "")
}
```

Or wait for the finished answer, then continue the same task:

```swift
let answer = try await runner.tasks.start(prompt: "Summarize my open tickets.").text()
let followUp = try await runner.tasks.runs.create(handle.run.taskId, text: "Now draft the reply.")
print(try await followUp.text())
```

The runner also exposes `files`, `conversations`, `events`, `metrics` and `shares`.

### Member tags and metadata

The end user a runner is opened for is a `customer` member. `RunnerIdentity`
can label it: `tags` seed a new member only (they are access-bearing), while
`metadata` seeds a new member and is merged into an existing one, its keys
overwriting keys of the same name.

```swift
let runner = try await client.runtimes("customer-agent").run(
    identity: RunnerIdentity(userId: "user_123", tags: ["customer:acme"], metadata: ["plan": "enterprise"])
)
```

Metadata grants nothing; it is for finding members. With a Control Plane
credential, filter on it and edit it. An update needs `members:manage` and
replaces the whole map; `[:]` clears it:

```swift
let enterprise = try await client.members.list(MemberListParams(metadata: ["plan": "enterprise"])).collect()
_ = try await client.members.update(memberId, MemberUpdate(metadata: ["plan": "team"]))
```

## End users signed in with your identity provider

An app that signs users in with Supabase, Auth0 or another OpenID provider
exchanges the provider's token for an Introspection token through a Direct
JWKS Application, with no app backend:

```swift
let client = try await IntrospectionClient.federated(
    subjectToken: { try await supabase.auth.session.accessToken },
    clientID: "intro_app_...",
    project: "my-project"
)
let run = try await client.tasks.start(prompt: "Hello", TaskCreate(runtimeId: runtimeId))
```

A federated token is not bound to a runtime, so each task names its runtime
version (`runtimeId`): a version id your backend resolves with a service
account and hands to the app, as with the JavaScript browser client. Or open a
`Runner` from the runtime, whose session is bound to it, and run tasks on that.

## Hosted login and push notifications

`AuthClient` with `.hostedLogin` signs a member in through the platform's
hosted login, either a customer `spa` Application or a first-party client such
as `OAuthClientID.ark`. `HostedLoginPresenter.signIn` takes the scopes to ask
for and returns the session; `session.user.name` is the member's display name.

A phone registers for push on its session: the token rides on the sign-in and
refresh grants, and ending the session ends push.

```swift
let session = try await presenter.signIn(with: auth, redirectURI: redirectURI, scope: "tasks:write events:read")

// Once iOS hands over the device token:
try await auth.registerPush(PushRegistration(deviceToken: deviceToken, environment: .production))

// When the user turns notifications off:
try await auth.registerPush(.cleared)
```

The SDK never logs the token. See the Authentication article in the DocC
documentation for the details.

## Telemetry (opt-in)

`IntrospectionTelemetry` (the `Telemetry` trait, see [Install](#install)) is the
Swift counterpart of the JavaScript SDK's `/otel` entry point, Python's
`introspection_sdk.otel` and Rust's `otel` feature: one OpenTelemetry setup that
exports custom events to `<base>/v1/logs` and gen_ai spans to `<base>/v1/traces`.

```swift
import IntrospectionSDK
import IntrospectionTelemetry

// The init() of the other SDKs: configure logs and traces once, register them as the
// global OpenTelemetry providers, and keep them as IntrospectionTelemetry.current.
// Unset settings come from INTROSPECTION_TOKEN, INTROSPECTION_BASE_OTEL_URL, INTROSPECTION_SERVICE_NAME.
let telemetry = try IntrospectionTelemetry.bootstrap()

// Or an instance you hold, without touching the globals:
let telemetry = try IntrospectionTelemetry.fromEnvironment()

// An app: reuse the signed-in session, refreshed like every other call.
let telemetry = try IntrospectionTelemetry(credentials: auth.credentials, serviceName: "ark-ios")
// Or from a client: IntrospectionTelemetry(credentials: client.dataPlane.credentials!)
// Or a token read per request: IntrospectionTelemetry(token: { try await currentToken() })
```

Custom events go to the same `introspection.track` family the other SDKs write:

```swift
try telemetry.logEvent("ark.feed.entry", attributes: ["entry_id": "e_1"], eventId: "feed-entry:e_1")
try telemetry.track("Button Clicked", properties: ["button_id": "submit"])
telemetry.feedback("thumbs_up", comments: "Spot on", conversationId: conversationId)
await telemetry.flush()   // before the app is suspended; shutdown() at exit
```

Names that are empty or start with `introspection.` or `gen_ai.` throw. Nothing
else throws: a failed export is logged to `TelemetryOptions.logger` and dropped.

Traces keep only gen_ai spans. `withGenAISpan` opens one and makes it the parent
of spans started inside it; `registerGlobally()` makes other OpenTelemetry
instrumentation export through the same providers.

```swift
let answer = try await telemetry.withGenAISpan(model: "gpt-5", provider: "openai") { span in
    span.setGenAIInputMessages([.system("Be brief."), .user(prompt)])
    let reply = try await llm.complete(prompt)
    span.setGenAIOutputMessages([.assistant(reply.text, finishReason: "stop")])
    span.setGenAIUsage(inputTokens: reply.inputTokens, outputTokens: reply.outputTokens)
    return reply.text
}
```

Identity, conversation and agent are scoped per task, and stamped on every span
and event inside the scope (`withUserId`, `withAnonymousId`, `withConversation`
and `withAgent` in the other SDKs):

```swift
try await IntrospectionTelemetry.withUserId("user_123") {
    try await IntrospectionTelemetry.withConversation { conversationId in   // nil mints intro_conv_…
        try await IntrospectionTelemetry.withAgent("support-bot", id: "agent_1") {
            try await handle(message)
        }
    }
}
```

A span with no conversation scoped gets an id shared by its trace. Use
`IntrospectionSpanProcessor` on a `TracerProviderBuilder` you already own, or
`IntrospectionLogs` for events alone.

Read custom events back with the core client, by name:

```swift
let entries = try await client.events.list(EventListParams(eventName: .track, names: ["ark.feed.entry"])).collect()
let names = entries.compactMap { $0.track?.name }
```

The `names` filter needs introspection-cloud#3172; an older deployment ignores
it and returns every custom event, so filter on `track?.name` too until then.

The platform keeps telemetry only when the token grants `telemetry:write`, and
drops it silently otherwise. API keys always grant it. A signed-in member's
token (email code, hosted login, federated exchange) grants it when its
Application's `allowed_scopes` are unset or list `telemetry:write`.

| Setting | Variable | Default |
| --- | --- | --- |
| Token | `INTROSPECTION_TOKEN` | required by `fromEnvironment()` and `token: nil` |
| OTLP base URL | `INTROSPECTION_BASE_OTEL_URL` | `https://otel.introspection.dev` |
| `service.name` | `INTROSPECTION_SERVICE_NAME` | `introspection-client` |
| Log batching | `OTEL_BLRP_SCHEDULE_DELAY`, `OTEL_BLRP_EXPORT_TIMEOUT`, `OTEL_BLRP_MAX_QUEUE_SIZE`, `OTEL_BLRP_MAX_EXPORT_BATCH_SIZE` | 5000 ms, 30000 ms, 2048, 100 |
| Span batching | `OTEL_BSP_SCHEDULE_DELAY`, `OTEL_BSP_EXPORT_TIMEOUT`, `OTEL_BSP_MAX_QUEUE_SIZE`, `OTEL_BSP_MAX_EXPORT_BATCH_SIZE` | 5000 ms, 30000 ms, 2048, 512 |
| Extra export headers | `OTEL_EXPORTER_OTLP_HEADERS` | none; never replaces `Authorization` |
| Body compression | `OTEL_EXPORTER_OTLP_COMPRESSION` (`gzip`, `none`) | `none`; gzip applies on Apple platforms only |

Export is always OTLP/HTTP with protobuf bodies, as in the other SDKs;
`OTEL_EXPORTER_OTLP_PROTOCOL` is not read.

An argument beats the variable, which beats the default. The base URL may end
in `/`, `/v1/logs` or `/v1/traces`.

## Environment variables

With the `Configuration` trait (telemetry reads its own; see [Telemetry](#telemetry-opt-in)):

```shell
export INTROSPECTION_TOKEN="intro_xxx"
export INTROSPECTION_BASE_API_URL="https://api.introspection.dev"   # optional
```

## Documentation

- DocC articles in [`Sources/IntrospectionSDK/Documentation.docc`](Sources/IntrospectionSDK/Documentation.docc) and [`Sources/IntrospectionTelemetry/Documentation.docc`](Sources/IntrospectionTelemetry/Documentation.docc)
- Runnable examples: `swift run RuntimesExample`, `swift run FederatedExample`
- [Authentication](https://docs.introspection.dev/sdk/authentication)
- [AGENTS.md](AGENTS.md) for contributors

## Stream recovery

Run streams request replay from cursor `0`, including output produced before the
first connection. Only a settling `RUN_FINISHED` or `RUN_ERROR` confirms completion;
`RUN_FINISHED` with `result.reason = "stream_close"` is suppressed. A nonterminal
EOF checks the specific run's status and reconnects within the recovery budget.
Each new content cursor renews both the timeout window and the reconnect budget.
Lifecycle events, heartbeats and duplicate content renew neither. The timeout is
checked when recovery is needed; it does not interrupt an open connection.

Every reconnect resumes from the last content cursor (`Last-Event-ID`). When
that cursor is older than the server's replay buffer, the stream continues with
one AG-UI `MESSAGES_SNAPSHOT` holding the run's messages so far; its id becomes
the new cursor, and the text helper takes its assistant text in place of what it
had read. When the server holds neither the frames nor a snapshot, it answers
`410` and the stream ends with an incomplete-output error. Runtime images that
predate the snapshot send `CUSTOM resume_gap` instead; raw streams pass it
through. The text helper raises an incomplete-output error instead of returning
partial text, including on `resume_gap`; it also raises on run failure or
cancellation. If the status read
says the run settled but the stream never confirmed completion, it raises an
incomplete-output error. Recover final output from the conversation transcript
when needed; the SDK does not automatically hydrate it or require an additional
`conversations:read` scope just to stream. A long stream can therefore
reconnect after its original timeout as long as content has continued to advance.

Use a concrete run ID when consuming one turn. `runs/current` is a moving alias: a
reconnect or status read may resolve to the next turn if another run has started.

The in-process fake sandbox (`mock://`) supplies replies through the conversation
transcript, not SSE. Its attach-only `stream_close` cannot satisfy `.text()`; use
transcript reads for fake-sandbox tests, or a real runtime for `.text()` tests.

The shared `run-stream-contract.json` fixtures pin these behaviors across Swift,
JavaScript, Rust and Python. Each test suite pins the fixture SHA-256; intentional
contract changes must update all four copies and their expected hashes together.

Swift exposes `.streamIncomplete` and `.runFailed` on `IntrospectionError.kind`.

## License

Apache-2.0
