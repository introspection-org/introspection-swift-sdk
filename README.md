# Introspection Swift SDK

A pure-Swift client for the Introspection REST API: Control Plane and Data Plane, with resumable run streams, cursor pagination, typed errors and session management. No dependencies. Supports iOS 16, macOS 13, tvOS 16, watchOS 9 and visionOS 1, and builds on Linux.

It covers the REST surface of the JavaScript and Rust SDKs. OpenTelemetry export (tracking, feedback, span processors) and Apache Arrow decoding are not included.

## Install

```swift
.package(url: "https://github.com/introspection-org/introspection-swift-sdk", branch: "main")
```

```swift
.product(name: "IntrospectionSDK", package: "introspection-swift-sdk")
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
let run = try await client.tasks.start(prompt: "Hello")
```

The provider must sign with asymmetric keys (ES256 or RS256), and the Application's federation must name its issuer (for Supabase, `https://<ref>.supabase.co/auth/v1`). The member is the same on every sign-in: it is derived from the federation and the provider's `sub`.

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

```swift
let client = try await IntrospectionClient.fromServiceAccount(
    clientId: id, clientSecret: secret, project: "my-project"
)
let runner = try await client.runtimes("customer-agent").run(RunRequest(identity: .init(userId: "u_42")))
let run = try await runner.tasks.start(prompt: "Summarize this repository")
for try await event in run.stream() { print(event.type) }
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

## Errors

Every failure is an `IntrospectionError` with a `kind` (`.authentication`, `.insufficientScope`, `.notFound`, `.conflict`, `.validation`, `.rateLimited`, `.unavailable`, `.network`, ...), the HTTP status, the error `code`, the request id and `Retry-After`. Rate-limited requests and idempotent `502/503/504` are retried automatically.

## Development

```sh
swift build
swift test
```

`./scripts-test.sh` runs the tests in the official `swift:6.1-noble` image, for machines without a Swift toolchain. `KeychainSessionStorage` and `HostedLoginPresenter` compile only on Apple platforms; CI builds them on macOS.
