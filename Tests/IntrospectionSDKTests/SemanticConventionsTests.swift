import Foundation
import Testing

@testable import IntrospectionSDK

/// Pins every semantic-convention name the SDK reads. These strings are a wire
/// contract with the platform and the other SDKs, so changing one must fail here.
@Suite struct SemanticConventionsTests {
    /// The platform's event-family registry, copied from `IntrospectionEventName` in
    /// `apps/dataplane-api/introspection_dataplane/models/events/names.py` (introspection-cloud),
    /// in declaration order. The SDK's set must equal it, like the platform's own
    /// registry test-lock in `tests/test_event_models.py`.
    static let platformEventNames = [
        "introspection.annotation",
        "introspection.feedback",
        "introspection.observation",
        "introspection.observation_clustering.run",
        "introspection.judgement",
        "introspection.pattern",
        "introspection.pattern.assignment",
        "introspection.track",
        "introspection.issue",
        "introspection.repository.created",
        "introspection.repository.pushed",
        "introspection.repository.merge",
        "introspection.automation.triggered",
        "introspection.automation.skipped",
    ]

    @Test func eventNamesMatchThePlatformRegistry() {
        #expect(IntrospectionEventName.allCases.map(\.rawValue) == Self.platformEventNames)
        #expect(Set(IntrospectionEventName.allCases).count == Self.platformEventNames.count)

        #expect(PlatformEventNames.annotation == "introspection.annotation")
        #expect(PlatformEventNames.feedback == "introspection.feedback")
        #expect(PlatformEventNames.observation == "introspection.observation")
        #expect(PlatformEventNames.observationClusteringRun == "introspection.observation_clustering.run")
        #expect(PlatformEventNames.judgement == "introspection.judgement")
        #expect(PlatformEventNames.pattern == "introspection.pattern")
        #expect(PlatformEventNames.patternAssignment == "introspection.pattern.assignment")
        #expect(PlatformEventNames.track == "introspection.track")
        #expect(PlatformEventNames.issue == "introspection.issue")
        #expect(PlatformEventNames.repositoryCreated == "introspection.repository.created")
        #expect(PlatformEventNames.repositoryPushed == "introspection.repository.pushed")
        #expect(PlatformEventNames.repositoryMerge == "introspection.repository.merge")
        #expect(PlatformEventNames.automationTriggered == "introspection.automation.triggered")
        #expect(PlatformEventNames.automationSkipped == "introspection.automation.skipped")

        #expect(IntrospectionEventName.annotation.rawValue == PlatformEventNames.annotation)
        #expect(IntrospectionEventName.feedback.rawValue == PlatformEventNames.feedback)
        #expect(IntrospectionEventName.observation.rawValue == PlatformEventNames.observation)
        #expect(IntrospectionEventName.observationClusteringRun.rawValue == PlatformEventNames.observationClusteringRun)
        #expect(IntrospectionEventName.judgement.rawValue == PlatformEventNames.judgement)
        #expect(IntrospectionEventName.pattern.rawValue == PlatformEventNames.pattern)
        #expect(IntrospectionEventName.patternAssignment.rawValue == PlatformEventNames.patternAssignment)
        #expect(IntrospectionEventName.track.rawValue == PlatformEventNames.track)
        #expect(IntrospectionEventName.issue.rawValue == PlatformEventNames.issue)
        #expect(IntrospectionEventName.repositoryCreated.rawValue == PlatformEventNames.repositoryCreated)
        #expect(IntrospectionEventName.repositoryPushed.rawValue == PlatformEventNames.repositoryPushed)
        #expect(IntrospectionEventName.repositoryMerge.rawValue == PlatformEventNames.repositoryMerge)
        #expect(IntrospectionEventName.automationTriggered.rawValue == PlatformEventNames.automationTriggered)
        #expect(IntrospectionEventName.automationSkipped.rawValue == PlatformEventNames.automationSkipped)
    }

    /// The attributes the processor and the `introspection.track` projection read; the same in every SDK.
    @Test func customEventLogAttributes() {
        #expect(LogAttributes.eventName == "event.name")
        #expect(LogAttributes.eventId == "event.id")
        #expect(LogAttributes.identityUserId == "identity.user.id")
        #expect(LogAttributes.identityAnonymousId == "identity.anonymous.id")
        #expect(LogAttributes.propertiesPrefix == "properties.")
        #expect(LogAttributes.reservedEventNamePrefixes == ["introspection.", "gen_ai."])
    }

    @Test func genAIAttributes() {
        #expect(GenAIAttributes.conversationId == "gen_ai.conversation.id")
        #expect(GenAIAttributes.agentId == "gen_ai.agent.id")
        #expect(GenAIAttributes.agentName == "gen_ai.agent.name")
        #expect(GenAIAttributes.operationName == "gen_ai.operation.name")
        #expect(GenAIAttributes.providerName == "gen_ai.provider.name")
        #expect(GenAIAttributes.requestModel == "gen_ai.request.model")
        #expect(GenAIAttributes.responseModel == "gen_ai.response.model")
        #expect(GenAIAttributes.responseId == "gen_ai.response.id")
        #expect(GenAIAttributes.responseFinishReasons == "gen_ai.response.finish_reasons")
        #expect(GenAIAttributes.usageInputTokens == "gen_ai.usage.input_tokens")
        #expect(GenAIAttributes.usageOutputTokens == "gen_ai.usage.output_tokens")
        #expect(GenAIAttributes.usageCacheReadInputTokens == "gen_ai.usage.cache_read.input_tokens")
        #expect(GenAIAttributes.usageCacheCreationInputTokens == "gen_ai.usage.cache_creation.input_tokens")
        #expect(GenAIAttributes.usageReasoningTokens == "gen_ai.usage.reasoning.output_tokens")
        #expect(GenAIAttributes.costUsd == "gen_ai.cost.usd")
        #expect(GenAIAttributes.inputMessages == "gen_ai.input.messages")
        #expect(GenAIAttributes.outputMessages == "gen_ai.output.messages")
        #expect(GenAIAttributes.systemInstructions == "gen_ai.system_instructions")
        #expect(GenAIAttributes.toolDefinitions == "gen_ai.tool.definitions")
        #expect(GenAIAttributes.toolName == "gen_ai.tool.name")
        #expect(GenAIAttributes.toolType == "gen_ai.tool.type")
        #expect(GenAIAttributes.toolDescription == "gen_ai.tool.description")
        #expect(GenAIAttributes.toolCallId == "gen_ai.tool.call.id")
        #expect(GenAIAttributes.toolCallArguments == "gen_ai.tool.call.arguments")
        #expect(GenAIAttributes.toolCallResult == "gen_ai.tool.call.result")
    }

    @Test func genAIOperationNames() {
        #expect(GenAIOperationNames.chat == "chat")
        #expect(GenAIOperationNames.executeTool == "execute_tool")
        #expect(GenAIOperationNames.invokeAgent == "invoke_agent")
        #expect(GenAIOperationNames.createAgent == "create_agent")
    }

    @Test func introspectionAttributes() {
        #expect(IntrospectionAttributes.agentInvocationId == "introspection.agent.invocation_id")
        #expect(IntrospectionAttributes.conversationClientMessageId == "introspection.conversation.client_message_id")
        #expect(IntrospectionAttributes.terminationReason == "introspection.termination_reason")
        #expect(IntrospectionAttributes.llmCostUsd == "introspection.llm.cost_usd")
        #expect(IntrospectionAttributes.llmUpstreamCostUsd == "introspection.llm.upstream_cost_usd")
    }

    @Test func customEventNames() {
        #expect(CustomEventNames.reconnect == "introspection.reconnect")
        #expect(CustomEventNames.messageIdentity == "introspection.message_identity")
        #expect(CustomEventNames.resumeGap == "resume_gap")
        #expect(AGUIEvent.reconnectEventName == CustomEventNames.reconnect)
        #expect(AGUIEvent.resumeGapEventName == CustomEventNames.resumeGap)
    }

    @Test func includesReuseTheAttributeNames() {
        #expect(ConversationItemInclude.systemInstructions.rawValue == GenAIAttributes.systemInstructions)
        #expect(ConversationItemInclude.toolDefinitions.rawValue == GenAIAttributes.toolDefinitions)
    }

    @Test func spanAccessorsReadTheConventions() throws {
        let span = GenAISpan(
            traceId: "tr",
            attributes: [
                "gen_ai": [
                    "operation": ["name": "chat"], "usage": ["input_tokens": 3], "cost": ["usd": 0.5],
                ],
                "introspection": ["agent": ["invocation_id": "inv-1"], "conversation": ["client_message_id": "m-1"]],
            ])
        #expect(span.operationName == GenAIOperationNames.chat)
        #expect(span.inputTokens == 3)
        #expect(span.costUsd == 0.5)
        #expect(span.invocationId == "inv-1")
        #expect(span.clientMessageId == "m-1")
    }
}
