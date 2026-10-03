// A federated end user: exchange an identity provider's token (here a Supabase
// access token) for a platform token, then run a task on the app's runtime.
// No app backend, no service-account secret.
//
// Run with:
//
//     SUBJECT_TOKEN=<supabase access token> \
//     INTROSPECTION_FEDERATED_CLIENT_ID=intro_app_xxx \
//     INTROSPECTION_PROJECT=ark INTROSPECTION_RUNTIME=ark \
//     INTROSPECTION_BASE_API_URL=https://api.staging.introspection.dev \
//       swift run FederatedExample
//
// In an app, `subjectToken` returns the provider SDK's current token instead,
// for example `{ try await supabase.auth.session.accessToken }`.

import Foundation
import IntrospectionSDK

let env = ProcessInfo.processInfo.environment
func required(_ name: String) -> String {
    guard let value = env[name], !value.isEmpty else {
        print("Set \(name)")
        exit(1)
    }
    return value
}

let subjectToken = required("SUBJECT_TOKEN")
let client = try await IntrospectionClient.federated(
    subjectToken: { subjectToken },
    clientID: required("INTROSPECTION_FEDERATED_CLIENT_ID"),
    project: required("INTROSPECTION_PROJECT"),
    runtime: required("INTROSPECTION_RUNTIME"),
    controlPlaneURL: URL(string: env["INTROSPECTION_BASE_API_URL"] ?? "https://api.introspection.dev")!
)
print("data plane: \(client.dataPlane.baseURL)")

// The runtime group resolves to its current version on the Data Plane.
let run = try await client.tasks.start(prompt: "Say hello in one sentence.")
print("task=\(run.run.taskId)")
print(try await run.text())

// Only this member's tasks are visible.
let mine = try await client.tasks.list(TaskListParams(limit: 5)).firstPage()
print("my recent tasks: \(mine.records.map(\.id))")
