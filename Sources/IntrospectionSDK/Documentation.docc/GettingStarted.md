# Getting started

Add the package, create a client, and run your first task.

## Add the package

Add the SDK from its `main` branch:

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

In Xcode, use File > Add Package Dependencies with the same URL. Commit your `Package.resolved` so every build uses the same release. The SDK requires iOS 18, macOS 15, tvOS 18, watchOS 11 or visionOS 2, and a Swift 6.2 or newer toolchain.

## Create a client

How you create the client depends on who is calling; <doc:Authentication> covers each case. On a server or in a script, an API key is enough:

```swift
import IntrospectionSDK

let client = IntrospectionClient(
    controlPlaneURL: URL(string: "https://api.introspection.dev")!,
    credentials: BearerToken(apiKey)
)
```

## Run a task

A runtime is a deployed agent. Open a ``Runner`` on it for one end user, then start a task and wait for the answer:

```swift
let runner = try await client.runtimes("customer-agent").run(identity: .init(userId: "user_123"))

let handle = try await runner.tasks.start(prompt: "Say hello in one sentence.")
print(try await handle.text())

let followUp = try await runner.tasks.runs.create(handle.run.taskId, text: "Now in French.")
print(try await followUp.text())

runner.close()
```

``RunHandle/text(options:)`` throws ``IntrospectionError`` with kind `.runFailed` when the run ends with an error, so a failed run never reads as an empty answer. To show the answer as it is written, stream it instead; see <doc:RunsAndStreaming>.

## Handle errors

Every failure is an ``IntrospectionError``. Switch on its `kind` (`.authentication`, `.insufficientScope`, `.notFound`, `.conflict`, `.rateLimited`, `.runFailed`, ...) and log its `requestId` when you report a problem. Rate-limited requests and idempotent `502`, `503` and `504` responses are retried automatically with backoff.
