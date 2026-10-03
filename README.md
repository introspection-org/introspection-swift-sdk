# Introspection Swift SDK

A pure-Swift client for the Introspection REST API: Control Plane and Data Plane, with resumable run streams, cursor pagination, typed errors and session management. Swift 6, built on `URLSession` and Apple's own packages (`swift-crypto`, `swift-log`, `swift-distributed-tracing`, and `swift-configuration` behind an opt-in trait). Supports iOS 18, macOS 15, tvOS 18, watchOS 11 and visionOS 2, and builds on Linux.

It covers the REST surface of the JavaScript and Rust SDKs. OpenTelemetry export (tracking, feedback, span processors) and Apache Arrow decoding are not included.

## Install

In Xcode, use File > Add Package Dependencies with the repository URL and the "Up to Next Minor Version" rule. In `Package.swift`, add the package and the product, with `X.Y.Z` the [latest release](https://github.com/introspection-org/introspection-swift-sdk/releases/latest):

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

## Signing in

### Federated identity provider (Supabase, Auth0, Okta, ...)

The app keeps its own identity provider and its SDK (for example supabase-swift) for sign-in and the session. An Introspection Application of type Direct JWKS, federated to that provider's issuer, turns the provider's token into a platform token for a `customer` member. No app backend is involved.

```swift
import IntrospectionSDK
import Supabase

let client = try await IntrospectionClient.federated(
    subjectToken: { try await supabase.auth.session.accessToken },
    clientID: "intro_app_...",
    project: "my-project",
    controlPlaneURL: URL(string: "https://api.introspection.dev")!
)
let run = try await client.tasks.start(prompt: "Hello", TaskCreate(runtimeId: runtimeId))
```

A federated token is not a runner token, so a task runs on the app's runtime only when its create and runs name the runtime version (`runtimeId`). Customer tokens cannot call the Control Plane, so the app's backend resolves that id with a service account (`client.runtimes.list(...)`) and returns it with the session, as with the JavaScript browser client. The provider must sign with asymmetric keys (ES256 or RS256), and the Application's federation must name its issuer (for Supabase, `https://<ref>.supabase.co/auth/v1`). The member is the same on every sign-in: it is derived from the federation and the provider's `sub`.

The first exchange runs inside `federated(...)`, which also learns the Data Plane URL. Later exchanges run before the platform token expires or after a 401, each time asking for a current provider token. Sign out with the provider's SDK. For lower-level control, use `SessionCredentials.tokenExchange` with your own `IntrospectionClient`.

### Platform sign-in (`AuthClient`)

`AuthClient` manages a platform session the way the Supabase Auth client does: sign in, persist, refresh, sign out and observe changes.

```swift
let auth = AuthClient(configuration: .init(
    controlPlaneURL: URL(string: "https://api.introspection.dev")!,
    clientID: "intro_app_...",
    project: "my-project",
    method: .hostedLogin,
    storage: KeychainSessionStorage()
))

// Hosted login in the system sheet (Apple platforms).
let presenter = HostedLoginPresenter(anchor: window)
try await presenter.signIn(with: auth, redirectURI: "https://app.example.com/auth/callback")

for await (event, session) in await auth.authStateChanges() {
    print(event, session?.user.memberId ?? "signed out")
}

let client = try await auth.client()
```

`.emailCode` (`signInWithOTP(email:)` / `verifyOTP(email:token:)`) targets the Control Plane's native email-code sign-in, which is proposed and not yet available on the platform.

### Machines and servers

The same runner flow as the JavaScript and Rust SDKs:

```swift
let client = IntrospectionClient(controlPlaneURL: baseURL, credentials: BearerToken(apiKey))
// or: try await IntrospectionClient.fromServiceAccount(clientId: id, clientSecret: secret, project: "my-project")

let runner = try await client.runtimes("customer-agent").run(identity: .init(userId: "user_123"))

let handle = try await runner.tasks.start(prompt: "Say hello in one sentence.")
for try await event in handle.stream() where event.eventType == .textMessageContent {
    print(event.delta ?? "", terminator: "")
}

// Or wait for the finished answer, then continue the same task.
let answer = try await runner.tasks.start(prompt: "Summarize my open tickets.").text()
let followUp = try await runner.tasks.runs.create(handle.run.taskId, text: "And the oldest one?")

runner.close()
```

`AuthAPI` exposes every grant directly: client credentials, token exchange, JWT bearer, authorization code with PKCE, refresh, device code and revoke. `OIDC` helps with any external issuer.

## Data Plane

Available on `IntrospectionClient` and on a `Runner`:

- `tasks`, `tasks.runs`: create and steer runs, resumable AG-UI streams (`Last-Event-ID`, readiness waits, reconnect budget).
- `files`, `files.versions`: upload, text writes, versions, tags and metadata, downloads.
- `conversations`, `conversations.items`: summaries, turns, GenAI spans, exports.
- `events`, `metrics`, `shares`, `automations`.
- `TranscriptAccumulator`, `foldSpans`, `mergeTranscripts`: one transcript from live events and stored spans.

## Control Plane

`runtimes` (and runners), `experiments`, `recipes`, `connectors` and connections, `repositories`, `annotations`, `projectLabels`, `organizations`, `projects`, `members`.

## Examples

Runnable programs in `Examples/`:

- `swift run RuntimesExample`: open a runner from a runtime, stream a task, list conversations and upload files (the Rust SDK's `examples/api/runtimes.rs`).
- `swift run FederatedExample`: exchange an identity provider's token and run a task as that end user.

## Errors

Every failure is an `IntrospectionError` with a `kind` (`.authentication`, `.insufficientScope`, `.notFound`, `.conflict`, `.validation`, `.rateLimited`, `.unavailable`, `.network`, ...), the HTTP status, the error `code`, the request id and `Retry-After`. Rate-limited requests and idempotent `502/503/504` are retried automatically.

## Development

```sh
swift build
swift test
scripts/lint.sh          # swift format lint, as CI runs it (--fix to rewrite)
scripts/coverage.sh      # tests with the line-coverage floor
scripts/setup-hooks.sh   # install the pre-commit hook
```

`scripts/docker-test.sh` runs the tests in the official `swift:6.4-noble` image, for machines without a Swift toolchain. `KeychainSessionStorage` and `HostedLoginPresenter` compile only on Apple platforms; CI builds them for macOS and iOS. Read [AGENTS.md](AGENTS.md) before contributing.

Releases are cut by release-please from Conventional Commit PR titles; Swift Package Manager installs from the resulting tags.
