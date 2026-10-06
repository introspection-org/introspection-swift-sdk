/// The Data Plane resources an ``IntrospectionClient`` and a ``Runner`` both expose, so code written against
/// one works with the other.
///
/// Each namespace sends the conforming type's own credential: the client's, or the runner's session token.
/// What that credential may do is the platform's to decide; a call it does not allow is refused with a 403.
public protocol DataPlaneResources: DataPlaneConnection {
    /// Tasks and their runs (`/v1/tasks`).
    var tasks: TasksAPI { get }
    /// Project files (`/v1/files`).
    var files: FilesAPI { get }
    /// Read-only conversations and their GenAI span items (`/v1/conversations`).
    var conversations: ConversationsAPI { get }
    /// Platform events (`/v1/events`).
    var events: EventsAPI { get }
    /// Telemetry aggregation (`/v1/metrics`).
    var metrics: MetricsAPI { get }
    /// Read-sharing grants for files and conversations (`/v1/shares`).
    var shares: SharesAPI { get }
    /// Scheduled prompts and platform work (`/v1/automations`).
    var automations: AutomationsAPI { get }
    /// The apps members connected for themselves (`/v1/connections`).
    var connections: AppConnectionsAPI { get }
}

extension IntrospectionClient: DataPlaneResources {
    /// App connections. ``AppConnectionsAPI/create(app:runtime:)`` needs `runtime` here.
    public var connections: AppConnectionsAPI { AppConnectionsAPI(http: dataPlane) }
}

extension Runner: DataPlaneResources {
    /// App connections; ``AppConnectionsAPI/create(app:runtime:)`` defaults to this runner's runtime group.
    public var connections: AppConnectionsAPI { AppConnectionsAPI(http: dataPlane, defaultRuntime: runtimeGroupId) }
}
