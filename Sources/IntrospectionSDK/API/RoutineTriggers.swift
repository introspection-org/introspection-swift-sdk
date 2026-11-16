import Foundation

// MARK: Enums

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

/// What starts a routine besides Run now: a schedule or an event, discriminated on `type`. A response entry always
/// carries `id`; in `RoutineCreate.triggers` / `RoutineUpdate.triggers` an `id` keeps that trigger and none adds one.
public enum RoutineTrigger: Codable, Sendable, Hashable {
    case schedule(RoutineScheduleTrigger)
    case slack(RoutineSlackTrigger)
    case github(RoutineGitHubTrigger)
    case linear(RoutineLinearTrigger)
    case webhook(RoutineWebhookTrigger)
    /// A `type` this SDK does not model, as received; sent back unchanged in an update.
    case unknown(type: String, id: String?, raw: JSONObject)

    private enum CodingKeys: String, CodingKey { case type, id }

    /// The trigger's id; nil on a new one.
    public var id: String? {
        switch self {
        case let .schedule(trigger): return trigger.id
        case let .slack(trigger): return trigger.id
        case let .github(trigger): return trigger.id
        case let .linear(trigger): return trigger.id
        case let .webhook(trigger): return trigger.id
        case let .unknown(_, id, _): return id
        }
    }

    /// The wire `type`.
    public var type: String {
        switch self {
        case .schedule: return "schedule"
        case .slack: return "slack"
        case .github: return "github"
        case .linear: return "linear"
        case .webhook: return "webhook"
        case let .unknown(type, _, _): return type
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "schedule": self = .schedule(try RoutineScheduleTrigger(from: decoder))
        case "slack": self = .slack(try RoutineSlackTrigger(from: decoder))
        case "github": self = .github(try RoutineGitHubTrigger(from: decoder))
        case "linear": self = .linear(try RoutineLinearTrigger(from: decoder))
        case "webhook": self = .webhook(try RoutineWebhookTrigger(from: decoder))
        default:
            self = .unknown(type: type, id: try container.decodeIfPresent(String.self, forKey: .id), raw: try JSONObject(from: decoder))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        if case let .unknown(_, _, raw) = self {
            try JSONValue.object(raw).encode(to: encoder)
            return
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        switch self {
        case let .schedule(trigger): try trigger.encode(to: encoder)
        case let .slack(trigger): try trigger.encode(to: encoder)
        case let .github(trigger): try trigger.encode(to: encoder)
        case let .linear(trigger): try trigger.encode(to: encoder)
        case let .webhook(trigger): try trigger.encode(to: encoder)
        case .unknown: break
        }
    }
}

/// A `schedule` trigger: a 5-field cron expression.
public struct RoutineScheduleTrigger: Codable, Sendable, Hashable {
    public var id: String?
    public var cron: String
    /// IANA time zone the cron is evaluated in; UTC when unset.
    public var timezone: String?
    /// Skip a slot once the routine's member has had no turn in a conversation they started in the project for
    /// this many seconds (3600...31536000). `nil` leaves it out, so a kept schedule keeps its stored value;
    /// `.some(nil)` sends `null`, which clears it.
    public var memberIdleSeconds: Int??

    enum CodingKeys: String, CodingKey {
        case id, cron, timezone
        case memberIdleSeconds = "member_idle_seconds"
    }

    public init(cron: String, timezone: String? = nil, id: String? = nil) {
        self.cron = cron
        self.timezone = timezone
        self.id = id
    }

    /// This schedule with its idle window set, or cleared with `nil`.
    public func memberIdle(seconds: Int?) -> RoutineScheduleTrigger {
        var copy = self
        copy.memberIdleSeconds = .some(seconds)
        return copy
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        cron = try container.decode(String.self, forKey: .cron)
        timezone = try container.decodeIfPresent(String.self, forKey: .timezone)
        memberIdleSeconds = try container.decodeIfPresent(Int.self, forKey: .memberIdleSeconds).map { .some($0) }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(cron, forKey: .cron)
        try container.encodeIfPresent(timezone, forKey: .timezone)
        // An omitted key keeps the stored window; an explicit null clears it.
        if let memberIdleSeconds { try container.encode(memberIdleSeconds, forKey: .memberIdleSeconds) }
    }
}

/// A `slack` trigger. `channelIds` is required for `slack.message.posted`.
public struct RoutineSlackTrigger: Codable, Sendable, Hashable {
    public var id: String?
    public var eventTypes: [RoutineTriggerEventType]
    public var channelIds: [String]?
    public var emoji: [String]?

    enum CodingKeys: String, CodingKey {
        case id, emoji
        case eventTypes = "event_types"
        case channelIds = "channel_ids"
    }

    public init(eventTypes: [RoutineTriggerEventType], channelIds: [String]? = nil, emoji: [String]? = nil, id: String? = nil) {
        self.eventTypes = eventTypes
        self.channelIds = channelIds
        self.emoji = emoji
        self.id = id
    }
}

/// A `github` trigger.
public struct RoutineGitHubTrigger: Codable, Sendable, Hashable {
    public var id: String?
    public var eventTypes: [RoutineTriggerEventType]
    public var repositoryIds: [String]?
    public var branches: [String]?

    enum CodingKeys: String, CodingKey {
        case id, branches
        case eventTypes = "event_types"
        case repositoryIds = "repository_ids"
    }

    public init(
        eventTypes: [RoutineTriggerEventType], repositoryIds: [String]? = nil, branches: [String]? = nil, id: String? = nil
    ) {
        self.eventTypes = eventTypes
        self.repositoryIds = repositoryIds
        self.branches = branches
        self.id = id
    }
}

/// A `linear` trigger, scoped to the project's bound Linear teams.
public struct RoutineLinearTrigger: Codable, Sendable, Hashable {
    public var id: String?
    public var eventTypes: [RoutineTriggerEventType]
    public var toStates: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case eventTypes = "event_types"
        case toStates = "to_states"
    }

    public init(eventTypes: [RoutineTriggerEventType], toStates: [String]? = nil, id: String? = nil) {
        self.eventTypes = eventTypes
        self.toStates = toStates
        self.id = id
    }
}

/// A `webhook` trigger on a project connector by its slug; its event types are the sender's own names, or `*` alone.
public struct RoutineWebhookTrigger: Codable, Sendable, Hashable {
    public var id: String?
    public var connectorSlug: String
    public var eventTypes: [RoutineTriggerEventType]
    /// A webhook body's top-level scalars by key; a non-string value compares as its JSON (`true`, `42`).
    public var payloadFields: [String: [String]]?

    enum CodingKeys: String, CodingKey {
        case id
        case connectorSlug = "connector_slug"
        case eventTypes = "event_types"
        case payloadFields = "payload_fields"
    }

    public init(
        connectorSlug: String, eventTypes: [RoutineTriggerEventType], payloadFields: [String: [String]]? = nil, id: String? = nil
    ) {
        self.connectorSlug = connectorSlug
        self.eventTypes = eventTypes
        self.payloadFields = payloadFields
        self.id = id
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
    let parameters: JSONObject?
    let files: [TaskFileRef]?
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
