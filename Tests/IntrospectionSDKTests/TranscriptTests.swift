import Foundation
import Testing

@testable import IntrospectionSDK

private func span(_ json: String) throws -> GenAISpan {
    try JSONCoding.decoder.decode(GenAISpan.self, from: Data(json.utf8))
}

private func event(_ value: JSONValue) -> AGUIEvent { AGUIEvent(raw: value) }

@Suite struct TranscriptTests {
    @Test func foldSpansOrdersDedupesAndJoinsResults() throws {
        // Given out of order: the tool span (s3), the follow-up chat (s4), the first chat (s2), and a delegation.
        let toolSpan = try span(
            #"""
            {"trace_id":"t","span_id":"s3","start_time":"2026-10-01T12:00:03Z","end_time":"2026-10-01T12:00:04Z",
             "attributes":{"gen_ai":{"operation":{"name":"execute_tool"},"tool":{"name":"search","call":{"id":"call-1","arguments":"{\"q\":\"x\"}"}}}}}
            """#)
        let followUp = try span(
            #"""
            {"trace_id":"t","span_id":"s4","start_time":"2026-10-01T12:00:05Z",
             "attributes":{"gen_ai":{"operation":{"name":"chat"},
              "input":{"messages":[{"role":"tool","parts":[{"type":"tool_call_response","id":"call-1","result":{"hits":2}}]}]},
              "output":{"messages":[{"role":"assistant","parts":[{"type":"text","content":"Found 2"}]}]}}}}
            """#)
        let firstChat = try span(
            #"""
            {"trace_id":"t","span_id":"s2","start_time":"2026-10-01T12:00:01Z","end_time":"2026-10-01T12:00:02Z",
             "attributes":{"gen_ai":{"operation":{"name":"chat"},"response":{"id":"resp-1"},
              "input":{"messages":[{"role":"system","parts":[{"type":"text","content":"sys"}]},{"role":"user","parts":[{"type":"text","content":"find x"}]}]},
              "output":{"messages":[{"role":"assistant","parts":[{"type":"thinking","content":"hmm"},{"type":"text","content":"Searching"},
               {"type":"tool_call","id":"call-1","name":"search","arguments":{"q":"x"}}]}]}},
              "introspection":{"conversation":{"client_message_id":"cm-1"}}}}
            """#)
        let delegation = try span(
            #"""
            {"trace_id":"t","span_id":"s5","start_time":"2026-10-01T12:00:06Z","duration_ns":5,"status":{"code":"Error"},
             "attributes":{"gen_ai":{"operation":{"name":"invoke_agent"},"agent":{"id":"a1","name":"researcher"}},
              "introspection":{"agent":{"invocation_id":"run-9"}}}}
            """#)

        let entries = foldSpans([toolSpan, followUp, delegation, firstChat])
        #expect(entries.map(\.id) == ["cm-1", "resp-1", "tool:call-1", "span:s4:assistant:0", "span:s5:delegation"])

        let user = try #require(entries[0].message)
        #expect(user.role == .user)
        #expect(user.text == "find x")
        #expect(user.clientMessageId == "cm-1")

        let assistant = try #require(entries[1].message)
        #expect(assistant.text == "Searching")
        #expect(assistant.thinking == "hmm")
        #expect(assistant.responseId == "resp-1")

        let tool = try #require(entries[2].tool)
        #expect(tool.name == "search")
        #expect(tool.status == .complete)
        #expect(tool.result == ["hits": 2])
        #expect(tool.arguments == #"{"q":"x"}"#)
        #expect(tool.spanId == "s4")

        let delegationEntry = try #require(entries[4].delegation)
        #expect(delegationEntry.status == .error)
        #expect(delegationEntry.invocationId == "run-9")
        #expect(delegationEntry.agentName == "researcher")
        #expect(delegationEntry.durationNs == 5)

        // Re-folding never duplicates.
        #expect(foldSpans([firstChat, toolSpan, followUp, delegation]) == entries)
    }

    @Test func requestedToolCallStaysRunningAndErrorResults() throws {
        let chat = try span(
            #"""
            {"trace_id":"t","span_id":"s1","start_time":"2026-10-01T12:00:01Z","end_time":"2026-10-01T12:00:02Z",
             "attributes":{"gen_ai":{"output":{"messages":[{"role":"assistant","parts":[{"type":"tool_call","id":"c1","name":"ls"}]}]}}}}
            """#)
        #expect(foldSpans([chat]).first?.tool?.status == .running)

        let failed = try span(
            #"""
            {"trace_id":"t","span_id":"s2","start_time":"2026-10-01T12:00:03Z",
             "attributes":{"gen_ai":{"input":{"messages":[{"role":"tool","parts":[{"type":"tool_call_response","id":"c1","response":{"error":"boom"}}]}]}}}}
            """#)
        #expect(foldSpans([chat, failed]).first?.tool?.status == .error)
    }

    @Test func accumulatorFoldsLiveStream() {
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
            event([
                "type": "TOOL_CALL_RESULT", "toolCallId": "c2",
                "content": #"{"details":{"agent":{"agent_run_id":"run-9","status":"running"}}}"#,
            ]),
            event(["type": "TOOL_CALL_START", "toolCallId": "c3", "toolCallName": "slow"]),
            event(["type": "ACTIVITY_SNAPSHOT", "messageId": "x"]),
            event(["type": "SOMETHING_NEW"]),
            event(["type": "RUN_FINISHED", "runId": "r1"]),
        ])

        let entries = accumulator.entries
        #expect(entries.map(\.id) == ["u1", "a1", "tool:c1", "delegation-tool:c2", "tool:c3"])
        #expect(entries[0].message?.text == "hi")
        #expect(entries[1].message?.text == "Hello")
        #expect(entries[1].message?.thinking == "plan more")
        #expect(entries[1].message?.responseId == "resp-1")
        #expect(entries[2].tool?.arguments == #"{"q":"x"}"#)
        #expect(entries[2].tool?.result == "2 hits")
        #expect(entries[2].tool?.status == .complete)
        let delegation = entries[3].delegation
        #expect(delegation?.invocationId == "run-9")
        #expect(delegation?.agentName == "researcher")
        #expect(delegation?.label == "Dig")
        #expect(delegation?.status == .running)
        #expect(entries[4].tool?.status == .error)
        #expect(activity == 1)
        #expect(control == ["introspection.message_identity"])
    }

    @Test func reasoningWithoutMessageIsKeptAtRunEnd() {
        let entries = foldAgui([
            event(["type": "REASONING_MESSAGE_CONTENT", "delta": "thinking only"]),
            event(["type": "RUN_ERROR", "runId": "r7", "message": "boom"]),
        ])
        #expect(entries.count == 1)
        #expect(entries[0].id == "r7:reasoning")
        #expect(entries[0].message?.thinking == "thinking only")
        #expect(entries[0].message?.text == "")
    }

    @Test func messagesSnapshotUpserts() {
        let entries = foldAgui([
            event(["type": "TEXT_MESSAGE_START", "messageId": "a1"]),
            event(["type": "TEXT_MESSAGE_CONTENT", "messageId": "a1", "delta": "partial"]),
            event([
                "type": "MESSAGES_SNAPSHOT",
                "messages": [
                    ["id": "u0", "role": "user", "content": "earlier"],
                    [
                        "id": "a1", "role": "assistant", "content": "complete",
                        "toolCalls": [["id": "c9", "function": ["name": "ls", "arguments": "{}"]]],
                    ],
                ],
            ]),
        ])
        #expect(entries.map(\.id) == ["a1", "u0", "tool:c9"])
        #expect(entries[0].message?.text == "complete")
        #expect(entries[2].tool?.arguments == "{}")
    }

    @Test func mergesStoredAndLiveTranscripts() {
        let stored: [TranscriptEntry] = [
            .message(TranscriptMessageEntry(id: "cm-1", role: .user, text: "hi", clientMessageId: "cm-1")),
            .message(TranscriptMessageEntry(id: "resp-1", role: .assistant, text: "hello", responseId: "resp-1")),
            .tool(TranscriptToolEntry(callId: "c1", name: "search", status: .complete)),
            .delegation(
                TranscriptDelegationEntry(id: "span:s5:delegation", status: .complete, invocationId: "run-9", agentId: "researcher")),
            .delegation(TranscriptDelegationEntry(id: "span:s6:delegation", status: .complete, agentId: "legacy")),
        ]
        let live: [TranscriptEntry] = [
            .message(TranscriptMessageEntry(id: "cm-1", role: .user, text: "hi")),
            .message(TranscriptMessageEntry(id: "a1", role: .assistant, text: "hello", responseId: "resp-1")),
            .tool(TranscriptToolEntry(callId: "c1", name: "search")),
            .delegation(
                TranscriptDelegationEntry(id: "delegation-tool:c2", status: .running, invocationId: "run-9", sourceToolCallId: "c2")),
            .delegation(
                TranscriptDelegationEntry(id: "delegation-tool:c3", status: .running, invocationId: "run-10", agentId: "researcher")),
            .delegation(TranscriptDelegationEntry(id: "delegation-tool:c4", status: .running, agentId: "legacy")),
            .message(TranscriptMessageEntry(id: "a2", role: .assistant, text: "still streaming")),
            .tool(TranscriptToolEntry(callId: "c5", name: "new")),
        ]
        let merged = mergeTranscripts(stored: stored, live: live)
        #expect(merged.map(\.id) == stored.map(\.id) + ["delegation-tool:c3", "a2", "tool:c5"])
    }
}
