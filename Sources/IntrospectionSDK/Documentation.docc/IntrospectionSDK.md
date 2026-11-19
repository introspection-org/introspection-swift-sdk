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
- ``AGUIRunOutcomeType``
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

Scheduled prompts and platform work. A schedule is a ``RoutineTrigger/schedule(_:)`` trigger; a one-off reminder is a
routine with no schedule trigger and a future ``RoutineCreate/nextTriggerAt``; set ``RoutineCreate/taskId`` to post each firing into an existing task. Each
trigger is recorded as an ``IntrospectionEventName/routineTriggered`` or ``IntrospectionEventName/routineSkipped``
event, read through ``EventsAPI`` with the `routineId` and `taskId` filters.
``RoutineListParams/taskId`` lists the routines that post into one task.

A routine can also start a run on an event: ``RoutineCreate/triggers`` lists ``RoutineTrigger``s, discriminated on
`type`: an integration (Slack, GitHub, Linear) or a project connector by slug, such as a `webhook` connector made with
``ConnectorCreate/webhook(name:slug:environment:)``. An event-started run's parameters are the event's
body, and ``RoutinesAPI`` `trigger` passes a manual run's, uploaded as a file unless the routine is a platform routine
or posts into an existing task; either way the run reads them as `parameters.json` and the prompt's
`@parameters.<key>` references are replaced by their top-level values.
A `webhook` connector is created without a secret. Its secrets are a sub-resource, ``ConnectorsAPI/secrets``:
``ConnectorSecretsAPI/create(_:type:project:)`` issues the first, of a ``ConnectorSigningSecretType``, and later
rotates it, returning the plaintext once in ``WebhookSecretCreated``; the old one stays valid until
``ConnectorSecretsAPI/delete(_:secretId:project:)`` names it, and ``ConnectorSecretsAPI/list(_:_:)`` lists at most
two ``WebhookSecret``s, current first.
``RoutineUpdate/triggers`` replaces the list, keeping each entry that names an `id`. A `type` this SDK does not
model decodes as ``RoutineTrigger/unknown(type:id:raw:)`` and is sent back unchanged.

The server serves these routes to administrators only today; introspection-cloud#3137 opens them to members for
their own task-targeted routines.

- ``RoutinesAPI``
- ``Routine``
- ``RoutineCreate``
- ``RoutineUpdate``
- ``RoutineListParams``
- ``RoutineTriggerResponse``
- ``RoutineTrigger``
- ``RoutineScheduleTrigger``
- ``RoutineSlackTrigger``
- ``RoutineGitHubTrigger``
- ``RoutineLinearTrigger``
- ``RoutineWebhookTrigger``
- ``RoutineCondition``
- ``RoutineMetadata``
- ``RoutineTriggerEventType``
- ``RoutineTriggerEventRef``
- ``RoutineRunSource``
- ``RoutineTaskMetadataKeys``
- ``RoutineTriggeredPayload``
- ``RoutineSkippedPayload``

### Issues

Issues at `/v1/issues` on `client.issues` or `runner.issues`: a brief with its creator, assignee and reviewer. Its
people (``IssueMember``), attachments (``IssueAttachment``: links, files, events and spans) and comments come back only
when a read names them with ``IssueInclude``; a list that was not included is nil. `update` with an ``IssueUpdate``
applies the fields it names, and the last write wins; pass ``Issue/etag`` as `ifMatch` to `update` or `delete` to have
the write refused with 412 when the issue changed since it was read. ``IssueUpdate/addAttachments`` and
``IssueUpdate/removeAttachments`` change the evidence without reading the issue first. To ask a person something, assign the issue, set it `waiting` and comment
with ``IssueCommentsAPI/create(_:comment:)``.

- ``IssuesAPI``
- ``IssueCommentsAPI``
- ``Issue``
- ``IssueMember``
- ``IssueMemberRelation``
- ``IssueComment``
- ``IssueInclude``
- ``IssueAttachment``
- ``IssueAttachmentCreate``
- ``IssueLink``
- ``IssueFile``
- ``IssueEventReference``
- ``IssueSpanReference``
- ``IssueCreate``
- ``IssueUpdate``
- ``IssueListParams``

### Control Plane resources

- ``RecipesAPI``
- ``ConnectorsAPI``
- ``ConnectorSecretsAPI``
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
