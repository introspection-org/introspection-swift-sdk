import Foundation
import XCTest

@testable import IntrospectionSDK

/// Pins every semantic-convention name the SDK reads. These strings are a wire
/// contract with the platform and the other SDKs, so changing one must fail here.
final class SemanticConventionsTests: XCTestCase {
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
    ]

    func testEventNamesMatchThePlatformRegistry() {
        XCTAssertEqual(IntrospectionEventName.allCases.map(\.rawValue), Self.platformEventNames)
        XCTAssertEqual(Set(IntrospectionEventName.allCases).count, Self.platformEventNames.count)

        XCTAssertEqual(PlatformEventNames.annotation, "introspection.annotation")
        XCTAssertEqual(PlatformEventNames.feedback, "introspection.feedback")
        XCTAssertEqual(PlatformEventNames.observation, "introspection.observation")
        XCTAssertEqual(PlatformEventNames.observationClusteringRun, "introspection.observation_clustering.run")
        XCTAssertEqual(PlatformEventNames.judgement, "introspection.judgement")
        XCTAssertEqual(PlatformEventNames.pattern, "introspection.pattern")
        XCTAssertEqual(PlatformEventNames.patternAssignment, "introspection.pattern.assignment")
        XCTAssertEqual(PlatformEventNames.track, "introspection.track")
        XCTAssertEqual(PlatformEventNames.issue, "introspection.issue")
        XCTAssertEqual(PlatformEventNames.repositoryCreated, "introspection.repository.created")
        XCTAssertEqual(PlatformEventNames.repositoryPushed, "introspection.repository.pushed")
        XCTAssertEqual(PlatformEventNames.repositoryMerge, "introspection.repository.merge")

        XCTAssertEqual(IntrospectionEventName.annotation.rawValue, PlatformEventNames.annotation)
        XCTAssertEqual(IntrospectionEventName.feedback.rawValue, PlatformEventNames.feedback)
        XCTAssertEqual(IntrospectionEventName.observation.rawValue, PlatformEventNames.observation)
        XCTAssertEqual(IntrospectionEventName.observationClusteringRun.rawValue, PlatformEventNames.observationClusteringRun)
        XCTAssertEqual(IntrospectionEventName.judgement.rawValue, PlatformEventNames.judgement)
        XCTAssertEqual(IntrospectionEventName.pattern.rawValue, PlatformEventNames.pattern)
        XCTAssertEqual(IntrospectionEventName.patternAssignment.rawValue, PlatformEventNames.patternAssignment)
        XCTAssertEqual(IntrospectionEventName.track.rawValue, PlatformEventNames.track)
        XCTAssertEqual(IntrospectionEventName.issue.rawValue, PlatformEventNames.issue)
        XCTAssertEqual(IntrospectionEventName.repositoryCreated.rawValue, PlatformEventNames.repositoryCreated)
        XCTAssertEqual(IntrospectionEventName.repositoryPushed.rawValue, PlatformEventNames.repositoryPushed)
        XCTAssertEqual(IntrospectionEventName.repositoryMerge.rawValue, PlatformEventNames.repositoryMerge)
    }

    func testGenAIAttributes() {
        XCTAssertEqual(GenAIAttributes.conversationId, "gen_ai.conversation.id")
        XCTAssertEqual(GenAIAttributes.agentId, "gen_ai.agent.id")
        XCTAssertEqual(GenAIAttributes.agentName, "gen_ai.agent.name")
        XCTAssertEqual(GenAIAttributes.operationName, "gen_ai.operation.name")
        XCTAssertEqual(GenAIAttributes.providerName, "gen_ai.provider.name")
        XCTAssertEqual(GenAIAttributes.requestModel, "gen_ai.request.model")
        XCTAssertEqual(GenAIAttributes.responseModel, "gen_ai.response.model")
        XCTAssertEqual(GenAIAttributes.responseId, "gen_ai.response.id")
        XCTAssertEqual(GenAIAttributes.responseFinishReasons, "gen_ai.response.finish_reasons")
        XCTAssertEqual(GenAIAttributes.usageInputTokens, "gen_ai.usage.input_tokens")
        XCTAssertEqual(GenAIAttributes.usageOutputTokens, "gen_ai.usage.output_tokens")
        XCTAssertEqual(GenAIAttributes.usageCacheReadInputTokens, "gen_ai.usage.cache_read.input_tokens")
        XCTAssertEqual(GenAIAttributes.usageCacheCreationInputTokens, "gen_ai.usage.cache_creation.input_tokens")
        XCTAssertEqual(GenAIAttributes.usageReasoningTokens, "gen_ai.usage.reasoning.output_tokens")
        XCTAssertEqual(GenAIAttributes.costUsd, "gen_ai.cost.usd")
        XCTAssertEqual(GenAIAttributes.inputMessages, "gen_ai.input.messages")
        XCTAssertEqual(GenAIAttributes.outputMessages, "gen_ai.output.messages")
        XCTAssertEqual(GenAIAttributes.systemInstructions, "gen_ai.system_instructions")
        XCTAssertEqual(GenAIAttributes.toolDefinitions, "gen_ai.tool.definitions")
        XCTAssertEqual(GenAIAttributes.toolName, "gen_ai.tool.name")
        XCTAssertEqual(GenAIAttributes.toolType, "gen_ai.tool.type")
        XCTAssertEqual(GenAIAttributes.toolDescription, "gen_ai.tool.description")
        XCTAssertEqual(GenAIAttributes.toolCallId, "gen_ai.tool.call.id")
        XCTAssertEqual(GenAIAttributes.toolCallArguments, "gen_ai.tool.call.arguments")
        XCTAssertEqual(GenAIAttributes.toolCallResult, "gen_ai.tool.call.result")
    }

    func testGenAIOperationNames() {
        XCTAssertEqual(GenAIOperationNames.chat, "chat")
        XCTAssertEqual(GenAIOperationNames.executeTool, "execute_tool")
        XCTAssertEqual(GenAIOperationNames.invokeAgent, "invoke_agent")
        XCTAssertEqual(GenAIOperationNames.createAgent, "create_agent")
    }

    func testIntrospectionAttributes() {
        XCTAssertEqual(IntrospectionAttributes.agentInvocationId, "introspection.agent.invocation_id")
        XCTAssertEqual(IntrospectionAttributes.conversationClientMessageId, "introspection.conversation.client_message_id")
        XCTAssertEqual(IntrospectionAttributes.terminationReason, "introspection.termination_reason")
        XCTAssertEqual(IntrospectionAttributes.llmCostUsd, "introspection.llm.cost_usd")
        XCTAssertEqual(IntrospectionAttributes.llmUpstreamCostUsd, "introspection.llm.upstream_cost_usd")
    }

    func testCustomEventNames() {
        XCTAssertEqual(CustomEventNames.reconnect, "introspection.reconnect")
        XCTAssertEqual(CustomEventNames.messageIdentity, "introspection.message_identity")
        XCTAssertEqual(CustomEventNames.resumeGap, "resume_gap")
        XCTAssertEqual(AGUIEvent.reconnectEventName, CustomEventNames.reconnect)
        XCTAssertEqual(AGUIEvent.resumeGapEventName, CustomEventNames.resumeGap)
    }

    func testIncludesReuseTheAttributeNames() {
        XCTAssertEqual(ConversationItemInclude.systemInstructions.rawValue, GenAIAttributes.systemInstructions)
        XCTAssertEqual(ConversationItemInclude.toolDefinitions.rawValue, GenAIAttributes.toolDefinitions)
    }

    func testSpanAccessorsReadTheConventions() throws {
        let span = GenAISpan(
            traceId: "tr",
            attributes: [
                "gen_ai": [
                    "operation": ["name": "chat"], "usage": ["input_tokens": 3], "cost": ["usd": 0.5],
                ],
                "introspection": ["agent": ["invocation_id": "inv-1"], "conversation": ["client_message_id": "m-1"]],
            ])
        XCTAssertEqual(span.operationName, GenAIOperationNames.chat)
        XCTAssertEqual(span.inputTokens, 3)
        XCTAssertEqual(span.costUsd, 0.5)
        XCTAssertEqual(span.invocationId, "inv-1")
        XCTAssertEqual(span.clientMessageId, "m-1")
    }
}
