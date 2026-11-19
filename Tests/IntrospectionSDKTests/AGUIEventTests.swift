import Foundation
import Testing

@testable import IntrospectionSDK

@Suite struct AGUIEventTests {
    private func decode(_ json: String) throws -> AGUIEvent {
        try JSONCoding.decoder.decode(AGUIEvent.self, from: Data(json.utf8))
    }

    @Test func interruptOutcomeCarriesTypedInterrupts() throws {
        let event = try decode(
            #"{"type":"RUN_FINISHED","threadId":"t","runId":"r","outcome":{"type":"interrupt","interrupts":[{"id":"i1","reason":"input_required"}]}}"#
        )
        guard case let .runFinished(finished) = event.payload, case let .interrupt(outcome) = finished.outcome else {
            Issue.record("expected an interrupt outcome, got \(event.payload)")
            return
        }
        #expect(outcome.interrupts == [AGUI.Interrupt(id: "i1", reason: "input_required")])
    }

    @Test func absentOutcomeStaysAbsent() throws {
        let event = try decode(#"{"type":"RUN_FINISHED","threadId":"t","runId":"r","timestamp":1700000000000}"#)
        guard case let .runFinished(finished) = event.payload else {
            Issue.record("expected RUN_FINISHED, got \(event.payload)")
            return
        }
        #expect(finished.outcome == nil)
        #expect(finished.timestamp == 1_700_000_000_000)
    }

    @Test func frameOutsideItsSchemaIsUnknownAndKeptRaw() throws {
        let json = #"{"type":"RUN_FINISHED","threadId":"t","runId":"r","outcome":{"type":"suspended"}}"#
        let event = try decode(json)
        #expect(event.payload == .unknown)
        #expect(event.eventType == .runFinished)
        #expect(event.raw["outcome"]?["type"] == "suspended")
        #expect(try JSONCoding.encoder.encode(event) == JSONCoding.encoder.encode(JSONValue(raw: json)))
    }

    @Test func keysAGUIDoesNotDefineStayInRaw() throws {
        let event = try decode(#"{"type":"TOOL_CALL_RESULT","messageId":"m","toolCallId":"c","content":"x","isError":true}"#)
        guard case let .toolCallResult(result) = event.payload else {
            Issue.record("expected TOOL_CALL_RESULT, got \(event.payload)")
            return
        }
        #expect(result.content == .text("x"))
        #expect(event.raw["isError"] == true)
    }

    @Test func subagentRunIdAndMetadata() throws {
        let event = try decode(
            #"{"type":"REASONING_MESSAGE_CONTENT","messageId":"m","delta":"d","subagentRunId":"sr1","metadata":{"k":null}}"#
        )
        guard case let .reasoningMessageContent(content) = event.payload else {
            Issue.record("expected REASONING_MESSAGE_CONTENT, got \(event.payload)")
            return
        }
        #expect(content.subagentRunId == "sr1")
        #expect(event.payload.body?.metadata == ["k": .null])
    }

    @Test func customHelperBuildsATypedEvent() {
        let event = AGUIEvent.custom("name", value: ["k": 1])
        #expect(event.payload == .custom(AGUI.CustomEvent(name: "name", value: ["k": 1])))
    }

    @Test func modelsEncodeTheirConstants() throws {
        let message = AGUI.Message.assistant(
            AGUI.AssistantMessage(
                id: "a", content: "hi", toolCalls: [AGUI.ToolCall(id: "c", function: AGUI.FunctionCall(name: "ls", arguments: "{}"))]))
        #expect(
            try JSONValue.from(message) == [
                "id": "a", "role": "assistant", "content": "hi",
                "toolCalls": [["id": "c", "type": "function", "function": ["name": "ls", "arguments": "{}"]]],
            ])
    }

    @Test func removedThinkingTypesDecodeAsUnknown() throws {
        let event = try decode(#"{"type":"THINKING_TEXT_MESSAGE_CONTENT","delta":"d"}"#)
        #expect(event.eventType.rawValue == "THINKING_TEXT_MESSAGE_CONTENT")
        #expect(event.payload == .unknown)
        let transcript = TranscriptAccumulator()
        transcript.push(event)
        #expect(transcript.entries.isEmpty)
    }
}

extension JSONValue {
    fileprivate init(raw json: String) throws {
        self = try JSONCoding.decoder.decode(JSONValue.self, from: Data(json.utf8))
    }
}
