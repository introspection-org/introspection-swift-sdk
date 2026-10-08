import Foundation

// The shared transcript projection: persisted GenAI spans and live AG-UI events fold into
// the same `[TranscriptEntry]`, and `mergeTranscripts` converges the two after a refresh.
// Tool status is execution status: an assistant `tool_call` part only proves the call was
// requested, so it folds as `running`; `complete`/`error` come from an ended `execute_tool`
// span, a `tool_call_response` part, or a live `TOOL_CALL_RESULT`.

/// Lifecycle of a tool call or delegation within a transcript.
public enum TranscriptStatus: String, Codable, Sendable, Hashable {
    case running
    case complete
    case error
}

/// Who wrote a transcript message.
public enum TranscriptRole: String, Codable, Sendable, Hashable {
    case user
    case assistant
}

/// A rendered chat message. `id` is stable across transports where the wire allows it.
public struct TranscriptMessageEntry: Codable, Sendable, Hashable {
    public var id: String
    public var role: TranscriptRole
    /// Concatenated text content.
    public var text: String
    /// Accumulated thinking / reasoning, when present.
    public var thinking: String?
    /// `gen_ai.response.id`, when known.
    public var responseId: String?
    /// `introspection.conversation.client_message_id`, when known.
    public var clientMessageId: String?
    /// Span the entry was folded from (stored transport only).
    public var spanId: String?

    public init(
        id: String, role: TranscriptRole, text: String, thinking: String? = nil, responseId: String? = nil,
        clientMessageId: String? = nil, spanId: String? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.thinking = thinking
        self.responseId = responseId
        self.clientMessageId = clientMessageId
        self.spanId = spanId
    }
}

/// One tool call and, once it arrived, its result. `callId` is the cross-transport key.
public struct TranscriptToolEntry: Codable, Sendable, Hashable {
    /// `tool:{callId}`.
    public var id: String
    public var callId: String
    public var name: String
    /// Raw JSON-encoded arguments, as far as they have streamed.
    public var arguments: String?
    public var result: JSONValue?
    public var status: TranscriptStatus
    public var spanId: String?

    public init(
        callId: String, name: String, status: TranscriptStatus = .running, arguments: String? = nil,
        result: JSONValue? = nil, spanId: String? = nil
    ) {
        id = "tool:\(callId)"
        self.callId = callId
        self.name = name
        self.status = status
        self.arguments = arguments
        self.result = result
        self.spanId = spanId
    }
}

/// One subagent invocation. Correlated by `invocationId`, then `sourceToolCallId`, then entry id;
/// `agentId` is a legacy fallback.
public struct TranscriptDelegationEntry: Codable, Sendable, Hashable {
    public var id: String
    /// Durable child agent-run id, the primary correlation key.
    public var invocationId: String?
    /// The `agent` tool call that launched the delegation (live transport).
    public var sourceToolCallId: String?
    /// The key a drill-in passes as the items `agent` filter.
    public var agentId: String?
    public var agentName: String?
    public var label: String?
    public var status: TranscriptStatus
    public var durationNs: Int64?
    public var spanId: String?

    public init(
        id: String, status: TranscriptStatus, invocationId: String? = nil, sourceToolCallId: String? = nil,
        agentId: String? = nil, agentName: String? = nil, label: String? = nil, durationNs: Int64? = nil,
        spanId: String? = nil
    ) {
        self.id = id
        self.status = status
        self.invocationId = invocationId
        self.sourceToolCallId = sourceToolCallId
        self.agentId = agentId
        self.agentName = agentName
        self.label = label
        self.durationNs = durationNs
        self.spanId = spanId
    }
}

/// One entry of a folded transcript, in render order.
public enum TranscriptEntry: Codable, Sendable, Hashable {
    case message(TranscriptMessageEntry)
    case tool(TranscriptToolEntry)
    case delegation(TranscriptDelegationEntry)

    public var id: String {
        switch self {
        case let .message(entry): return entry.id
        case let .tool(entry): return entry.id
        case let .delegation(entry): return entry.id
        }
    }

    public var message: TranscriptMessageEntry? {
        if case let .message(entry) = self { return entry }
        return nil
    }

    public var tool: TranscriptToolEntry? {
        if case let .tool(entry) = self { return entry }
        return nil
    }

    public var delegation: TranscriptDelegationEntry? {
        if case let .delegation(entry) = self { return entry }
        return nil
    }
}

private let delegationOperations: Set<String> = [GenAIOperationNames.invokeAgent, GenAIOperationNames.createAgent]
private let agentToolName = "agent"

/// The error bit a tool response carries, in the shapes emitters use.
private func responseIsError(_ value: JSONValue?) -> Bool {
    guard case let .object(record)? = value else { return false }
    if record["isError"] == .bool(true) { return true }
    if record["status"] == .string("error") { return true }
    switch record["error"] {
    case nil, .null?, .bool(false)?: return false
    case let .string(text)?: return !text.isEmpty
    case let .number(number)?: return number != 0 && !number.isNaN
    default: return true
    }
}

private func spanEnded(_ span: GenAISpan) -> Bool {
    span.endTime != nil || span.durationNs != nil
}

private func textOf(_ parts: [GenAIMessagePart]) -> String {
    parts.compactMap { part -> String? in
        if case let .text(text) = part { return text.content ?? "" }
        return nil
    }.joined(separator: "\n")
}

private func thinkingOf(_ parts: [GenAIMessagePart]) -> String {
    parts.compactMap { part -> String? in
        if case let .thinking(thinking) = part { return thinking.content ?? "" }
        return nil
    }.joined(separator: "\n")
}

private func jsonString(_ value: JSONValue) -> String {
    if case let .string(text) = value { return text }
    return (try? JSONCoding.encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? ""
}

private func parseObject(_ value: JSONValue?) -> JSONObject? {
    switch value {
    case let .object(object)?: return object
    case let .string(text)?:
        guard let data = text.data(using: .utf8),
            case let .object(object)? = try? JSONCoding.decoder.decode(JSONValue.self, from: data)
        else { return nil }
        return object
    default: return nil
    }
}

private struct ToolPatch {
    var name: String?
    var arguments: String?
    var result: JSONValue?
    var status: TranscriptStatus?
    var spanId: String?
}

/// Fold persisted conversation items into transcript entries, oldest first.
///
/// Spans may arrive in any page order. Within one span the order is user inputs, then one
/// assistant entry, then its tool calls in part order. A tool call seen from several sources
/// keeps its first position and merges the later fields onto it.
public func foldSpans(_ spans: [GenAISpan]) -> [TranscriptEntry] {
    let ordered = spans.enumerated().sorted { lhs, rhs in
        let left = lhs.element.startTime ?? .distantPast
        let right = rhs.element.startTime ?? .distantPast
        if left != right { return left < right }
        let leftId = lhs.element.spanId ?? ""
        let rightId = rhs.element.spanId ?? ""
        if leftId != rightId { return leftId < rightId }
        return lhs.offset < rhs.offset
    }.map(\.element)

    var entries: [TranscriptEntry] = []
    var toolIndex: [String: Int] = [:]

    func upsertTool(_ callId: String, _ patch: ToolPatch) {
        if let index = toolIndex[callId], case var .tool(existing) = entries[index] {
            if let name = patch.name, !name.isEmpty { existing.name = name }
            if let arguments = patch.arguments { existing.arguments = arguments }
            if let result = patch.result {
                existing.result = result
                // A failed execution stays failed: the next model call's input carries the refusal as plain text.
                existing.status = existing.status == .error ? .error : patch.status ?? .complete
            } else if let status = patch.status, status != .running {
                // Execution outcomes overwrite; a later `running` sighting never downgrades.
                existing.status = status
            }
            if let spanId = patch.spanId, !spanId.isEmpty { existing.spanId = spanId }
            entries[index] = .tool(existing)
            return
        }
        let entry = TranscriptToolEntry(
            callId: callId, name: patch.name ?? "", status: patch.status ?? .running,
            arguments: patch.arguments, result: patch.result, spanId: patch.spanId
        )
        toolIndex[callId] = entries.count
        entries.append(.tool(entry))
    }

    for span in ordered {
        let spanId = span.spanId
        let spanKey = spanId ?? span.traceId

        if let operation = span.operationName, delegationOperations.contains(operation) {
            let status: TranscriptStatus = span.status?.code == .error ? .error : (spanEnded(span) ? .complete : .running)
            entries.append(
                .delegation(
                    TranscriptDelegationEntry(
                        id: "span:\(spanKey):delegation", status: status, invocationId: span.invocationId,
                        agentId: span.agentId, agentName: span.agentName, durationNs: span.durationNs, spanId: spanId
                    )))
            continue
        }

        if let callId = span.toolCallId {
            let status: TranscriptStatus = spanEnded(span) ? (span.status?.code == .error ? .error : .complete) : .running
            upsertTool(callId, ToolPatch(name: span.toolName, arguments: span.toolCallArguments, status: status, spanId: spanId))
        }

        let inputMessages = span.inputMessages
        let clientMessageId = span.clientMessageId
        let userCount = inputMessages.filter { $0.role == .user }.count
        for (index, message) in inputMessages.enumerated() {
            if message.role == .user {
                let text = textOf(message.parts)
                if text.isEmpty { continue }
                // client_message_id names the optimistic user message only when the delta has one candidate.
                let stableId = (clientMessageId != nil && userCount == 1) ? clientMessageId ?? "" : "span:\(spanKey):user:\(index)"
                entries.append(
                    .message(
                        TranscriptMessageEntry(
                            id: stableId, role: .user, text: text, clientMessageId: clientMessageId, spanId: spanId
                        )))
            } else if message.role == .tool {
                for part in message.parts {
                    guard case let .toolCallResponse(response) = part, let id = response.id, !id.isEmpty else { continue }
                    upsertTool(
                        id,
                        ToolPatch(
                            name: response.name, result: response.response,
                            status: responseIsError(response.response) ? .error : .complete, spanId: spanId
                        ))
                }
            }
        }

        for (index, message) in span.outputMessages.enumerated() where message.role == .assistant {
            let text = textOf(message.parts)
            let thinking = thinkingOf(message.parts)
            if !text.isEmpty || !thinking.isEmpty {
                let responseId = span.responseId
                entries.append(
                    .message(
                        TranscriptMessageEntry(
                            id: responseId ?? "span:\(spanKey):assistant:\(index)", role: .assistant, text: text,
                            thinking: thinking.isEmpty ? nil : thinking, responseId: responseId, spanId: spanId
                        )))
            }
            for part in message.parts {
                guard case let .toolCall(call) = part, let id = call.id, !id.isEmpty else { continue }
                upsertTool(id, ToolPatch(name: call.name, arguments: call.arguments.map(jsonString), status: .running, spanId: spanId))
            }
        }
    }
    return entries
}

/// Incremental AG-UI to transcript fold for the live path. Push events as they stream and
/// read `entries` at any point. Activity and control frames go to the callbacks; unknown
/// event types are ignored.
public final class TranscriptAccumulator {
    public private(set) var entries: [TranscriptEntry] = []
    private var messageIndex: [String: Int] = [:]
    private var toolIndex: [String: Int] = [:]
    private var delegationIndex: [String: Int] = [:]
    private var lastAssistantIndex: Int?
    private var pendingThinking = ""
    private let onActivity: ((AGUIEvent) -> Void)?
    private let onControl: ((AGUIEvent) -> Void)?

    /// `onActivity` receives `ACTIVITY_SNAPSHOT`/`ACTIVITY_DELTA`; `onControl` receives every `CUSTOM` frame.
    public init(onActivity: ((AGUIEvent) -> Void)? = nil, onControl: ((AGUIEvent) -> Void)? = nil) {
        self.onActivity = onActivity
        self.onControl = onControl
    }

    /// Fold one event.
    public func push(_ event: AGUIEvent) {
        switch event.type {
        case "TEXT_MESSAGE_START":
            guard let messageId = event.messageId else { return }
            openMessage(messageId, role: event.role == "user" ? .user : .assistant)
        case "TEXT_MESSAGE_CONTENT":
            guard let messageId = event.messageId else { return }
            appendText(messageId, event.delta ?? "")
        case "TEXT_MESSAGE_CHUNK":
            guard let messageId = event.messageId, !messageId.isEmpty else { return }
            openMessage(messageId, role: event.role == "user" ? .user : .assistant)
            if let delta = event.delta, !delta.isEmpty { appendText(messageId, delta) }
        // Reasoning streams before the message it belongs to, so it buffers until the next assistant message opens.
        case "REASONING_MESSAGE_CONTENT", "REASONING_MESSAGE_CHUNK":
            if let delta = event.delta { pendingThinking += delta }
        case "THINKING_TEXT_MESSAGE_CONTENT":
            let delta = event.delta ?? ""
            if let index = lastAssistantIndex {
                updateMessage(at: index) { $0.thinking = ($0.thinking ?? "") + delta }
            } else {
                pendingThinking += delta
            }
        case "MESSAGES_SNAPSHOT":
            applyMessagesSnapshot(event)
        case "TOOL_CALL_START":
            guard let callId = event.toolCallId else { return }
            openTool(callId, name: event.toolCallName ?? "")
        case "TOOL_CALL_ARGS":
            guard let callId = event.toolCallId else { return }
            appendArgs(callId, event.delta ?? "")
        case "TOOL_CALL_CHUNK":
            guard let callId = event.toolCallId, !callId.isEmpty else { return }
            openTool(callId, name: event.toolCallName ?? "")
            if let delta = event.delta, !delta.isEmpty { appendArgs(callId, delta) }
        case "TOOL_CALL_END":
            // END seals the arguments only; execution is still in flight.
            guard let callId = event.toolCallId else { return }
            maybeConvertToDelegation(callId)
        case "TOOL_CALL_RESULT":
            guard let callId = event.toolCallId else { return }
            let isError = event.raw["isError"]?.boolValue == true
            maybeConvertToDelegation(callId)
            if let index = delegationIndex[callId] {
                applyDelegationLaunchResult(at: index, content: event.content, isError: isError)
                return
            }
            let index = openTool(callId, name: "")
            updateTool(at: index) {
                $0.result = event.content
                $0.status = isError ? .error : .complete
            }
        case "RUN_FINISHED", "RUN_ERROR":
            // A running delegation stays open: its completion is the child run's, not this run's.
            for index in toolIndex.values {
                updateTool(at: index) { if $0.status == .running { $0.status = .error } }
            }
            flushPendingThinking(event)
        case "ACTIVITY_SNAPSHOT", "ACTIVITY_DELTA":
            onActivity?(event)
        case "CUSTOM":
            if event.name == CustomEventNames.messageIdentity,
                let messageId = event.value?["messageId"]?.stringValue,
                let responseId = event.value?["responseId"]?.stringValue,
                let index = messageIndex[messageId]
            {
                updateMessage(at: index) { $0.responseId = responseId }
            }
            onControl?(event)
        default:
            return
        }
    }

    /// Fold a sequence of events.
    public func push<S: Sequence>(contentsOf events: S) where S.Element == AGUIEvent {
        for event in events { push(event) }
    }

    private func flushPendingThinking(_ event: AGUIEvent) {
        guard !pendingThinking.isEmpty else { return }
        let index = lastAssistantIndex ?? openMessage("\(event.runId ?? "run"):reasoning", role: .assistant)
        // openMessage drains the buffer itself when it opens an assistant entry.
        guard !pendingThinking.isEmpty else { return }
        let thinking = pendingThinking
        pendingThinking = ""
        updateMessage(at: index) { $0.thinking = ($0.thinking ?? "") + thinking }
    }

    @discardableResult
    private func openMessage(_ messageId: String, role: TranscriptRole) -> Int {
        if let index = messageIndex[messageId] { return index }
        var entry = TranscriptMessageEntry(id: messageId, role: role, text: "")
        let index = entries.count
        if role == .assistant {
            lastAssistantIndex = index
            if !pendingThinking.isEmpty {
                entry.thinking = pendingThinking
                pendingThinking = ""
            }
        }
        messageIndex[messageId] = index
        entries.append(.message(entry))
        return index
    }

    private func appendText(_ messageId: String, _ delta: String) {
        let index = messageIndex[messageId] ?? openMessage(messageId, role: .assistant)
        updateMessage(at: index) { $0.text += delta }
    }

    @discardableResult
    private func openTool(_ callId: String, name: String) -> Int {
        if let index = toolIndex[callId] {
            if !name.isEmpty { updateTool(at: index) { if $0.name.isEmpty { $0.name = name } } }
            return index
        }
        let index = entries.count
        toolIndex[callId] = index
        entries.append(.tool(TranscriptToolEntry(callId: callId, name: name)))
        return index
    }

    private func appendArgs(_ callId: String, _ delta: String) {
        let index = openTool(callId, name: "")
        updateTool(at: index) { $0.arguments = ($0.arguments ?? "") + delta }
    }

    private func updateMessage(at index: Int, _ body: (inout TranscriptMessageEntry) -> Void) {
        guard case var .message(entry) = entries[index] else { return }
        body(&entry)
        entries[index] = .message(entry)
    }

    private func updateTool(at index: Int, _ body: (inout TranscriptToolEntry) -> Void) {
        guard case var .tool(entry) = entries[index] else { return }
        body(&entry)
        entries[index] = .tool(entry)
    }

    private func updateDelegation(at index: Int, _ body: (inout TranscriptDelegationEntry) -> Void) {
        guard case var .delegation(entry) = entries[index] else { return }
        body(&entry)
        entries[index] = .delegation(entry)
    }

    /// A baseline upsert: known ids update in place, new ones append.
    private func applyMessagesSnapshot(_ event: AGUIEvent) {
        for message in event.raw["messages"]?.arrayValue ?? [] {
            guard let id = message["id"]?.stringValue, !id.isEmpty else { continue }
            let role = message["role"]?.stringValue
            if role == "user" || role == "assistant" {
                let index = openMessage(id, role: role == "user" ? .user : .assistant)
                if let content = message["content"]?.stringValue {
                    updateMessage(at: index) { $0.text = content }
                }
            }
            for call in message["toolCalls"]?.arrayValue ?? [] {
                guard let callId = call["id"]?.stringValue, !callId.isEmpty else { continue }
                let index = openTool(callId, name: call["function"]?["name"]?.stringValue ?? "")
                if let arguments = call["function"]?["arguments"]?.stringValue {
                    updateTool(at: index) { $0.arguments = arguments }
                }
            }
        }
    }

    /// An `agent` tool call whose sealed args are a `start` action converts in place to a delegation.
    private func maybeConvertToDelegation(_ callId: String) {
        guard let index = toolIndex[callId], case let .tool(tool) = entries[index], tool.name == agentToolName,
            let arguments = tool.arguments, let args = parseObject(.string(arguments))
        else { return }
        if let action = args["action"], action != .string("start") { return }
        entries[index] = .delegation(
            TranscriptDelegationEntry(
                id: "delegation-tool:\(callId)", status: .running, sourceToolCallId: callId,
                agentName: args["name"]?.stringValue, label: args["label"]?.stringValue
            ))
        toolIndex[callId] = nil
        delegationIndex[callId] = index
    }

    /// The `agent` tool's result means the child launched, not finished: it supplies the
    /// invocation id, and only a launch failure moves the status.
    private func applyDelegationLaunchResult(at index: Int, content: JSONValue?, isError: Bool) {
        if isError {
            updateDelegation(at: index) { $0.status = .error }
            return
        }
        guard let result = parseObject(content) else { return }
        let agent = result["details"]?["agent"]
        updateDelegation(at: index) { entry in
            if let invocationId = agent?["agent_run_id"]?.stringValue, !invocationId.isEmpty {
                entry.invocationId = invocationId
            }
            switch agent?["status"]?.stringValue {
            case "completed": entry.status = .complete
            case "failed", "error": entry.status = .error
            default: break
            }
        }
    }
}

/// One-shot fold of AG-UI events.
public func foldAgui<S: Sequence>(_ events: S) -> [TranscriptEntry] where S.Element == AGUIEvent {
    let accumulator = TranscriptAccumulator()
    accumulator.push(contentsOf: events)
    return accumulator.entries
}

private func messageKeys(_ entry: TranscriptMessageEntry) -> [String] {
    [entry.id] + [entry.responseId, entry.clientMessageId].compactMap { $0 }.filter { !$0.isEmpty }
}

/// Converge a live transcript onto its stored twin after a refresh. Stored entries win and keep
/// their order; a live entry survives only when nothing stored correlates with it (messages by any
/// id alias, tools by `callId`, delegations by invocation).
public func mergeTranscripts(stored: [TranscriptEntry], live: [TranscriptEntry]) -> [TranscriptEntry] {
    var storedMessageKeys = Set<String>()
    var toolCallIds = Set<String>()
    var delegationKeys = Set<String>()
    var legacyAgentIds = Set<String>()
    for entry in stored {
        switch entry {
        case let .message(message):
            storedMessageKeys.formUnion(messageKeys(message))
        case let .tool(tool):
            toolCallIds.insert(tool.callId)
        case let .delegation(delegation):
            delegationKeys.insert(delegation.id)
            if let invocationId = delegation.invocationId, !invocationId.isEmpty {
                delegationKeys.insert(invocationId)
            } else if let agentId = delegation.agentId, !agentId.isEmpty {
                legacyAgentIds.insert(agentId)
            }
            if let source = delegation.sourceToolCallId, !source.isEmpty { delegationKeys.insert(source) }
        }
    }
    let unmatched = live.filter { entry in
        switch entry {
        case let .message(message):
            return !messageKeys(message).contains { storedMessageKeys.contains($0) }
        case let .tool(tool):
            return !toolCallIds.contains(tool.callId)
        case let .delegation(delegation):
            if let invocationId = delegation.invocationId, !invocationId.isEmpty, delegationKeys.contains(invocationId) { return false }
            if let source = delegation.sourceToolCallId, !source.isEmpty, delegationKeys.contains(source) { return false }
            if delegationKeys.contains(delegation.id) { return false }
            let hasInvocation = !(delegation.invocationId ?? "").isEmpty
            if !hasInvocation, let agentId = delegation.agentId, !agentId.isEmpty, legacyAgentIds.contains(agentId) { return false }
            return true
        }
    }
    return stored + unmatched
}
