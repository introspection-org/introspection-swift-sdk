#if Telemetry
import Foundation

/// The identity, conversation and agent scoped on the current task. Every span ended and every event logged
/// inside a scope carries it, as OpenTelemetry baggage does in the other SDKs.
public struct TelemetryContext: Sendable, Hashable {
    public var userId: String?
    public var anonymousId: String?
    public var conversationId: String?
    public var previousResponseId: String?
    public var agentName: String?
    public var agentId: String?

    public init(
        userId: String? = nil, anonymousId: String? = nil, conversationId: String? = nil, previousResponseId: String? = nil,
        agentName: String? = nil, agentId: String? = nil
    ) {
        self.userId = userId
        self.anonymousId = anonymousId
        self.conversationId = conversationId
        self.previousResponseId = previousResponseId
        self.agentName = agentName
        self.agentId = agentId
    }

    /// The scope of the current task.
    @TaskLocal public static var current = TelemetryContext()

    /// A new conversation id, `intro_conv_<32 hex>`, the shape the other SDKs mint.
    public static func newConversationId() -> String {
        "intro_conv_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    func with(_ change: (inout TelemetryContext) -> Void) -> TelemetryContext {
        var copy = self
        change(&copy)
        return copy
    }
}

extension IntrospectionTelemetry {
    /// Run `operation` as the end user `userId` (`withUserId` in the other SDKs).
    public static func withUserId<T>(_ userId: String, operation: () async throws -> T) async rethrows -> T {
        try await TelemetryContext.$current.withValue(TelemetryContext.current.with { $0.userId = userId }, operation: operation)
    }

    /// Run `operation` as the end user `userId`.
    public static func withUserId<T>(_ userId: String, operation: () throws -> T) rethrows -> T {
        try TelemetryContext.$current.withValue(TelemetryContext.current.with { $0.userId = userId }, operation: operation)
    }

    /// Run `operation` as the anonymous visitor `anonymousId` (`withAnonymousId`).
    public static func withAnonymousId<T>(_ anonymousId: String, operation: () async throws -> T) async rethrows -> T {
        try await TelemetryContext.$current.withValue(TelemetryContext.current.with { $0.anonymousId = anonymousId }, operation: operation)
    }

    /// Run `operation` as the anonymous visitor `anonymousId`.
    public static func withAnonymousId<T>(_ anonymousId: String, operation: () throws -> T) rethrows -> T {
        try TelemetryContext.$current.withValue(TelemetryContext.current.with { $0.anonymousId = anonymousId }, operation: operation)
    }

    /// Run `operation` in a conversation (`withConversation`); a nil id mints one. `operation` receives the id.
    public static func withConversation<T>(
        _ conversationId: String? = nil, previousResponseId: String? = nil, operation: (String) async throws -> T
    ) async rethrows -> T {
        let id = conversationId ?? TelemetryContext.newConversationId()
        let scoped = TelemetryContext.current.with {
            $0.conversationId = id
            $0.previousResponseId = previousResponseId
        }
        return try await TelemetryContext.$current.withValue(scoped) { try await operation(id) }
    }

    /// Run `operation` in a conversation; a nil id mints one. `operation` receives the id.
    public static func withConversation<T>(
        _ conversationId: String? = nil, previousResponseId: String? = nil, operation: (String) throws -> T
    ) rethrows -> T {
        let id = conversationId ?? TelemetryContext.newConversationId()
        let scoped = TelemetryContext.current.with {
            $0.conversationId = id
            $0.previousResponseId = previousResponseId
        }
        return try TelemetryContext.$current.withValue(scoped) { try operation(id) }
    }

    /// Run `operation` as the agent `name` (`withAgent`).
    public static func withAgent<T>(_ name: String, id: String? = nil, operation: () async throws -> T) async rethrows -> T {
        let scoped = TelemetryContext.current.with {
            $0.agentName = name
            $0.agentId = id
        }
        return try await TelemetryContext.$current.withValue(scoped, operation: operation)
    }

    /// Run `operation` as the agent `name`.
    public static func withAgent<T>(_ name: String, id: String? = nil, operation: () throws -> T) rethrows -> T {
        let scoped = TelemetryContext.current.with {
            $0.agentName = name
            $0.agentId = id
        }
        return try TelemetryContext.$current.withValue(scoped, operation: operation)
    }
}
#endif
