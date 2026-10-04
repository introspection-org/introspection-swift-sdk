import Foundation
import Testing

/// The live settings, read once, so a test whose settings are missing is skipped before it runs.
enum Live {
    static let environment = ProcessInfo.processInfo.environment
    static let isEnabled = environment["INTROSPECTION_LIVE"] == "1"

    static func value(_ name: String) -> String? {
        environment[name].flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The settings a federated client for the test user `prefix` reads.
    static func federated(_ prefix: String) -> [String] {
        [
            "SUPABASE_URL", "SUPABASE_PUBLISHABLE_KEY", "\(prefix)_EMAIL", "\(prefix)_PASSWORD",
            "INTROSPECTION_FEDERATED_CLIENT_ID", "INTROSPECTION_PROJECT",
        ]
    }

    /// The settings the service-account lookup of the runtime version reads.
    static let runtimeLookup = ["INTROSPECTION_CLIENT_ID", "INTROSPECTION_CLIENT_SECRET", "INTROSPECTION_RUNTIME"]

    static func requires(_ names: String...) -> ConditionTrait { requires(names) }

    /// Enabled when the Control Plane URL and every named setting are set.
    static func requires(_ names: [String]) -> ConditionTrait {
        let controlPlane = value("INTROSPECTION_BASE_API_URL") ?? value("INTROSPECTION_BASE_URL")
        let settings = (controlPlane == nil ? ["INTROSPECTION_BASE_URL"] : []) + names.filter { value($0) == nil }
        var seen: Set<String> = []
        let missing = settings.filter { seen.insert($0).inserted }
        return .enabled(
            if: missing.isEmpty, Comment(rawValue: "\(missing.joined(separator: ", ")) \(missing.count == 1 ? "is" : "are") not set"))
    }
}
