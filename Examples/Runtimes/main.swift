// End-to-end walkthrough: look up a runtime by runtime group slug, open a Runner,
// spawn a task, stream its run, then upload files. A port of the Rust SDK's
// examples/api/runtimes.rs.
//
// Run with:
//
//     INTROSPECTION_TOKEN=intro_xxx \
//     INTROSPECTION_BASE_API_URL=http://localhost:8000 \
//       swift run RuntimesExample

import Foundation
import IntrospectionSDK

let env = ProcessInfo.processInfo.environment
guard let token = env["INTROSPECTION_TOKEN"] else {
    print("Set INTROSPECTION_TOKEN")
    exit(1)
}
let baseURL = URL(string: env["INTROSPECTION_BASE_API_URL"] ?? "https://api.introspection.dev")!
let runtime = env["INTROSPECTION_RUNTIME"] ?? "customer-agent"
let client = IntrospectionClient(controlPlaneURL: baseURL, credentials: BearerToken(token))

// 1) Look up the runtime by runtime group slug or id and open a Runner.
let runner = try await client.runtimes(runtime).run(ttlSeconds: 3600)
print("runner -> dp=\(runner.dataPlaneEndpoint), session=\(runner.sessionId), expires=\(String(describing: runner.expiresAt))")

// 2) Spawn a task and stream its events.
let run = try await runner.tasks.start(
    prompt: "Say hello in one sentence.",
    TaskCreate(conversationMetadata: ["flow": "runner_example"])
)
print("spawned task=\(run.run.taskId), run=\(run.run.id)")

for try await event in run.stream() where event.eventType == .textMessageContent {
    print(event.delta ?? "", terminator: "")
}
print()

let conversations = try await runner.conversations.list(ConversationListParams(metadata: ["flow": "runner_example"])).firstPage()
print("matching conversations: \(conversations.records.count)")

// 3) Upload files via the runner.
let note = try await runner.files.createText(
    FileCreateText(content: "# Hello\n\nFrom the Swift SDK Runner.", name: "notes.md", mimeType: "text/markdown")
)
print("created file: \(note.id)")

let binary = try await runner.files.upload(FileUpload(data: Data("hello binary".utf8), filename: "hello.bin"))
print("uploaded binary file: \(binary.id)")

runner.close()
