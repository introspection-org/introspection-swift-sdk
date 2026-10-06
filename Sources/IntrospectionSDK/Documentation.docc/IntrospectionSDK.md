# ``IntrospectionSDK``

A Swift client for the Introspection platform: run agents on your runtimes, stream their answers, and read back tasks, files and conversations.

## Overview

Introspection splits into a Control Plane (organizations, projects, runtimes, recipes, connectors, experiments) and a Data Plane (tasks, runs, files, conversations, events, metrics). ``IntrospectionClient`` talks to both, and a ``Runner`` is a Data Plane connection bound to one runtime and one end user. Both expose the same Data Plane resources, declared by ``DataPlaneResources``.

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

The package has two products. `IntrospectionSDK`, documented here, is the client and has no OpenTelemetry dependency. `IntrospectionTelemetry` is opt-in: enable the `Telemetry` package trait and add the product to send custom events and gen_ai traces over OpenTelemetry, as the other Introspection SDKs do. See <doc:CustomEventsAndTelemetry>.

```swift
.package(url: "https://github.com/introspection-org/introspection-swift-sdk", branch: "main", traits: ["Telemetry"])
```

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:Authentication>
- <doc:RunsAndStreaming>
- <doc:ConfigurationAndObservability>
- <doc:CustomEventsAndTelemetry>
- ``IntrospectionClient``
- ``Runner``
- ``IntrospectionError``

### Signing in

- ``AuthClient``
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
- ``DataPlaneResources``

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

### App connections

The apps members connected for themselves, at `/v1/connections` on `client.connections` or `runner.connections`.
A member who is not an administrator only ever sees and changes their own. On a runner,
``AppConnectionsAPI/create(app:runtime:)`` connects the app for the runner's runtime group; on the client, pass
`runtime`. A connector's connections, which a business manages for its customers, are ``ConnectorsAPI/connections`` on
the Control Plane.

- ``AppConnectionsAPI``
- ``AppConnection``
- ``ConnectPage``

### Custom events

Written by the opt-in `IntrospectionTelemetry` product; read here.

- <doc:CustomEventsAndTelemetry>
- ``TrackPayload``
- ``EventListParams/names``
- ``LogAttributes``

### Automations

Scheduled prompts and platform work. A one-off reminder is a ``AutomationTriggerType/manual`` automation with a future
``AutomationCreate/nextTriggerAt``; set ``AutomationCreate/taskId`` to post each firing into an existing task. Each
trigger is recorded as an ``IntrospectionEventName/automationTriggered`` or ``IntrospectionEventName/automationSkipped``
event, read through ``EventsAPI`` with the `automationId` and `taskId` filters.
``AutomationListParams/taskId`` lists the automations that post into one task.

The server serves these routes to administrators only today; introspection-cloud#3137 opens them to members for
their own task-targeted automations.

- ``AutomationsAPI``
- ``Automation``
- ``AutomationCreate``
- ``AutomationUpdate``
- ``AutomationListParams``
- ``AutomationTriggerResponse``
- ``AutomationTriggeredPayload``
- ``AutomationSkippedPayload``

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
