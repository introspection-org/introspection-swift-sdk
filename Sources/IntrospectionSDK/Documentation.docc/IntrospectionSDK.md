# ``IntrospectionSDK``

A Swift client for the Introspection platform: run agents on your runtimes, stream their answers, and read back tasks, files and conversations.

## Overview

Introspection splits into a Control Plane (organizations, projects, runtimes, recipes, connectors, experiments) and a Data Plane (tasks, runs, files, conversations, events, metrics). ``IntrospectionClient`` talks to both, and a ``Runner`` is a Data Plane connection bound to one runtime and one end user.

```swift
import IntrospectionSDK

let client = IntrospectionClient(
    controlPlaneURL: URL(string: "https://api.introspection.dev")!,
    credentials: BearerToken(apiKey)
)
let runner = try await client.runtimes("customer-agent").run(identity: .init(userId: "user_123"))
let answer = try await runner.tasks.start(prompt: "Summarize my open tickets.").text()
```

The package is Swift 6, built on `URLSession` and Apple's own packages, and runs on iOS, macOS, tvOS, watchOS, visionOS and Linux.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:Authentication>
- <doc:RunsAndStreaming>
- <doc:ConfigurationAndObservability>
- ``IntrospectionClient``
- ``Runner``
- ``IntrospectionError``

### Signing in

- ``AuthAPI``
- ``SessionCredentials``
- ``BearerToken``
- ``CredentialProvider``
- ``OIDC``
- ``PKCE``

### Runtimes and runners

- ``RuntimesAPI``
- ``RuntimeHandle``
- ``RunnerIdentity``
- ``RunRequest``
- ``ExperimentsAPI``
- ``ExperimentHandle``
- ``DataPlaneConnection``

### Tasks and runs

- ``TasksAPI``
- ``TaskRunsAPI``
- ``RunHandle``
- ``RunStreamOptions``
- ``IntrospectionTask``
- ``TaskRun``
- ``TaskCreate``

### Streaming events and transcripts

- ``AGUIEvent``
- ``AGUIEventType``
- ``TranscriptAccumulator``
- ``TranscriptEntry``

### Files, conversations and telemetry

- ``FilesAPI``
- ``ConversationsAPI``
- ``EventsAPI``
- ``MetricsAPI``
- ``SharesAPI``
- ``AutomationsAPI``

### Control Plane resources

- ``RecipesAPI``
- ``ConnectorsAPI``
- ``ConnectionsAPI``
- ``RepositoriesAPI``
- ``AnnotationsAPI``
- ``ProjectLabelsAPI``
- ``OrganizationsAPI``
- ``ProjectsAPI``
- ``MembersAPI``

### Transport and pagination

- ``HTTPClient``
- ``HTTPTransport``
- ``URLSessionTransport``
- ``Paginator``
- ``Page``
- ``JSONValue``
