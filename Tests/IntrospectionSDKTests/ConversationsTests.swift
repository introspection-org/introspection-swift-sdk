import Foundation
import Testing

@testable import IntrospectionSDK

private let conversationJSON = #"""
    {"object":"conversation","id":"conv-1","created_at":"2026-10-01T12:00:00Z","updated_at":"2026-10-01T12:05:00Z",
     "agents":[{"id":"root"},{"id":"a1","name":"researcher","parent_id":"root","invocation_id":"run-9","depth":1}],
     "usage":{"input_tokens":10,"output_tokens":20,"total_tokens":30},"cost":{"usd":0.01},
     "metrics":{"duration_ms":1200.5,"trace_count":2,"span_count":9,"tool_use_count":3,"failed_tool_use_count":1,
     "llm_call_count":4,"failed_llm_call_count":0,"has_errors":true},
     "environment":"production","service_name":"svc","metadata":{"flow":"company"},"task_title":"Hello"}
    """#

private let chatSpanJSON = #"""
    {"trace_id":"t1","span_id":"s2","name":"chat anthropic","kind":"CLIENT","start_time":"2026-10-01T12:00:02Z",
     "end_time":"2026-10-01T12:00:03Z","duration_ns":1000000000,"status":{"code":"Ok"},
     "resource":{"service":{"name":"svc"}},
     "attributes":{"gen_ai":{"operation":{"name":"chat"},"response":{"id":"resp-1"},"usage":{"input_tokens":5},
      "input":{"messages":[{"role":"user","parts":[{"type":"text","content":"hi"}]},
       {"role":"tool","parts":[{"type":"tool_call_response","id":"call-0","result":{"ok":true}}]}]},
      "output":{"messages":[{"role":"assistant","finish_reason":"stop","parts":[
       {"type":"reasoning","content":"think"},{"type":"text","content":"hello"},
       {"type":"tool_call","id":"call-1","name":"search","arguments":{"q":"x"}},
       {"type":"image-url","url":"https://x/y.png"},{"type":"hologram","depth":3}]}]}},
      "introspection":{"conversation":{"client_message_id":"cm-1"}},"custom.attr":"kept"}}
    """#

private let toolSpanJSON = #"""
    {"trace_id":"t1","span_id":"s1","start_time":"2026-10-01T12:00:01Z",
     "attributes":{"gen_ai":{"operation":{"name":"execute_tool"},"tool":{"name":"search","call":{"id":"call-1"}}}}}
    """#

@Suite struct ConversationsTests {
    @Test func listSerializesReadWindowAndMetadata() async throws {
        let transport = MockTransport(json: #"{"records":[\#(conversationJSON)],"count":1,"total_count":null,"next":null}"#)
        let client = makeClient(transport)
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let paginator = try client.conversations.list(
            ConversationListParams(
                limit: 10, order: .asc, lookback: "24h", sort: .cost, shareIds: ["sh1"], conversationIds: ["a", "b"],
                status: .error, serviceNames: ["x", "y"], resolution: "resolved",
                metadata: ["tenant": "acme", "flow": "company:x"]
            ), now: now)
        let page = try await paginator.firstPage()
        let conversation = try #require(page.records.first)
        #expect(conversation.metrics?.llmCallCount == 4)
        #expect(conversation.agents?.last?.invocationId == "run-9")
        #expect(conversation.metadata == ["flow": "company"])
        #expect(conversation.cost?.usd == 0.01)

        let q = try #require(transport.last).query
        #expect(transport.last?.path == "/v1/conversations")
        #expect(q["direction"] == ["asc"])
        #expect(q["start_date"] == [ISO8601.format(now.addingTimeInterval(-86_400))])
        #expect(q["end_date"] == nil)
        #expect(q["lookback"] == nil)
        #expect(q["order"] == nil)
        #expect(q["sort"] == ["cost"])
        #expect(q["status"] == ["Error"])
        #expect(q["conversation_ids"] == ["a", "b"])
        #expect(q["service_names"] == ["x", "y"])
        #expect(q["metadata"] == ["flow:company:x", "tenant:acme"])
    }

    @Test func readWindowValidationThrowsBeforeSending() throws {
        let transport = MockTransport(json: "{}")
        let client = makeClient(transport)
        let error = try #require(throws: IntrospectionError.self) {
            try client.conversations.list(ConversationListParams(start: Date(), lookback: "1h"))
        }
        #expect(error.kind == .validation)
        #expect(throws: (any Error).self) { try client.conversations.list(ConversationListParams(lookback: "3 days")) }
        #expect(throws: (any Error).self) { try client.conversations.list(ConversationListParams(lookback: "5m5")) }
        #expect(transport.requests.count == 0)

        #expect(ReadLookback("500ms").seconds == 0.5)
        #expect(ReadLookback("2w").seconds == 1_209_600)
        #expect(ReadLookback.minutes(5).seconds == 300)
        #expect(ReadLookback("h").seconds == nil)
    }

    @Test func explicitWindow() async throws {
        let transport = MockTransport(json: #"{"records":[],"count":0,"next":null}"#)
        let client = makeClient(transport)
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 2_000)
        _ = try await client.conversations.list(ConversationListParams(start: start, end: end)).firstPage()
        #expect(transport.last?.query["start_date"] == [ISO8601.format(start)])
        #expect(transport.last?.query["end_date"] == [ISO8601.format(end)])
    }

    @Test func genAISpanDecodingAndAccessors() throws {
        let span = try JSONCoding.decoder.decode(GenAISpan.self, from: Data(chatSpanJSON.utf8))
        #expect(span.operationName == "chat")
        #expect(span.responseId == "resp-1")
        #expect(span.clientMessageId == "cm-1")
        #expect(span.inputTokens == 5)
        #expect(span.kind == .client)
        #expect(span.status?.code == .ok)
        #expect(span.attribute("custom.attr") == "kept")
        #expect(span.inputMessages.count == 2)

        guard case let .toolCallResponse(response) = span.inputMessages[1].parts[0] else {
            Issue.record("expected tool_call_response")
            return
        }
        #expect(response.response == ["ok": true])

        let parts = try #require(span.outputMessages.first).parts
        #expect(parts.map(\.type) == ["reasoning", "text", "tool_call", "image-url", "hologram"])
        guard case let .thinking(thinking) = parts[0], case let .toolCall(call) = parts[2],
            case let .media(media) = parts[3], case let .unknown(raw) = parts[4]
        else {
            Issue.record("unexpected part shapes")
            return
        }
        #expect(thinking.content == "think")
        #expect(call.arguments == ["q": "x"])
        #expect(media.url == "https://x/y.png")
        #expect(raw["depth"] == 3)
        #expect(span.outputMessages.first?.finishReason == "stop")
        #expect(span.outputMessages.first?.text == "hello")

        // Unknown parts round-trip unchanged; a legacy `result` re-encodes as `response`.
        let reencoded = try JSONCoding.decoder.decode(GenAIMessagePart.self, from: JSONCoding.encoder.encode(parts[4]))
        #expect(reencoded == parts[4])
        let encodedResponse = try JSONValue.from(span.inputMessages[1].parts[0])
        #expect(encodedResponse == ["type": "tool_call_response", "id": "call-0", "response": ["ok": true]])
    }

    @Test func itemsListNormalizesAndFollowsNext() async throws {
        let transport = MockTransport { _, index in
            index == 0
                ? .response(
                    .json(#"{"object":"list","data":[\#(chatSpanJSON)],"first_id":"s2","last_id":"s2","has_more":true,"next":"n2"}"#))
                : .response(
                    .json(#"{"object":"list","data":[\#(toolSpanJSON)],"first_id":"s1","last_id":"s1","has_more":false,"next":null}"#))
        }
        let client = makeClient(transport)
        let items = try await client.conversations.items.list(
            "conv/1", ConversationItemListParams(limit: 1, include: [.events, .toolDefinitions], agent: "root", fromCompaction: true)
        ).collect()
        #expect(items.map(\.spanId) == ["s2", "s1"])
        #expect(transport.requests[0].request.url.absoluteString.contains("/v1/conversations/conv%2F1/items?"))
        #expect(transport.requests[0].query["include"] == ["events", "gen_ai.tool.definitions"])
        #expect(transport.requests[0].query["agent"] == ["root"])
        #expect(transport.requests[0].query["from_compaction"] == ["true"])
        #expect(transport.requests[1].query["next"] == ["n2"])

        let messages = items[0].attribute("gen_ai.input.messages")?.arrayValue ?? []
        let part = messages[1]["parts"]?[0]
        #expect(part?["response"] == ["ok": true])
        #expect(part?["result"] == nil)
    }

    @Test func itemsListRejectsHasMoreWithoutNext() async throws {
        let transport = MockTransport(json: #"{"object":"list","data":[],"has_more":true,"next":null}"#)
        let client = makeClient(transport)
        let error = try await #require(throws: IntrospectionError.self) { try await client.conversations.items.list("c").collect() }
        #expect(error.kind == .decoding)
    }

    @Test func retrieveFindsLatestChatTurn() async throws {
        let transport = MockTransport { request, _ in
            request.url.path.hasSuffix("/items")
                ? .response(.json(#"{"object":"list","data":[\#(toolSpanJSON),\#(chatSpanJSON)],"has_more":false,"next":null}"#))
                : .response(.json(chatSpanJSON))
        }
        let client = makeClient(transport)
        let span = try await client.conversations.retrieve(conversationId: "c1")
        #expect(span?.spanId == "s2")
        #expect(transport.last?.path == "/v1/conversations/c1/items/s2")

        let empty = makeClient(MockTransport(json: #"{"object":"list","data":[],"has_more":false}"#))
        let none = try await empty.conversations.retrieve(conversationId: "c1")
        #expect(none == nil)
    }

    @Test func getTurnsAndExports() async throws {
        let turnJSON = #"""
            {"object":"list","data":[{"object":"conversation.turn","id":"turn-1","trace_id":"t1","ordinal":1,
             "started_at":"2026-10-01T12:00:00Z","ended_at":"2026-10-01T12:00:05Z","status":"completed",
             "messages":[{"id":"m1","role":"user","parts":[{"type":"text","content":"hi"}],"source_span_id":"s1",
              "created_at":"2026-10-01T12:00:00Z","channel_reply":{"command":"reply","status":"sent"}}],
             "response_ids":["r1"],"has_steps":true,"item_count":3,"cost_usd":0.5,"duration_ms":5000}],
             "first_id":"turn-1","last_id":"turn-1","has_more":false,"next":null}
            """#
        let trajectoryJSON = #"""
            [{"role":"meta","source":"claude-code","cwd":"/w"},{"role":"user","content":"hi","timestamp":"2026-10-01T12:00:00Z"},
             {"role":"assistant","content":null,"timestamp":"2026-10-01T12:00:01Z","tool_calls":[{"id":"c1","name":"ls","args":"{}"}]},
             {"role":"tool","tool_call_id":"c1","content":"ok","timestamp":"2026-10-01T12:00:02Z","ok":true}]
            """#
        let transport = MockTransport { request, _ in
            let path = request.url.path
            if path.hasSuffix("/turns") { return .response(.json(turnJSON)) }
            if path.hasSuffix("/export") {
                let accept = request.headers["Accept"] ?? ""
                if accept.contains("trajectory") { return .response(.json(trajectoryJSON)) }
                if accept.contains("arrow") {
                    return .stream(status: 200, headers: ["content-type": accept], chunks: [Data([1, 2]), Data([3])], error: nil)
                }
                return .response(
                    .json(#"{"object":"list","first_id":"s2","data":[\#(chatSpanJSON)],"last_id":"s2","has_more":false,"next":null}"#))
            }
            return .response(.json(conversationJSON))
        }
        let client = makeClient(transport)

        let conversation = try await client.conversations.get("conv-1", shareId: "sh")
        #expect(conversation.taskTitle == "Hello")
        #expect(transport.last?.query["share_id"] == ["sh"])

        let turns = try await client.conversations.turns("conv-1", ConversationTurnListParams(limit: 5, agent: "root", lookbackDays: 7))
            .collect()
        #expect(turns.first?.status == .completed)
        #expect(turns.first?.messages?.first?.channelReply?.status == "sent")
        #expect(turns.first?.messages?.first?.parts.first?.type == "text")
        #expect(transport.last?.path == "/v1/conversations/conv-1/turns")
        #expect(transport.last?.query["lookback_days"] == ["7"])

        let exported = try await client.conversations.exportJSON("conv-1", ConversationExportParams(agent: "root", fromCompaction: true))
        #expect(exported.data.count == 1)
        #expect(transport.last?.request.headers["Accept"] == "application/json")
        #expect(transport.last?.query["from_compaction"] == ["true"])

        let trajectory = try await client.conversations.exportTrajectory("conv-1")
        #expect(trajectory.map(\.role) == ["meta", "user", "assistant", "tool"])
        #expect(trajectory[2].content == nil)
        #expect(trajectory[2].toolCalls?.first?.name == "ls")
        #expect(trajectory[3].ok == true)
        #expect(transport.last?.request.headers["Accept"] == "application/vnd.letta.trajectory+json;version=1")

        let stream = try await client.conversations.exportStream("conv-1", format: .arrow)
        let bytes = try await stream.collect()
        #expect(bytes == Data([1, 2, 3]))
        #expect(transport.last?.request.headers["Accept"] == "application/vnd.apache.arrow.stream")
    }
}
