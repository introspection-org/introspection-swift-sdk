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
"Up to Next Minor Version" rule. In `Package.swift`, with `X.Y.Z` the
[latest release](https://github.com/introspection-org/introspection-swift-sdk/releases/latest):

```swift
dependencies: [
    .package(url: "https://github.com/introspection-org/introspection-swift-sdk", .upToNextMinor(from: "X.Y.Z")),
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

## License

Apache-2.0
