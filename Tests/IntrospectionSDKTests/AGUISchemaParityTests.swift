import Foundation
import Testing

@testable import IntrospectionSDK

/// Holds the AG-UI models to `@ag-ui/core`'s own schemas: `Fixtures/ag-ui-core.schema.json`, exported from the
/// published package by `scripts/export-ag-ui-schema.mjs`. Instances are generated from the schema, so a
/// property the models drop, rename or type differently fails here.
@Suite struct AGUISchemaParityTests {
    static let schema: JSONValue = {
        let url = Bundle.module.url(forResource: "ag-ui-core.schema", withExtension: "json", subdirectory: "Fixtures")!
        return try! JSONCoding.decoder.decode(JSONValue.self, from: Data(contentsOf: url))
    }()
    static let defs = schema["$defs"]!.objectValue!
    static let eventDefs = defs["Event"]!["oneOf"]!.arrayValue!.map { defName($0["$ref"]!.stringValue!) }

    /// Every reachable non-event `$def` with a shape, and how it round-trips through its Swift type.
    static let models: [String: @Sendable (JSONValue) throws -> JSONValue] = [
        "Message": roundTrip(AGUI.Message.self),
        "DeveloperMessage": roundTrip(AGUI.DeveloperMessage.self),
        "SystemMessage": roundTrip(AGUI.SystemMessage.self),
        "AssistantMessage": roundTrip(AGUI.AssistantMessage.self),
        "UserMessage": roundTrip(AGUI.UserMessage.self),
        "ToolMessage": roundTrip(AGUI.ToolMessage.self),
        "ActivityMessage": roundTrip(AGUI.ActivityMessage.self),
        "ReasoningMessage": roundTrip(AGUI.ReasoningMessage.self),
        "ToolCall": roundTrip(AGUI.ToolCall.self),
        "FunctionCall": roundTrip(AGUI.FunctionCall.self),
        "InputContent": roundTrip(AGUI.InputContent.self),
        "TextPart": roundTrip(AGUI.TextPart.self),
        "ImagePart": roundTrip(AGUI.ImagePart.self),
        "AudioPart": roundTrip(AGUI.AudioPart.self),
        "VideoPart": roundTrip(AGUI.VideoPart.self),
        "DocumentPart": roundTrip(AGUI.DocumentPart.self),
        "PartSource": roundTrip(AGUI.InputContentSource.self),
        "InputContentDataSource": roundTrip(AGUI.DataSource.self),
        "UrlSource": roundTrip(AGUI.UrlSource.self),
        "FileSource": roundTrip(AGUI.FileSource.self),
        "Interrupt": roundTrip(AGUI.Interrupt.self),
        "RunFinishedOutcome": roundTrip(AGUI.RunFinishedOutcome.self),
        "RunFinishedSuccessOutcome": roundTrip(AGUI.RunFinishedSuccessOutcome.self),
        "RunFinishedInterruptOutcome": roundTrip(AGUI.RunFinishedInterruptOutcome.self),
        "RunFinishedCancelledOutcome": roundTrip(AGUI.RunFinishedCancelledOutcome.self),
        "SubagentFinishedOutcome": roundTrip(AGUI.SubagentFinishedOutcome.self),
        "SubagentFinishedSuccessOutcome": roundTrip(AGUI.SubagentFinishedSuccessOutcome.self),
        "SubagentFinishedSuspendedOutcome": roundTrip(AGUI.SubagentFinishedSuspendedOutcome.self),
        "JsonPatch": roundTrip([AGUI.JsonPatchOperation].self),
        "JsonPatchOperation": roundTrip(AGUI.JsonPatchOperation.self),
        "AddOperation": roundTrip(AGUI.AddOperation.self),
        "RemoveOperation": roundTrip(AGUI.RemoveOperation.self),
        "ReplaceOperation": roundTrip(AGUI.ReplaceOperation.self),
        "MoveOperation": roundTrip(AGUI.MoveOperation.self),
        "CopyOperation": roundTrip(AGUI.CopyOperation.self),
        "TestOperation": roundTrip(AGUI.TestOperation.self),
        "RunAgentInput": roundTrip(AGUI.RunAgentInput.self),
        "Tool": roundTrip(AGUI.Tool.self),
        "Context": roundTrip(AGUI.Context.self),
        "ResumeEntry": roundTrip(AGUI.ResumeEntry.self),
        "TokenUsage": roundTrip(AGUI.TokenUsage.self),
    ]

    /// Unions rotate through their branches across variants; arrays already hold one item per branch.
    static let variants = 0..<7

    static func defName(_ ref: String) -> String { String(ref.split(separator: "/").last!) }

    static func roundTrip<T: Codable & SendableMetatype>(_: T.Type) -> @Sendable (JSONValue) throws -> JSONValue {
        { try JSONValue.from($0.decode(T.self)) }
    }

    static func typedBody(_ instance: JSONValue) -> JSONValue? {
        AGUIEvent(raw: instance).payload.body.flatMap { try? JSONValue.from($0) }
    }

    // MARK: Events

    @Test func eventTypesMatchTheSchemaExactly() {
        let consts = Set(Self.eventDefs.map { Self.defs[$0]!["properties"]!["type"]!["const"]!.stringValue! })
        let enumerated = Set(Self.defs["EventType"]!["enum"]!.arrayValue!.compactMap(\.stringValue))
        let constants: [AGUIEventType] = [
            .textMessageStart, .textMessageContent, .textMessageEnd, .textMessageChunk, .toolCallStart, .toolCallArgs,
            .toolCallEnd, .toolCallChunk, .toolCallResult, .stateSnapshot, .stateDelta, .messagesSnapshot,
            .activitySnapshot, .activityDelta, .raw, .custom, .runStarted, .runFinished, .runError, .stepStarted,
            .stepFinished, .reasoningStart, .reasoningMessageStart, .reasoningMessageContent, .reasoningMessageEnd,
            .reasoningMessageChunk, .reasoningEnd, .reasoningEncryptedValue, .subagentStarted, .subagentFinished,
            .subagentError,
        ]
        #expect(consts.count == 31)
        #expect(consts == enumerated)
        #expect(Set(constants.map(\.rawValue)) == consts)
        #expect(constants.count == consts.count)
        #expect(Set(AGUIEventPayload.decoders.keys) == consts)
    }

    @Test(arguments: eventDefs) func maximalEventRoundTripsTyped(_ name: String) throws {
        let def = Self.defs[name]!
        let type = def["properties"]!["type"]!["const"]!.stringValue!
        for variant in Self.variants {
            var sampler = SchemaSampler(defs: Self.defs, variant: variant, maximal: true)
            let instance = sampler.sample(def)
            let event = AGUIEvent(raw: instance)
            let body = try #require(event.payload.body, "\(name) variant \(variant) decoded as .unknown: \(instance)")
            #expect(Swift.type(of: body).eventType.rawValue == type)
            #expect(try JSONValue.from(body) == instance, "\(name) variant \(variant)")
        }
    }

    @Test(arguments: eventDefs) func minimalEventRoundTripsTyped(_ name: String) {
        var sampler = SchemaSampler(defs: Self.defs, variant: 0, maximal: false)
        let instance = sampler.sample(Self.defs[name]!)
        #expect(Self.typedBody(instance) == instance, "\(name): \(instance)")
    }

    @Test(arguments: eventDefs) func eventMissingARequiredPropertyIsUnknown(_ name: String) {
        for maximal in [false, true] {
            var counter = SchemaSampler(defs: Self.defs, variant: 0, maximal: maximal)
            _ = counter.sample(Self.defs[name]!)
            #expect(counter.requiredSeen > 0)
            for drop in 0..<counter.requiredSeen {
                var sampler = SchemaSampler(defs: Self.defs, variant: 0, maximal: maximal, drop: drop)
                let instance = sampler.sample(Self.defs[name]!)
                #expect(AGUIEvent(raw: instance).payload == .unknown, "\(name) without required #\(drop): \(instance)")
                #expect(AGUIEvent(raw: instance).raw == instance)
            }
        }
    }

    @Test(arguments: eventDefs) func eventWithAnOutOfSchemaConstantIsUnknown(_ name: String) {
        for variant in Self.variants {
            var counter = SchemaSampler(defs: Self.defs, variant: variant, maximal: true)
            _ = counter.sample(Self.defs[name]!)
            for poison in 0..<counter.constantsSeen {
                var sampler = SchemaSampler(defs: Self.defs, variant: variant, maximal: true, poison: poison)
                let instance = sampler.sample(Self.defs[name]!)
                #expect(AGUIEvent(raw: instance).payload == .unknown, "\(name) with constant #\(poison) out of schema: \(instance)")
            }
        }
    }

    @Test func nonIntegerTimestampIsUnknown() {
        #expect(AGUIEvent(raw: ["type": "TEXT_MESSAGE_END", "messageId": "m", "timestamp": 1.5]).payload == .unknown)
        #expect(AGUIEvent(raw: ["type": "TEXT_MESSAGE_END", "messageId": "m", "timestamp": 1_700_000_000_000]).payload != .unknown)
    }

    // MARK: Messages, content and the other reachable types

    @Test func everyReachableDefinitionHasAModel() {
        var reachable = Set<String>()
        var pending = ["Event"]
        while let name = pending.popLast() {
            guard reachable.insert(name).inserted else { continue }
            pending += Self.refs(in: Self.defs[name]!)
        }
        let shaped = reachable.filter { name in
            let def = Self.defs[name]!
            return def["properties"] != nil || def["oneOf"] != nil || def["type"] == "array"
        }
        #expect(shaped.subtracting(Self.eventDefs).subtracting(["Event"]) == Set(Self.models.keys))
        #expect(Set(reachable.filter { Self.defs[$0]!["properties"] != nil }) == Set(Self.inits.keys))
    }

    @Test func closedEnumsMatchTheSchema() {
        func values(_ schema: JSONValue) -> [String] { schema["enum"]!.arrayValue!.compactMap(\.stringValue) }
        #expect(AGUI.TextMessageRole.allCases.map(\.rawValue) == values(Self.defs["TextMessageRole"]!))
        #expect(
            AGUI.ReasoningEncryptedValueSubtype.allCases.map(\.rawValue) == values(Self.defs["ReasoningEncryptedValueSubtype"]!))
        #expect(AGUI.ResumeStatus.allCases.map(\.rawValue) == values(Self.defs["ResumeEntry"]!["properties"]!["status"]!))
    }

    @Test(arguments: models.keys.sorted()) func modelRoundTrips(_ name: String) throws {
        let roundTrip = Self.models[name]!
        for (variant, maximal) in Self.variants.map({ ($0, true) }) + [(0, false)] {
            var sampler = SchemaSampler(defs: Self.defs, variant: variant, maximal: maximal)
            let instance = sampler.sample(Self.defs[name]!)
            #expect(try roundTrip(instance) == instance, "\(name) variant \(variant) maximal \(maximal)")
        }
    }

    @Test(arguments: models.keys.sorted()) func modelRejectsWhatItsSchemaRejects(_ name: String) {
        let roundTrip = Self.models[name]!
        var counter = SchemaSampler(defs: Self.defs, variant: 0, maximal: true)
        _ = counter.sample(Self.defs[name]!)
        for drop in 0..<counter.requiredSeen {
            var sampler = SchemaSampler(defs: Self.defs, variant: 0, maximal: true, drop: drop)
            let instance = sampler.sample(Self.defs[name]!)
            #expect(throws: (any Error).self, "\(name) without required #\(drop)") { try roundTrip(instance) }
        }
        for poison in 0..<counter.constantsSeen {
            var sampler = SchemaSampler(defs: Self.defs, variant: 0, maximal: true, poison: poison)
            let instance = sampler.sample(Self.defs[name]!)
            #expect(throws: (any Error).self, "\(name) with constant #\(poison) out of schema") { try roundTrip(instance) }
        }
    }

    /// Rebuilds each struct through its public init from a decoded instance, so an init that skips a property fails.
    static let inits: [String: @Sendable (JSONValue) throws -> Bool] = [
        "DeveloperMessage": {
            let m = try $0.decode(AGUI.DeveloperMessage.self);
            return AGUI.DeveloperMessage(
                id: m.id, content: m.content, subagentRunId: m.subagentRunId, name: m.name, encryptedValue: m.encryptedValue,
                metadata: m.metadata) == m
        },
        "SystemMessage": {
            let m = try $0.decode(AGUI.SystemMessage.self);
            return AGUI.SystemMessage(
                id: m.id, content: m.content, subagentRunId: m.subagentRunId, name: m.name, encryptedValue: m.encryptedValue,
                metadata: m.metadata) == m
        },
        "AssistantMessage": {
            let m = try $0.decode(AGUI.AssistantMessage.self);
            return AGUI.AssistantMessage(
                id: m.id, subagentRunId: m.subagentRunId, name: m.name, encryptedValue: m.encryptedValue, content: m.content,
                toolCalls: m.toolCalls, metadata: m.metadata) == m
        },
        "UserMessage": {
            let m = try $0.decode(AGUI.UserMessage.self);
            return AGUI.UserMessage(
                id: m.id, content: m.content, subagentRunId: m.subagentRunId, name: m.name, encryptedValue: m.encryptedValue,
                metadata: m.metadata) == m
        },
        "ToolMessage": {
            let m = try $0.decode(AGUI.ToolMessage.self);
            return AGUI.ToolMessage(
                id: m.id, content: m.content, toolCallId: m.toolCallId, subagentRunId: m.subagentRunId, error: m.error,
                encryptedValue: m.encryptedValue, metadata: m.metadata) == m
        },
        "ActivityMessage": {
            let m = try $0.decode(AGUI.ActivityMessage.self);
            return AGUI.ActivityMessage(
                id: m.id, activityType: m.activityType, content: m.content, subagentRunId: m.subagentRunId, metadata: m.metadata) == m
        },
        "ReasoningMessage": {
            let m = try $0.decode(AGUI.ReasoningMessage.self);
            return AGUI.ReasoningMessage(
                id: m.id, content: m.content, subagentRunId: m.subagentRunId, encryptedValue: m.encryptedValue, metadata: m.metadata) == m
        },
        "ToolCall": {
            let m = try $0.decode(AGUI.ToolCall.self);
            return AGUI.ToolCall(id: m.id, function: m.function, encryptedValue: m.encryptedValue, metadata: m.metadata) == m
        },
        "FunctionCall": {
            let m = try $0.decode(AGUI.FunctionCall.self); return AGUI.FunctionCall(name: m.name, arguments: m.arguments) == m
        },
        "TextPart": {
            let m = try $0.decode(AGUI.TextPart.self); return AGUI.TextPart(text: m.text, id: m.id, metadata: m.metadata) == m
        },
        "ImagePart": {
            let m = try $0.decode(AGUI.ImagePart.self); return AGUI.ImagePart(source: m.source, id: m.id, metadata: m.metadata) == m
        },
        "AudioPart": {
            let m = try $0.decode(AGUI.AudioPart.self); return AGUI.AudioPart(source: m.source, id: m.id, metadata: m.metadata) == m
        },
        "VideoPart": {
            let m = try $0.decode(AGUI.VideoPart.self); return AGUI.VideoPart(source: m.source, id: m.id, metadata: m.metadata) == m
        },
        "DocumentPart": {
            let m = try $0.decode(AGUI.DocumentPart.self); return AGUI.DocumentPart(source: m.source, id: m.id, metadata: m.metadata) == m
        },
        "InputContentDataSource": {
            let m = try $0.decode(AGUI.DataSource.self); return AGUI.DataSource(value: m.value, mimeType: m.mimeType) == m
        },
        "UrlSource": {
            let m = try $0.decode(AGUI.UrlSource.self); return AGUI.UrlSource(value: m.value, mimeType: m.mimeType) == m
        },
        "FileSource": {
            let m = try $0.decode(AGUI.FileSource.self);
            return AGUI.FileSource(value: m.value, provider: m.provider, mimeType: m.mimeType) == m
        },
        "Interrupt": {
            let m = try $0.decode(AGUI.Interrupt.self);
            return AGUI.Interrupt(
                id: m.id, reason: m.reason, subagentRunId: m.subagentRunId, message: m.message, toolCallId: m.toolCallId,
                responseSchema: m.responseSchema, expiresAt: m.expiresAt, metadata: m.metadata) == m
        },
        "RunFinishedSuccessOutcome": {
            let m = try $0.decode(AGUI.RunFinishedSuccessOutcome.self);
            return AGUI.RunFinishedSuccessOutcome(pendingToolCallIds: m.pendingToolCallIds) == m
        },
        "RunFinishedInterruptOutcome": {
            let m = try $0.decode(AGUI.RunFinishedInterruptOutcome.self);
            return AGUI.RunFinishedInterruptOutcome(interrupts: m.interrupts) == m
        },
        "RunFinishedCancelledOutcome": {
            let m = try $0.decode(AGUI.RunFinishedCancelledOutcome.self); return AGUI.RunFinishedCancelledOutcome() == m
        },
        "SubagentFinishedSuccessOutcome": {
            let m = try $0.decode(AGUI.SubagentFinishedSuccessOutcome.self); return AGUI.SubagentFinishedSuccessOutcome() == m
        },
        "SubagentFinishedSuspendedOutcome": {
            let m = try $0.decode(AGUI.SubagentFinishedSuspendedOutcome.self);
            return AGUI.SubagentFinishedSuspendedOutcome(interruptIds: m.interruptIds) == m
        },
        "AddOperation": {
            let m = try $0.decode(AGUI.AddOperation.self); return AGUI.AddOperation(path: m.path, value: m.value) == m
        },
        "RemoveOperation": {
            let m = try $0.decode(AGUI.RemoveOperation.self); return AGUI.RemoveOperation(path: m.path) == m
        },
        "ReplaceOperation": {
            let m = try $0.decode(AGUI.ReplaceOperation.self); return AGUI.ReplaceOperation(path: m.path, value: m.value) == m
        },
        "MoveOperation": {
            let m = try $0.decode(AGUI.MoveOperation.self); return AGUI.MoveOperation(from: m.from, path: m.path) == m
        },
        "CopyOperation": {
            let m = try $0.decode(AGUI.CopyOperation.self); return AGUI.CopyOperation(from: m.from, path: m.path) == m
        },
        "TestOperation": {
            let m = try $0.decode(AGUI.TestOperation.self); return AGUI.TestOperation(path: m.path, value: m.value) == m
        },
        "RunAgentInput": {
            let m = try $0.decode(AGUI.RunAgentInput.self);
            return AGUI.RunAgentInput(
                threadId: m.threadId, runId: m.runId, messages: m.messages, protocolVersion: m.protocolVersion, parentRunId: m.parentRunId,
                state: m.state, tools: m.tools, context: m.context, forwardedProps: m.forwardedProps, resume: m.resume) == m
        },
        "Tool": {
            let m = try $0.decode(AGUI.Tool.self);
            return AGUI.Tool(name: m.name, description: m.description, parameters: m.parameters, metadata: m.metadata) == m
        },
        "Context": {
            let m = try $0.decode(AGUI.Context.self); return AGUI.Context(description: m.description, value: m.value) == m
        },
        "ResumeEntry": {
            let m = try $0.decode(AGUI.ResumeEntry.self);
            return AGUI.ResumeEntry(interruptId: m.interruptId, status: m.status, payload: m.payload, metadata: m.metadata) == m
        },
        "TokenUsage": {
            let m = try $0.decode(AGUI.TokenUsage.self);
            return AGUI.TokenUsage(
                provider: m.provider, model: m.model, inputTokens: m.inputTokens, outputTokens: m.outputTokens, totalTokens: m.totalTokens,
                reasoningTokens: m.reasoningTokens, cachedInputTokens: m.cachedInputTokens, cacheWriteInputTokens: m.cacheWriteInputTokens)
                == m
        },
        "TextMessageStartEvent": {
            let m = try $0.decode(AGUI.TextMessageStartEvent.self);
            return AGUI.TextMessageStartEvent(
                messageId: m.messageId, subagentRunId: m.subagentRunId, role: m.role, name: m.name, timestamp: m.timestamp,
                rawEvent: m.rawEvent, metadata: m.metadata) == m
        },
        "TextMessageContentEvent": {
            let m = try $0.decode(AGUI.TextMessageContentEvent.self);
            return AGUI.TextMessageContentEvent(
                messageId: m.messageId, delta: m.delta, subagentRunId: m.subagentRunId, timestamp: m.timestamp, rawEvent: m.rawEvent,
                metadata: m.metadata) == m
        },
        "TextMessageEndEvent": {
            let m = try $0.decode(AGUI.TextMessageEndEvent.self);
            return AGUI.TextMessageEndEvent(
                messageId: m.messageId, subagentRunId: m.subagentRunId, timestamp: m.timestamp, rawEvent: m.rawEvent, metadata: m.metadata)
                == m
        },
        "TextMessageChunkEvent": {
            let m = try $0.decode(AGUI.TextMessageChunkEvent.self);
            return AGUI.TextMessageChunkEvent(
                subagentRunId: m.subagentRunId, messageId: m.messageId, role: m.role, delta: m.delta, name: m.name, timestamp: m.timestamp,
                rawEvent: m.rawEvent, metadata: m.metadata) == m
        },
        "ToolCallStartEvent": {
            let m = try $0.decode(AGUI.ToolCallStartEvent.self);
            return AGUI.ToolCallStartEvent(
                toolCallId: m.toolCallId, toolCallName: m.toolCallName, subagentRunId: m.subagentRunId, parentMessageId: m.parentMessageId,
                timestamp: m.timestamp, rawEvent: m.rawEvent, metadata: m.metadata) == m
        },
        "ToolCallArgsEvent": {
            let m = try $0.decode(AGUI.ToolCallArgsEvent.self);
            return AGUI.ToolCallArgsEvent(
                toolCallId: m.toolCallId, delta: m.delta, subagentRunId: m.subagentRunId, timestamp: m.timestamp, rawEvent: m.rawEvent,
                metadata: m.metadata) == m
        },
        "ToolCallEndEvent": {
            let m = try $0.decode(AGUI.ToolCallEndEvent.self);
            return AGUI.ToolCallEndEvent(
                toolCallId: m.toolCallId, subagentRunId: m.subagentRunId, timestamp: m.timestamp, rawEvent: m.rawEvent, metadata: m.metadata
            ) == m
        },
        "ToolCallChunkEvent": {
            let m = try $0.decode(AGUI.ToolCallChunkEvent.self);
            return AGUI.ToolCallChunkEvent(
                subagentRunId: m.subagentRunId, toolCallId: m.toolCallId, toolCallName: m.toolCallName, parentMessageId: m.parentMessageId,
                delta: m.delta, timestamp: m.timestamp, rawEvent: m.rawEvent, metadata: m.metadata) == m
        },
        "ToolCallResultEvent": {
            let m = try $0.decode(AGUI.ToolCallResultEvent.self);
            return AGUI.ToolCallResultEvent(
                messageId: m.messageId, toolCallId: m.toolCallId, content: m.content, subagentRunId: m.subagentRunId, role: m.role,
                timestamp: m.timestamp, rawEvent: m.rawEvent, metadata: m.metadata) == m
        },
        "StateSnapshotEvent": {
            let m = try $0.decode(AGUI.StateSnapshotEvent.self);
            return AGUI.StateSnapshotEvent(
                snapshot: m.snapshot, subagentRunId: m.subagentRunId, timestamp: m.timestamp, rawEvent: m.rawEvent, metadata: m.metadata)
                == m
        },
        "StateDeltaEvent": {
            let m = try $0.decode(AGUI.StateDeltaEvent.self);
            return AGUI.StateDeltaEvent(
                delta: m.delta, subagentRunId: m.subagentRunId, timestamp: m.timestamp, rawEvent: m.rawEvent, metadata: m.metadata) == m
        },
        "MessagesSnapshotEvent": {
            let m = try $0.decode(AGUI.MessagesSnapshotEvent.self);
            return AGUI.MessagesSnapshotEvent(messages: m.messages, timestamp: m.timestamp, rawEvent: m.rawEvent, metadata: m.metadata) == m
        },
        "ActivitySnapshotEvent": {
            let m = try $0.decode(AGUI.ActivitySnapshotEvent.self);
            return AGUI.ActivitySnapshotEvent(
                messageId: m.messageId, activityType: m.activityType, content: m.content, subagentRunId: m.subagentRunId,
                replace: m.replace, timestamp: m.timestamp, rawEvent: m.rawEvent, metadata: m.metadata) == m
        },
        "ActivityDeltaEvent": {
            let m = try $0.decode(AGUI.ActivityDeltaEvent.self);
            return AGUI.ActivityDeltaEvent(
                messageId: m.messageId, activityType: m.activityType, patch: m.patch, subagentRunId: m.subagentRunId,
                timestamp: m.timestamp, rawEvent: m.rawEvent, metadata: m.metadata) == m
        },
        "RawEvent": {
            let m = try $0.decode(AGUI.RawEvent.self);
            return AGUI.RawEvent(
                event: m.event, subagentRunId: m.subagentRunId, source: m.source, timestamp: m.timestamp, rawEvent: m.rawEvent,
                metadata: m.metadata) == m
        },
        "CustomEvent": {
            let m = try $0.decode(AGUI.CustomEvent.self);
            return AGUI.CustomEvent(
                name: m.name, value: m.value, subagentRunId: m.subagentRunId, timestamp: m.timestamp, rawEvent: m.rawEvent,
                metadata: m.metadata) == m
        },
        "RunStartedEvent": {
            let m = try $0.decode(AGUI.RunStartedEvent.self);
            return AGUI.RunStartedEvent(
                threadId: m.threadId, runId: m.runId, protocolVersion: m.protocolVersion, parentRunId: m.parentRunId, input: m.input,
                timestamp: m.timestamp, rawEvent: m.rawEvent, metadata: m.metadata) == m
        },
        "RunFinishedEvent": {
            let m = try $0.decode(AGUI.RunFinishedEvent.self);
            return AGUI.RunFinishedEvent(
                threadId: m.threadId, runId: m.runId, result: m.result, outcome: m.outcome, usage: m.usage, timestamp: m.timestamp,
                rawEvent: m.rawEvent, metadata: m.metadata) == m
        },
        "RunErrorEvent": {
            let m = try $0.decode(AGUI.RunErrorEvent.self);
            return AGUI.RunErrorEvent(
                message: m.message, code: m.code, usage: m.usage, timestamp: m.timestamp, rawEvent: m.rawEvent, metadata: m.metadata) == m
        },
        "StepStartedEvent": {
            let m = try $0.decode(AGUI.StepStartedEvent.self);
            return AGUI.StepStartedEvent(
                stepName: m.stepName, subagentRunId: m.subagentRunId, timestamp: m.timestamp, rawEvent: m.rawEvent, metadata: m.metadata)
                == m
        },
        "StepFinishedEvent": {
            let m = try $0.decode(AGUI.StepFinishedEvent.self);
            return AGUI.StepFinishedEvent(
                stepName: m.stepName, subagentRunId: m.subagentRunId, timestamp: m.timestamp, rawEvent: m.rawEvent, metadata: m.metadata)
                == m
        },
        "ReasoningStartEvent": {
            let m = try $0.decode(AGUI.ReasoningStartEvent.self);
            return AGUI.ReasoningStartEvent(
                messageId: m.messageId, subagentRunId: m.subagentRunId, timestamp: m.timestamp, rawEvent: m.rawEvent, metadata: m.metadata)
                == m
        },
        "ReasoningMessageStartEvent": {
            let m = try $0.decode(AGUI.ReasoningMessageStartEvent.self);
            return AGUI.ReasoningMessageStartEvent(
                messageId: m.messageId, subagentRunId: m.subagentRunId, timestamp: m.timestamp, rawEvent: m.rawEvent, metadata: m.metadata)
                == m
        },
        "ReasoningMessageContentEvent": {
            let m = try $0.decode(AGUI.ReasoningMessageContentEvent.self);
            return AGUI.ReasoningMessageContentEvent(
                messageId: m.messageId, delta: m.delta, subagentRunId: m.subagentRunId, timestamp: m.timestamp, rawEvent: m.rawEvent,
                metadata: m.metadata) == m
        },
        "ReasoningMessageEndEvent": {
            let m = try $0.decode(AGUI.ReasoningMessageEndEvent.self);
            return AGUI.ReasoningMessageEndEvent(
                messageId: m.messageId, subagentRunId: m.subagentRunId, timestamp: m.timestamp, rawEvent: m.rawEvent, metadata: m.metadata)
                == m
        },
        "ReasoningMessageChunkEvent": {
            let m = try $0.decode(AGUI.ReasoningMessageChunkEvent.self);
            return AGUI.ReasoningMessageChunkEvent(
                subagentRunId: m.subagentRunId, messageId: m.messageId, delta: m.delta, timestamp: m.timestamp, rawEvent: m.rawEvent,
                metadata: m.metadata) == m
        },
        "ReasoningEndEvent": {
            let m = try $0.decode(AGUI.ReasoningEndEvent.self);
            return AGUI.ReasoningEndEvent(
                messageId: m.messageId, subagentRunId: m.subagentRunId, timestamp: m.timestamp, rawEvent: m.rawEvent, metadata: m.metadata)
                == m
        },
        "ReasoningEncryptedValueEvent": {
            let m = try $0.decode(AGUI.ReasoningEncryptedValueEvent.self);
            return AGUI.ReasoningEncryptedValueEvent(
                subtype: m.subtype, entityId: m.entityId, encryptedValue: m.encryptedValue, subagentRunId: m.subagentRunId,
                timestamp: m.timestamp, rawEvent: m.rawEvent, metadata: m.metadata) == m
        },
        "SubagentStartedEvent": {
            let m = try $0.decode(AGUI.SubagentStartedEvent.self);
            return AGUI.SubagentStartedEvent(
                subagentRunId: m.subagentRunId, name: m.name, description: m.description, parentSubagentRunId: m.parentSubagentRunId,
                parentToolCallId: m.parentToolCallId, parentMessageId: m.parentMessageId, timestamp: m.timestamp, rawEvent: m.rawEvent,
                metadata: m.metadata) == m
        },
        "SubagentFinishedEvent": {
            let m = try $0.decode(AGUI.SubagentFinishedEvent.self);
            return AGUI.SubagentFinishedEvent(
                subagentRunId: m.subagentRunId, result: m.result, outcome: m.outcome, timestamp: m.timestamp, rawEvent: m.rawEvent,
                metadata: m.metadata) == m
        },
        "SubagentErrorEvent": {
            let m = try $0.decode(AGUI.SubagentErrorEvent.self);
            return AGUI.SubagentErrorEvent(
                subagentRunId: m.subagentRunId, message: m.message, code: m.code, timestamp: m.timestamp, rawEvent: m.rawEvent,
                metadata: m.metadata) == m
        },
    ]

    @Test(arguments: inits.keys.sorted()) func publicInitSetsEveryProperty(_ name: String) throws {
        for variant in Self.variants {
            var sampler = SchemaSampler(defs: Self.defs, variant: variant, maximal: true)
            #expect(try Self.inits[name]!(sampler.sample(Self.defs[name]!)), "\(name) variant \(variant)")
        }
    }

    static func refs(in schema: JSONValue) -> [String] {
        switch schema {
        case let .object(object):
            let own = object["$ref"]?.stringValue.map { [defName($0)] } ?? []
            return own + object.values.flatMap(refs(in:))
        case let .array(array):
            return array.flatMap(refs(in:))
        default:
            return []
        }
    }
}

/// Generates schema-valid instances over `JSONValue`. `poison` replaces the n-th constant or enum value met with
/// one outside the schema, and `drop` omits the n-th required property met, so each can be made invalid in turn.
struct SchemaSampler {
    let defs: [String: JSONValue]
    var variant: Int
    let maximal: Bool
    var poison: Int?
    var drop: Int?
    private(set) var constantsSeen = 0
    private(set) var requiredSeen = 0

    init(defs: [String: JSONValue], variant: Int, maximal: Bool, poison: Int? = nil, drop: Int? = nil) {
        self.defs = defs
        self.variant = variant
        self.maximal = maximal
        self.poison = poison
        self.drop = drop
    }

    mutating func sample(_ schema: JSONValue) -> JSONValue {
        if let ref = schema["$ref"]?.stringValue {
            return sample(defs[AGUISchemaParityTests.defName(ref)]!)
        }
        if let value = schema["const"] { return constant(value) }
        if let values = schema["enum"]?.arrayValue { return constant(values[variant % values.count]) }
        if let branches = (schema["oneOf"] ?? schema["anyOf"])?.arrayValue {
            return sample(branches[variant % branches.count])
        }
        switch schema["type"]?.stringValue {
        case "object": return object(schema)
        case "array": return array(of: schema["items"]!)
        case "string": return schema["pattern"] == nil ? "text" : "/a/b~1c"
        case "integer": return 42
        case "boolean": return true
        case "null": return .null
        default: return ["any": [1, "two", false, ["nested": "value"]]]
        }
    }

    private mutating func constant(_ value: JSONValue) -> JSONValue {
        defer { constantsSeen += 1 }
        return constantsSeen == poison ? "not-in-the-schema" : value
    }

    private mutating func object(_ schema: JSONValue) -> JSONValue {
        let required = Set(schema["required"]?.arrayValue?.compactMap(\.stringValue) ?? [])
        var object: [String: JSONValue] = [:]
        for (key, property) in (schema["properties"]?.objectValue ?? [:]).sorted(by: { $0.key < $1.key }) {
            if required.contains(key) {
                requiredSeen += 1
                if requiredSeen - 1 == drop { continue }
            } else if !maximal {
                continue
            }
            object[key] = sample(property)
        }
        return .object(object)
    }

    /// One item per branch of the item schema, so one instance holds every member of a union.
    private mutating func array(of items: JSONValue) -> JSONValue {
        let start = variant
        defer { variant = start }
        return .array(
            (0..<branchCount(items)).map { offset in
                variant = start + offset
                return sample(items)
            })
    }

    private func branchCount(_ schema: JSONValue) -> Int {
        if let ref = schema["$ref"]?.stringValue { return branchCount(defs[AGUISchemaParityTests.defName(ref)]!) }
        return max((schema["oneOf"] ?? schema["anyOf"])?.arrayValue?.count ?? 1, 1)
    }
}
