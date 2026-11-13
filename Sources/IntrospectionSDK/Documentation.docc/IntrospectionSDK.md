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

The apps and accounts members connected for themselves, and the project's own grants, at `/v1/connections` on
`client.connections` or `runner.connections`: the one connections resource. A member who is not an administrator only
ever sees and changes their own. On a runner, ``AppConnectionsAPI/create(app:runtime:returnURL:)`` connects the app for
the runner's runtime group; on the client, pass `runtime`. ``AppConnectionsAPI/create(integration:returnURL:)`` connects
the member's own account through an organization integration such as Google Workspace.

- ``AppConnectionsAPI``
- ``AppConnection``
- ``AppConnectionListParams``
- ``AppConnectionOwner``
- ``AppConnectionConnector``
- ``ConnectPage``

### Custom events

Written by the opt-in `IntrospectionTelemetry` product; read here.

- <doc:CustomEventsAndTelemetry>
- ``TrackPayload``
- ``EventListParams/names``
- ``LogAttributes``

### Routines

Scheduled prompts and platform work. A one-off reminder is a ``RoutineTriggerType/manual`` routine with a future
``RoutineCreate/nextTriggerAt``; set ``RoutineCreate/taskId`` to post each firing into an existing task. Each
trigger is recorded as an ``IntrospectionEventName/routineTriggered`` or ``IntrospectionEventName/routineSkipped``
event, read through ``EventsAPI`` with the `routineId` and `taskId` filters.
``RoutineListParams/taskId`` lists the routines that post into one task.

A routine can also start a run on an event: ``RoutineCreate/triggers`` lists ``RoutineTriggerSpec``s on an
integration (Slack, GitHub) or on a project connector by slug, such as a `webhook` connector made with
``ConnectorCreate/webhook(name:slug:webhookAuth:environment:)``. A trigger's `parameters` read named values out of the
event's body by JSON pointer, and ``RoutinesAPI/trigger(_:parameters:)`` passes a manual run's parameters; either way
the prompt's `@parameters.<name>` references are replaced by their values. ``RoutineUpdate/triggers`` replaces the list,
keeping each entry that names an `id` (``RoutineTriggerSpec/init(keeping:)``).

The server serves these routes to administrators only today; introspection-cloud#3137 opens them to members for
their own task-targeted routines.

- ``RoutinesAPI``
- ``Routine``
- ``RoutineCreate``
- ``RoutineUpdate``
- ``RoutineListParams``
- ``RoutineTriggerResponse``
- ``RoutineTrigger``
- ``RoutineTriggerSpec``
- ``RoutineTriggerFilter``
- ``RoutineTriggerSource``
- ``RoutineTriggerProvider``
- ``RoutineTriggerEventType``
- ``RoutineTriggerEventRef``
- ``RoutineRunSource``
- ``RoutineTaskMetadataKeys``
- ``RoutineTriggeredPayload``
- ``RoutineSkippedPayload``

### Issues

Issues at `/v1/issues` on `client.issues` or `runner.issues`: a brief with its creator, assignee and reviewer. Its
people (``IssueMember``), attachments (files, links, events, spans) and comments come back only when a read names them
with ``IssueInclude``; a list that was not included is nil. `update` with an ``IssueUpdate`` applies the fields it
names, and the last write wins; pass ``Issue/etag`` as `ifMatch` to `update` or `delete` to have the write refused with
412 when the issue changed since it was read. To ask a person something, assign the issue, set it `waiting` and comment
with ``IssueCommentsAPI/create(_:comment:)``.

- ``IssuesAPI``
- ``IssueCommentsAPI``
- ``Issue``
- ``IssueMember``
- ``IssueMemberRelation``
- ``IssueComment``
- ``IssueInclude``
- ``IssueCreate``
- ``IssueUpdate``
- ``IssueListParams``

### Control Plane resources

- ``RecipesAPI``
- ``ConnectorsAPI``
- ``RepositoriesAPI``
- ``AnnotationsAPI``
- ``TagsAPI``
- ``OrganizationsAPI``
- ``ProjectsAPI``
- ``MembersAPI``

### Project administration

Each needs an org credential (a member session or access token) carrying the resource's `*:read` / `*:write` /
`*:delete` scope; a project API key carries none of them. A plaintext the API returns once or takes on write is a
``Secret``, which never prints.

- ``ApiKeysAPI``
- ``ApplicationsAPI``
- ``EndpointsAPI``
- ``EndpointCreate``
- ``RemotesAPI``
- ``ApplicationIdpsAPI``
- ``ApplicationSecretsAPI``
- ``ApplicationKeysAPI``
- ``CredentialsAPI``
- ``VariablesAPI``
- ``IntegrationsAPI``
- ``IntegrationAccessTokenRequest``
- ``IntegrationAccessToken``
- ``IntegrationRepositories``
- ``GitHubInstallationRepository``
- ``JudgesAPI``
- ``RuntimePeering``
- ``Secret``

### Evals

An eval task (``TaskKind/eval``, created with ``TaskCreate/commands`` set) runs compose services from ``ImagesAPI``
images and takes ``TaskCommandsAPI`` commands against its live sandbox.

- ``ImagesAPI``
- ``IntrospectionImage``
- ``ImageCreate``
- ``ImageSource``
- ``TaskCommandsAPI``
- ``TaskCommandSpec``
- ``TaskCommand``

### Transport and pagination

- ``HTTPClient``
- ``HTTPTransport``
- ``URLSessionTransport``
- ``Paginator``
- ``Page``
- ``JSONValue``
