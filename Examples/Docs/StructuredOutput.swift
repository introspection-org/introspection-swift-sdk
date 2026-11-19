// docs: patterns/structured-output

import Foundation
import IntrospectionSDK

enum StructuredOutput {
    static func readStream(runner: Runner) async throws -> String? {
        // #region docs:patterns/structured-output/read-stream
        let handle = try await runner.tasks.start(prompt: "Triage ticket 4411: ...")
        var args: [String: String] = [:]
        var submitId: String?

        for try await event in handle.stream() {
            switch event.payload {
            case let .toolCallStart(start) where start.toolCallName == "submit_result":
                submitId = start.toolCallId
            case let .toolCallArgs(chunk):
                args[chunk.toolCallId, default: ""] += chunk.delta
            case let .messagesSnapshot(snapshot):
                // A stream resumed past its replay buffer sends a snapshot with each call's complete arguments.
                for case let .assistant(message) in snapshot.messages {
                    for call in message.toolCalls ?? [] {
                        if call.function.name == "submit_result" { submitId = call.id }
                        args[call.id] = call.function.arguments
                    }
                }
            default:
                break
            }
        }
        let raw = submitId.flatMap { args[$0] }
        // #endregion docs:patterns/structured-output/read-stream
        return raw
    }

    static func validate(runner: Runner, taskId: String, raw: String?) async throws {
        // #region docs:patterns/structured-output/validate
        // The submit tool's schema, as the recipe's `submit_result` tool declares it.
        struct Triage: Decodable {
            enum Category: String, Decodable {
                case billing, bug, other
            }

            let category: Category
            let priority: Int
            let summary: String

            var isValid: Bool { (1...4).contains(priority) && summary.count <= 280 }
        }

        let result = raw.flatMap { try? JSONDecoder().decode(Triage.self, from: Data($0.utf8)) }
        if result?.isValid != true {
            _ = try await runner.tasks.runs.create(
                taskId,
                TaskRunCreate(text: "You did not call submit_result with a valid triage. Call it now.", kind: .prompt)
            )
        }
        // #endregion docs:patterns/structured-output/validate
    }
}
