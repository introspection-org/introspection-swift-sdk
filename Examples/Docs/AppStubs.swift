// Stand-ins for the application values the docs snippets receive: its signed-in
// user and its stored task bindings. App code a snippet calls is stubbed inside
// its region instead.

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
