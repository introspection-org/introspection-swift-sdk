import Foundation
import XCTest
@testable import IntrospectionSDK

private func span(_ json: String) throws -> GenAISpan {
    try JSONCoding.decoder.decode(GenAISpan.self, from: Data(json.utf8))
}

private func event(_ value: JSONValue) -> AGUIEvent { AGUIEvent(raw: value) }

final class TranscriptTests: XCTestCase {
    func testFoldSpansOrdersDedupesAndJoinsResults() throws {
        // Given out of order: the tool span (s3), the follow-up chat (s4), the first chat (s2), and a delegation.
        let toolSpan = try span(#"""
        {"trace_id":"t","span_id":"s3","start_time":"2026-10-01T12:00:03Z","end_time":"2026-10-01T12:00:04Z",
         "attributes":{"gen_ai":{"operation":{"name":"execute_tool"},"tool":{"name":"search","call":{"id":"call-1","arguments":"{\"q\":\"x\"}"}}}}}
        """#)
        let followUp = try span(#"""
        {"trace_id":"t","span_id":"s4","start_time":"2026-10-01T12:00:05Z",
         "attributes":{"gen_ai":{"operation":{"name":"chat"},
          "input":{"messages":[{"role":"tool","parts":[{"type":"tool_call_response","id":"call-1","result":{"hits":2}}]}]},
          "output":{"messages":[{"role":"assistant","parts":[{"type":"text","content":"Found 2"}]}]}}}}
        """#)
        let firstChat = try span(#"""
        {"trace_id":"t","span_id":"s2","start_time":"2026-10-01T12:00:01Z","end_time":"2026-10-01T12:00:02Z",
         "attributes":{"gen_ai":{"operation":{"name":"chat"},"response":{"id":"resp-1"},
          "input":{"messages":[{"role":"system","parts":[{"type":"text","content":"sys"}]},{"role":"user","parts":[{"type":"text","content":"find x"}]}]},
          "output":{"messages":[{"role":"assistant","parts":[{"type":"thinking","content":"hmm"},{"type":"text","content":"Searching"},
           {"type":"tool_call","id":"call-1","name":"search","arguments":{"q":"x"}}]}]}},
          "introspection":{"conversation":{"client_message_id":"cm-1"}}}}
        """#)
        let delegation = try span(#"""
        {"trace_id":"t","span_id":"s5","start_time":"2026-10-01T12:00:06Z","duration_ns":5,"status":{"code":"Error"},
         "attributes":{"gen_ai":{"operation":{"name":"invoke_agent"},"agent":{"id":"a1","name":"researcher"}},
          "introspection":{"agent":{"invocation_id":"run-9"}}}}
        """#)

        let entries = foldSpans([toolSpan, followUp, delegation, firstChat])
        XCTAssertEqual(entries.map(\.id), ["cm-1", "resp-1", "tool:call-1", "span:s4:assistant:0", "span:s5:delegation"])

        let user = try XCTUnwrap(entries[0].message)
        XCTAssertEqual(user.role, .user)
        XCTAssertEqual(user.text, "find x")
        XCTAssertEqual(user.clientMessageId, "cm-1")

        let assistant = try XCTUnwrap(entries[1].message)
        XCTAssertEqual(assistant.text, "Searching")
        XCTAssertEqual(assistant.thinking, "hmm")
        XCTAssertEqual(assistant.responseId, "resp-1")

        let tool = try XCTUnwrap(entries[2].tool)
        XCTAssertEqual(tool.name, "search")
        XCTAssertEqual(tool.status, .complete)
        XCTAssertEqual(tool.result, ["hits": 2])
        XCTAssertEqual(tool.arguments, #"{"q":"x"}"#)
        XCTAssertEqual(tool.spanId, "s4")

        let delegationEntry = try XCTUnwrap(entries[4].delegation)
        XCTAssertEqual(delegationEntry.status, .error)
        XCTAssertEqual(delegationEntry.invocationId, "run-9")
        XCTAssertEqual(delegationEntry.agentName, "researcher")
        XCTAssertEqual(delegationEntry.durationNs, 5)

        // Re-folding never duplicates.
        XCTAssertEqual(foldSpans([firstChat, toolSpan, followUp, delegation]), entries)
    }

    func testRequestedToolCallStaysRunningAndErrorResults() throws {
        let chat = try span(#"""
        {"trace_id":"t","span_id":"s1","start_time":"2026-10-01T12:00:01Z","end_time":"2026-10-01T12:00:02Z",
         "attributes":{"gen_ai":{"output":{"messages":[{"role":"assistant","parts":[{"type":"tool_call","id":"c1","name":"ls"}]}]}}}}
        """#)
        XCTAssertEqual(foldSpans([chat]).first?.tool?.status, .running)

        let failed = try span(#"""
        {"trace_id":"t","span_id":"s2","start_time":"2026-10-01T12:00:03Z",
         "attributes":{"gen_ai":{"input":{"messages":[{"role":"tool","parts":[{"type":"tool_call_response","id":"c1","response":{"error":"boom"}}]}]}}}}
        """#)
        XCTAssertEqual(foldSpans([chat, failed]).first?.tool?.status, .error)
    }

    func testAccumulatorFoldsLiveStream() {
        var activity = 0
        var control: [String] = []
        let accumulator = TranscriptAccumulator(onActivity: { _ in activity += 1 }, onControl: { control.append($0.name ?? "") })
        accumulator.push(contentsOf: [
            event(["type": "RUN_STARTED", "runId": "r1"]),
            event(["type": "TEXT_MESSAGE_START", "messageId": "u1", "role": "user"]),
            event(["type": "TEXT_MESSAGE_CONTENT", "messageId": "u1", "delta": "hi"]),
            event(["type": "REASONING_MESSAGE_CONTENT", "delta": "plan "]),
            event(["type": "REASONING_MESSAGE_CHUNK", "delta": "more"]),
            event(["type": "TEXT_MESSAGE_START", "messageId": "a1", "role": "assistant"]),
            event(["type": "TEXT_MESSAGE_CONTENT", "messageId": "a1", "delta": "Hel"]),
            event(["type": "TEXT_MESSAGE_CHUNK", "messageId": "a1", "delta": "lo"]),
            event(["type": "CUSTOM", "name": "introspection.message_identity", "value": ["messageId": "a1", "responseId": "resp-1"]]),
            event(["type": "TOOL_CALL_START", "toolCallId": "c1", "toolCallName": "search"]),
            event(["type": "TOOL_CALL_ARGS", "toolCallId": "c1", "delta": "{\"q\":"]),
            event(["type": "TOOL_CALL_ARGS", "toolCallId": "c1", "delta": "\"x\"}"]),
            event(["type": "TOOL_CALL_END", "toolCallId": "c1"]),
            event(["type": "TOOL_CALL_RESULT", "toolCallId": "c1", "content": "2 hits", "isError": false]),
            event(["type": "TOOL_CALL_START", "toolCallId": "c2", "toolCallName": "agent"]),
            event(["type": "TOOL_CALL_ARGS", "toolCallId": "c2", "delta": #"{"action":"start","name":"researcher","label":"Dig"}"#]),
            event(["type": "TOOL_CALL_END", "toolCallId": "c2"]),
            event(["type": "TOOL_CALL_RESULT", "toolCallId": "c2", "content": #"{"details":{"agent":{"agent_run_id":"run-9","status":"running"}}}"#]),
            event(["type": "TOOL_CALL_START", "toolCallId": "c3", "toolCallName": "slow"]),
            event(["type": "ACTIVITY_SNAPSHOT", "messageId": "x"]),
            event(["type": "SOMETHING_NEW"]),
            event(["type": "RUN_FINISHED", "runId": "r1"]),
        ])

        let entries = accumulator.entries
        XCTAssertEqual(entries.map(\.id), ["u1", "a1", "tool:c1", "delegation-tool:c2", "tool:c3"])
        XCTAssertEqual(entries[0].message?.text, "hi")
        XCTAssertEqual(entries[1].message?.text, "Hello")
        XCTAssertEqual(entries[1].message?.thinking, "plan more")
        XCTAssertEqual(entries[1].message?.responseId, "resp-1")
        XCTAssertEqual(entries[2].tool?.arguments, #"{"q":"x"}"#)
        XCTAssertEqual(entries[2].tool?.result, "2 hits")
        XCTAssertEqual(entries[2].tool?.status, .complete)
        let delegation = entries[3].delegation
        XCTAssertEqual(delegation?.invocationId, "run-9")
        XCTAssertEqual(delegation?.agentName, "researcher")
        XCTAssertEqual(delegation?.label, "Dig")
        XCTAssertEqual(delegation?.status, .running)
        XCTAssertEqual(entries[4].tool?.status, .error)
        XCTAssertEqual(activity, 1)
        XCTAssertEqual(control, ["introspection.message_identity"])
    }

    func testReasoningWithoutMessageIsKeptAtRunEnd() {
        let entries = foldAgui([
            event(["type": "REASONING_MESSAGE_CONTENT", "delta": "thinking only"]),
            event(["type": "RUN_ERROR", "runId": "r7", "message": "boom"]),
        ])
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].id, "r7:reasoning")
        XCTAssertEqual(entries[0].message?.thinking, "thinking only")
        XCTAssertEqual(entries[0].message?.text, "")
    }

    func testMessagesSnapshotUpserts() {
        let entries = foldAgui([
            event(["type": "TEXT_MESSAGE_START", "messageId": "a1"]),
            event(["type": "TEXT_MESSAGE_CONTENT", "messageId": "a1", "delta": "partial"]),
            event(["type": "MESSAGES_SNAPSHOT", "messages": [
                ["id": "u0", "role": "user", "content": "earlier"],
                ["id": "a1", "role": "assistant", "content": "complete", "toolCalls": [["id": "c9", "function": ["name": "ls", "arguments": "{}"]]]],
            ]]),
        ])
        XCTAssertEqual(entries.map(\.id), ["a1", "u0", "tool:c9"])
        XCTAssertEqual(entries[0].message?.text, "complete")
        XCTAssertEqual(entries[2].tool?.arguments, "{}")
    }

    func testMergeTranscripts() {
        let stored: [TranscriptEntry] = [
            .message(TranscriptMessageEntry(id: "cm-1", role: .user, text: "hi", clientMessageId: "cm-1")),
            .message(TranscriptMessageEntry(id: "resp-1", role: .assistant, text: "hello", responseId: "resp-1")),
            .tool(TranscriptToolEntry(callId: "c1", name: "search", status: .complete)),
            .delegation(TranscriptDelegationEntry(id: "span:s5:delegation", status: .complete, invocationId: "run-9", agentId: "researcher")),
            .delegation(TranscriptDelegationEntry(id: "span:s6:delegation", status: .complete, agentId: "legacy")),
        ]
        let live: [TranscriptEntry] = [
            .message(TranscriptMessageEntry(id: "cm-1", role: .user, text: "hi")),
            .message(TranscriptMessageEntry(id: "a1", role: .assistant, text: "hello", responseId: "resp-1")),
            .tool(TranscriptToolEntry(callId: "c1", name: "search")),
            .delegation(TranscriptDelegationEntry(id: "delegation-tool:c2", status: .running, invocationId: "run-9", sourceToolCallId: "c2")),
            .delegation(TranscriptDelegationEntry(id: "delegation-tool:c3", status: .running, invocationId: "run-10", agentId: "researcher")),
            .delegation(TranscriptDelegationEntry(id: "delegation-tool:c4", status: .running, agentId: "legacy")),
            .message(TranscriptMessageEntry(id: "a2", role: .assistant, text: "still streaming")),
            .tool(TranscriptToolEntry(callId: "c5", name: "new")),
        ]
        let merged = mergeTranscripts(stored: stored, live: live)
        XCTAssertEqual(merged.map(\.id), stored.map(\.id) + ["delegation-tool:c3", "a2", "tool:c5"])
    }
}
