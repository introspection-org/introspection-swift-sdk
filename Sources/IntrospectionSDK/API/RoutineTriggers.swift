import Foundation

// MARK: Enums

/// What a routine trigger listens to: an organization integration, or a project connector by slug.
public struct RoutineTriggerSource: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public init(from decoder: any Decoder) throws { rawValue = try decoder.singleString() }
    public func encode(to encoder: any Encoder) throws { try encoder.encodeSingle(rawValue) }

    /// The organization's platform app install (Slack, GitHub).
    public static let integration: RoutineTriggerSource = "integration"
    /// A project connector named by `connectorSlug`, such as a `webhook` connector.
    public static let connector: RoutineTriggerSource = "connector"
}

/// The provider whose events a routine trigger listens to.
public struct RoutineTriggerProvider: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public init(from decoder: any Decoder) throws { rawValue = try decoder.singleString() }
    public func encode(to encoder: any Encoder) throws { try encoder.encodeSingle(rawValue) }

    public static let slack: RoutineTriggerProvider = "slack"
    /// Refused by the server until Linear events are forwarded.
    public static let linear: RoutineTriggerProvider = "linear"
    public static let github: RoutineTriggerProvider = "github"
    /// A `webhook` connector: its event types are the sender's own names.
    public static let webhook: RoutineTriggerProvider = "webhook"
}

/// An event type a routine trigger names: `{provider}.{object}.{action}` from the platform's catalogue, or, for a
/// `webhook` connector, any name the sender uses.
public struct RoutineTriggerEventType: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public init(from decoder: any Decoder) throws { rawValue = try decoder.singleString() }
    public func encode(to encoder: any Encoder) throws { try encoder.encodeSingle(rawValue) }

    /// Every event type a connector delivers; it stands alone in `eventTypes`.
    public static let wildcard: RoutineTriggerEventType = "*"
    /// A webhook body with no string `type`.
    public static let webhookReceived: RoutineTriggerEventType = "webhook.received"
    /// Requires a `channelIds` filter.
    public static let slackMessagePosted: RoutineTriggerEventType = "slack.message.posted"
    public static let slackAppMentioned: RoutineTriggerEventType = "slack.app.mentioned"
    public static let slackReactionAdded: RoutineTriggerEventType = "slack.reaction.added"
    public static let linearIssueCreated: RoutineTriggerEventType = "linear.issue.created"
    public static let linearIssueStatusChanged: RoutineTriggerEventType = "linear.issue.status_changed"
    public static let linearCycleCompleted: RoutineTriggerEventType = "linear.cycle.completed"
    public static let githubPullRequestOpened: RoutineTriggerEventType = "github.pull_request.opened"
    public static let githubPullRequestMerged: RoutineTriggerEventType = "github.pull_request.merged"
    public static let githubIssueOpened: RoutineTriggerEventType = "github.issue.opened"
    public static let githubWorkflowRunFailed: RoutineTriggerEventType = "github.workflow_run.failed"
    public static let githubPush: RoutineTriggerEventType = "github.push"
}

/// What started a routine's run, stamped on its task's metadata as `trigger_source`.
public struct RoutineRunSource: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public init(from decoder: any Decoder) throws { rawValue = try decoder.singleString() }
    public func encode(to encoder: any Encoder) throws { try encoder.encodeSingle(rawValue) }

    public static let scheduled: RoutineRunSource = "scheduled"
    public static let manual: RoutineRunSource = "manual"
    /// An event trigger.
    public static let trigger: RoutineRunSource = "trigger"
}

// MARK: Models

/// A trigger's filter: every key set must contain the event's value for it. Each provider allows its own keys
/// (Slack `channelIds`, `emoji`; GitHub `repositoryIds`, `branches`; a webhook `payloadFields`).
public struct RoutineTriggerFilter: Codable, Sendable, Hashable {
    public var channelIds: [String]?
    public var emoji: [String]?
    public var teamIds: [String]?
    public var toStates: [String]?
    public var repositoryIds: [String]?
    public var branches: [String]?
    /// A webhook body's top-level scalars by key; a non-string value compares as its JSON (`true`, `42`).
    public var payloadFields: [String: [String]]?

    enum CodingKeys: String, CodingKey {
        case channelIds = "channel_ids"
        case emoji
        case teamIds = "team_ids"
        case toStates = "to_states"
        case repositoryIds = "repository_ids"
        case branches
        case payloadFields = "payload_fields"
    }

    public init(
        channelIds: [String]? = nil,
        emoji: [String]? = nil,
        teamIds: [String]? = nil,
        toStates: [String]? = nil,
        repositoryIds: [String]? = nil,
        branches: [String]? = nil,
        payloadFields: [String: [String]]? = nil
    ) {
        self.channelIds = channelIds
        self.emoji = emoji
        self.teamIds = teamIds
        self.toStates = toStates
        self.repositoryIds = repositoryIds
        self.branches = branches
        self.payloadFields = payloadFields
    }
}

/// A stored event trigger of a routine.
public struct RoutineTrigger: Codable, Sendable, Hashable {
    public let id: String
    public let routineId: String?
    public let orgId: String?
    public let projectId: String?
    public let source: RoutineTriggerSource
    public let provider: RoutineTriggerProvider
    /// The project connector, for a `connector` trigger.
    public let connectorSlug: String?
    public let eventTypes: [RoutineTriggerEventType]
    public let filter: RoutineTriggerFilter?
    /// Named values read from the event's body, `{name: JSON pointer}`, for `@parameters.<name>` in the prompt.
    public let parameters: [String: String]?
    public let enabled: Bool?
    public let createdAt: Date?
    public let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case routineId = "routine_id"
        case orgId = "org_id"
        case projectId = "project_id"
        case source, provider
        case connectorSlug = "connector_slug"
        case eventTypes = "event_types"
        case filter, parameters, enabled
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// One trigger in `RoutineCreate.triggers` / `RoutineUpdate.triggers`. With `id` it keeps that trigger, applying
/// the fields given; without one it is a new trigger. Only a prompt routine that starts a task per run takes triggers.
public struct RoutineTriggerSpec: Encodable, Sendable, Hashable {
    public var provider: RoutineTriggerProvider
    /// 1 to 50 distinct event types.
    public var eventTypes: [RoutineTriggerEventType]
    /// Server default `integration`.
    public var source: RoutineTriggerSource?
    /// Required for a `connector` trigger, and only for it.
    public var connectorSlug: String?
    public var filter: RoutineTriggerFilter?
    /// `{name: JSON pointer}`, at most 20: each name lowercase letters, digits and `_`, starting with a letter, up to
    /// 40; each pointer RFC 6901, up to 512 characters. A value resolves to a scalar or `null`.
    public var parameters: [String: String]?
    public var enabled: Bool?
    /// An existing trigger of this routine to keep (update only).
    public var id: String?

    enum CodingKeys: String, CodingKey {
        case id, source, provider
        case connectorSlug = "connector_slug"
        case eventTypes = "event_types"
        case filter, parameters, enabled
    }

    public init(
        provider: RoutineTriggerProvider,
        eventTypes: [RoutineTriggerEventType],
        source: RoutineTriggerSource? = nil,
        connectorSlug: String? = nil,
        filter: RoutineTriggerFilter? = nil,
        parameters: [String: String]? = nil,
        enabled: Bool? = nil,
        id: String? = nil
    ) {
        self.provider = provider
        self.eventTypes = eventTypes
        self.source = source
        self.connectorSlug = connectorSlug
        self.filter = filter
        self.parameters = parameters
        self.enabled = enabled
        self.id = id
    }

    /// A trigger on a project connector by its slug, such as a `webhook` connector's.
    public static func connector(
        _ connectorSlug: String,
        eventTypes: [RoutineTriggerEventType],
        provider: RoutineTriggerProvider = .webhook,
        filter: RoutineTriggerFilter? = nil,
        parameters: [String: String]? = nil,
        enabled: Bool? = nil
    ) -> RoutineTriggerSpec {
        RoutineTriggerSpec(
            provider: provider, eventTypes: eventTypes, source: .connector, connectorSlug: connectorSlug, filter: filter,
            parameters: parameters, enabled: enabled)
    }

    /// The spec that keeps a stored trigger as it is; a `RoutineUpdate.triggers` list drops every trigger it omits.
    public init(keeping trigger: RoutineTrigger) {
        self.init(
            provider: trigger.provider, eventTypes: trigger.eventTypes, source: trigger.source, connectorSlug: trigger.connectorSlug,
            filter: trigger.filter, parameters: trigger.parameters, enabled: trigger.enabled, id: trigger.id)
    }
}

/// The event trigger a run or skip answered: which trigger, the event type and its delivery.
public struct RoutineTriggerEventRef: Codable, Sendable, Hashable {
    public var triggerId: String?
    public var eventType: String?
    /// `{provider}:{event id}`: what a redelivery repeats.
    public var deliveryId: String?

    enum CodingKeys: String, CodingKey {
        case triggerId = "trigger_id"
        case eventType = "event_type"
        case deliveryId = "delivery_id"
    }
}

/// Body of `POST /v1/routines/{id}/trigger`.
struct RoutineTriggerRequest: Encodable {
    let parameters: JSONObject
}

// MARK: Task metadata

/// Platform-owned task metadata keys a routine's run carries; a client metadata patch may not set them.
public enum RoutineTaskMetadataKeys {
    /// The run's ``RoutineRunSource``.
    public static let triggerSource = "trigger_source"
    /// The ``RoutineTriggerEventRef`` of a `trigger`-sourced run.
    public static let routineTrigger = "routine_trigger"
    /// Each `@parameters.<name>` the prompt referenced that had no value, and so received `null`.
    public static let unresolvedParameters = "unresolved_parameters"
}

extension IntrospectionTask {
    /// What started this routine run; nil for a task no routine started.
    public var routineRunSource: RoutineRunSource? {
        metadata?[RoutineTaskMetadataKeys.triggerSource]?.stringValue.map(RoutineRunSource.init(rawValue:))
    }

    /// The event trigger and delivery that started this run, when one did.
    public var routineTrigger: RoutineTriggerEventRef? {
        guard let value = metadata?[RoutineTaskMetadataKeys.routineTrigger] else { return nil }
        return try? value.decode(RoutineTriggerEventRef.self)
    }

    /// The `@parameters.<name>` references in this run's prompt that resolved to `null`.
    public var unresolvedParameters: [String]? {
        metadata?[RoutineTaskMetadataKeys.unresolvedParameters]?.arrayValue?.compactMap(\.stringValue)
    }
}
