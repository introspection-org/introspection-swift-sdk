import Foundation

/// OpenTelemetry GenAI semantic-convention span attributes, as the platform
/// stores them. Names mirror the JS SDK's `GenAi` constants.
public enum GenAIAttributes {
    public static let conversationId = "gen_ai.conversation.id"
    public static let agentId = "gen_ai.agent.id"
    public static let agentName = "gen_ai.agent.name"
    /// `chat`, `execute_tool`, `invoke_agent`, ... (see `GenAIOperationNames`).
    public static let operationName = "gen_ai.operation.name"
    public static let providerName = "gen_ai.provider.name"
    public static let requestModel = "gen_ai.request.model"
    public static let responseModel = "gen_ai.response.model"
    public static let responseId = "gen_ai.response.id"
    public static let responseFinishReasons = "gen_ai.response.finish_reasons"
    public static let usageInputTokens = "gen_ai.usage.input_tokens"
    public static let usageOutputTokens = "gen_ai.usage.output_tokens"
    public static let usageCacheReadInputTokens = "gen_ai.usage.cache_read.input_tokens"
    public static let usageCacheCreationInputTokens = "gen_ai.usage.cache_creation.input_tokens"
    public static let usageReasoningTokens = "gen_ai.usage.reasoning.output_tokens"
    /// Platform extension kept under `gen_ai.`: the call's computed cost in USD.
    public static let costUsd = "gen_ai.cost.usd"
    public static let inputMessages = "gen_ai.input.messages"
    public static let outputMessages = "gen_ai.output.messages"
    public static let systemInstructions = "gen_ai.system_instructions"
    public static let toolDefinitions = "gen_ai.tool.definitions"
    public static let toolName = "gen_ai.tool.name"
    public static let toolType = "gen_ai.tool.type"
    public static let toolDescription = "gen_ai.tool.description"
    public static let toolCallId = "gen_ai.tool.call.id"
    public static let toolCallArguments = "gen_ai.tool.call.arguments"
    public static let toolCallResult = "gen_ai.tool.call.result"
}

/// Values of `gen_ai.operation.name`.
public enum GenAIOperationNames {
    public static let chat = "chat"
    public static let executeTool = "execute_tool"
    public static let invokeAgent = "invoke_agent"
    public static let createAgent = "create_agent"
}

/// Introspection-namespaced span attributes, companions to `GenAIAttributes`.
public enum IntrospectionAttributes {
    /// The durable child agent-run id on a delegation span.
    public static let agentInvocationId = "introspection.agent.invocation_id"
    /// The client id of the turn's optimistic user message.
    public static let conversationClientMessageId = "introspection.conversation.client_message_id"
    /// Why a turn was aborted: `cancelled` or `awaiting_user`.
    public static let terminationReason = "introspection.termination_reason"
    /// Provider-reported cost of the call in USD.
    public static let llmCostUsd = "introspection.llm.cost_usd"
    /// Provider-reported upstream inference cost in USD.
    public static let llmUpstreamCostUsd = "introspection.llm.upstream_cost_usd"
}

/// The platform event families `/v1/events` serves (the values of `IntrospectionEventName`).
public enum PlatformEventNames {
    public static let annotation = "introspection.annotation"
    public static let feedback = "introspection.feedback"
    public static let observation = "introspection.observation"
    public static let observationClusteringRun = "introspection.observation_clustering.run"
    public static let judgement = "introspection.judgement"
    public static let pattern = "introspection.pattern"
    public static let patternAssignment = "introspection.pattern.assignment"
    public static let track = "introspection.track"
    public static let issue = "introspection.issue"
    public static let repositoryCreated = "introspection.repository.created"
    public static let repositoryPushed = "introspection.repository.pushed"
    public static let repositoryMerge = "introspection.repository.merge"
}

/// Names of AG-UI `CUSTOM` events on a run stream.
public enum CustomEventNames {
    /// Emitted by this SDK on each reconnect or readiness wait, when opted in.
    public static let reconnect = "introspection.reconnect"
    /// Sent by the server to map a live message id to its provider alias.
    public static let messageIdentity = "introspection.message_identity"
    /// Sent by the server when a disconnect outlived its replay buffer.
    public static let resumeGap = "resume_gap"
}
