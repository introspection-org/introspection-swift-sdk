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
It supports iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2 and Linux.

## Install

In Xcode, use File > Add Package Dependencies with the repository URL and the
"Branch" rule set to `main`. In `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/introspection-org/introspection-swift-sdk", branch: "main"),
],
targets: [
    .target(name: "App", dependencies: [
        .product(name: "IntrospectionSDK", package: "introspection-swift-sdk"),
    ]),
]
```

| Trait | Adds |
| --- | --- |
| `Configuration` | `IntrospectionClient.Configuration(config:)`, read through [swift-configuration](https://github.com/apple/swift-configuration) |

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

A federated token is not bound to a runtime, so each task names the runtime
version. Resolve it on your backend with a service account, as with the
JavaScript browser client.

## Environment variables

With the `Configuration` trait:

```shell
export INTROSPECTION_TOKEN="intro_xxx"
export INTROSPECTION_BASE_API_URL="https://api.introspection.dev"   # optional
```

## Documentation

- DocC articles in [`Sources/IntrospectionSDK/Documentation.docc`](Sources/IntrospectionSDK/Documentation.docc)
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
