import Foundation
import Testing

@testable import IntrospectionSDK

@Suite struct AGUIEventTests {
    private func decode(_ json: String) throws -> AGUIEvent {
        try JSONCoding.decoder.decode(AGUIEvent.self, from: Data(json.utf8))
    }

    @Test(arguments: [
        (#"{"type":"RUN_FINISHED","threadId":"t","runId":"r"}"#, AGUIRunOutcomeType.success),
        (#"{"type":"RUN_FINISHED","threadId":"t","runId":"r","outcome":{"type":"success","pendingToolCallIds":["c1"]}}"#, .success),
        (#"{"type":"RUN_FINISHED","threadId":"t","runId":"r","outcome":{"type":"cancelled"}}"#, .cancelled),
        (#"{"type":"RUN_FINISHED","threadId":"t","runId":"r","outcome":{"type":"suspended"}}"#, "suspended"),
    ])
    func runFinishedOutcomeType(json: String, expected: AGUIRunOutcomeType) throws {
        #expect(try decode(json).outcomeType == expected)
    }

    @Test func interruptOutcomeCarriesItsInterrupts() throws {
        let event = try decode(
            #"{"type":"RUN_FINISHED","threadId":"t","runId":"r","outcome":{"type":"interrupt","interrupts":[{"id":"i1","reason":"input_required"}]}}"#
        )
        #expect(event.outcomeType == .interrupt)
        #expect(event.interrupts?.first?["id"] == "i1")
    }

    @Test func outcomeTypeIsOnlyForRunFinished() throws {
        #expect(try decode(#"{"type":"RUN_ERROR","message":"x","outcome":{"type":"cancelled"}}"#).outcomeType == nil)
    }

    @Test func subagentRunIdAndMetadata() throws {
        let event = try decode(
            #"{"type":"REASONING_MESSAGE_CONTENT","messageId":"m","delta":"d","subagentRunId":"sr1","metadata":{"k":null}}"#
        )
        #expect(event.eventType == .reasoningMessageContent)
        #expect(event.subagentRunId == "sr1")
        #expect(event.metadata == ["k": .null])
        #expect(try decode(#"{"type":"TEXT_MESSAGE_END","messageId":"m"}"#).subagentRunId == nil)
    }

    @Test(arguments: [
        (AGUIEventType.activitySnapshot, "ACTIVITY_SNAPSHOT"),
        (.activityDelta, "ACTIVITY_DELTA"),
        (.reasoningStart, "REASONING_START"),
        (.reasoningMessageStart, "REASONING_MESSAGE_START"),
        (.reasoningMessageContent, "REASONING_MESSAGE_CONTENT"),
        (.reasoningMessageEnd, "REASONING_MESSAGE_END"),
        (.reasoningMessageChunk, "REASONING_MESSAGE_CHUNK"),
        (.reasoningEnd, "REASONING_END"),
        (.reasoningEncryptedValue, "REASONING_ENCRYPTED_VALUE"),
        (.subagentStarted, "SUBAGENT_STARTED"),
        (.subagentFinished, "SUBAGENT_FINISHED"),
        (.subagentError, "SUBAGENT_ERROR"),
    ])
    func agui1EventTypes(type: AGUIEventType, wire: String) {
        #expect(type.rawValue == wire)
    }

    @Test func removedThinkingTypesDecodeAsUnknown() throws {
        let event = try decode(#"{"type":"THINKING_TEXT_MESSAGE_CONTENT","delta":"d"}"#)
        #expect(event.eventType.rawValue == "THINKING_TEXT_MESSAGE_CONTENT")
        let transcript = TranscriptAccumulator()
        transcript.push(event)
        #expect(transcript.entries.isEmpty)
    }
}
