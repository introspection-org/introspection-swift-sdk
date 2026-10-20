// Stand-ins for the application code the docs snippets call: its session,
// its database and its connection to the browser.

import Foundation
import IntrospectionSDK

/// The user signed in to the application, taken from its server session.
struct SignedInUser: Sendable {
    let id: String
}

/// Which task an application record is bound to.
struct AgentBinding: Sendable {
    let taskId: String
    let userId: String
}

/// The application's own order store.
struct OrderStore: Sendable {
    func saveAgentBinding(_ orderId: String, _ binding: AgentBinding) async throws {}
}

/// Forwards one event to the user's browser, for example over server-sent events.
func sendEventToBrowser(_ event: AGUIEvent) async throws {}
