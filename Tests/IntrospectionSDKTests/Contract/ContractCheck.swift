import Foundation

@testable import IntrospectionSDK

// The check itself. The cloud classifies every route and writes the classification into each
// plane's OpenAPI document: an operation without `x-introspection` is for every client, and one
// with it lists the clients that implement it in `clients` (`[]` for none). Integration and
// excluded routes are not in the documents at all. So the documents are the only list: there are
// no exemptions here.
//
// It fails when
// 1. an operation required for the SDK (no `x-introspection`, or `clients` includes `sdk`) is not
//    called anywhere in Sources (method + path);
// 2. Sources calls a `/v1` route (method + path) that is in neither document.
// Field-level changes are not compared.

/// One OpenAPI document, read as plain JSON.
struct OpenAPIDocument {
    /// `controlplane` or `dataplane`.
    let plane: String
    let document: JSONObject
    /// Where it came from, so the report names the reference it was checked against.
    let source: String
}

struct ContractReport {
    var missing: [String] = []
    var unknown: [String] = []
    var sources: [String] = []

    var failed: Bool { !missing.isEmpty || !unknown.isEmpty }

    var summary: String { "\(missing.count) missing operations, \(unknown.count) unknown routes" }

    var text: String {
        var lines = ["API contract: \(failed ? "drift" : "clean"): \(summary)", "reference: \(sources.joined(separator: " + "))"]
        func section(_ title: String, _ items: [String]) {
            guard !items.isEmpty else { return }
            lines += ["", "\(title) (\(items.count)):"] + items.sorted().map { "  \($0)" }
        }
        section("Missing operations: required for sdk, not called in Sources", missing)
        section("Unknown routes: called in Sources, in neither document", unknown)
        return lines.joined(separator: "\n")
    }
}

enum ContractCheck {
    private static let httpMethods = ["get", "post", "put", "patch", "delete"]

    /// `GET /v1/widgets/{}`: a route with its path parameters unnamed, as call sites write it.
    private static func key(_ method: String, _ path: String) -> String {
        "\(method) \(path.replacingOccurrences(of: #"\{[^}]*\}"#, with: "{}", options: .regularExpression))"
    }

    private static func requiredForSDK(_ operation: JSONValue) -> Bool {
        guard let flags = operation["x-introspection"] else { return true }
        return flags["clients"]?.arrayValue?.contains { $0.stringValue == "sdk" } ?? false
    }

    static func run(documents: [OpenAPIDocument], sites: [CallSite]) -> ContractReport {
        var report = ContractReport(sources: documents.map(\.source))
        // Each operation by key, with its name and whether the SDK must call it.
        var operations: [String: (name: String, required: Bool)] = [:]
        for document in documents {
            for (path, item) in document.document["paths"]?.objectValue ?? [:] {
                for method in httpMethods {
                    guard let operation = item[method], !operation.isNull else { continue }
                    let key = key(method.uppercased(), path)
                    if operations[key] == nil {
                        operations[key] = ("\(document.plane) \(method.uppercased()) \(path)", requiredForSDK(operation))
                    }
                }
            }
        }
        var called: Set<String> = []
        for site in sites {
            for path in site.paths {
                let key = key(site.method, path)
                if operations[key] == nil {
                    report.unknown.append("\(site.method) \(path)  (\(site.location))")
                }
                called.insert(key)
            }
        }
        report.missing = operations.filter { $0.value.required && !called.contains($0.key) }.map(\.value.name)
        report.unknown = Array(Set(report.unknown))
        return report
    }
}
