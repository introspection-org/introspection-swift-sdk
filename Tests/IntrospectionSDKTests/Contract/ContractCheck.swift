import Foundation

@testable import IntrospectionSDK

// The check itself. The cloud classifies every route and writes the classification into each
// OpenAPI document: an operation's `x-introspection.clients` names the clients expected to call it,
// and a parameter flagged `clients: []` is one no client is expected to send. Integration and
// excluded routes are not in the documents at all. So the documents are the only list: there are no
// exemptions here.
//
// It fails when
// 1. an operation whose clients include `sdk` is not called anywhere in Sources;
// 2. Sources calls a `/v1` route that is in neither document;
// 3. a called operation's request body, query parameters or response differ from Sources in field
//    names, required vs optional, or basic type, `$ref`s followed into nested schemas.
// A call site whose types the check cannot read is a warning naming the operation, the part and the
// call site; it does not fail the run.
//
// Required has one direction: required by the reference and optional in the SDK. A field the SDK
// always sends or always expects although the reference makes it optional is fine (the reference
// marks any field with a default optional, and the API still serializes it).

struct ContractFinding: Hashable, Comparable {
    var operation: String
    var detail: String
    var location: String

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.operation, lhs.detail, lhs.location) < (rhs.operation, rhs.detail, rhs.location)
    }
}

struct ContractReport {
    var missing: [String] = []
    var unknown: [String] = []
    var differences: [ContractFinding] = []
    var warnings: [ContractFinding] = []
    var notes: [String] = []
    var sources: [String] = []

    var failed: Bool { !missing.isEmpty || !unknown.isEmpty || !differences.isEmpty }

    var summary: String {
        "\(missing.count) missing operations, \(unknown.count) unknown routes, \(differences.count) field differences, "
            + "\(warnings.count) warnings"
    }

    var text: String {
        var lines = ["API contract: \(failed ? "drift" : "clean"): \(summary)", "reference: \(sources.joined(separator: " + "))"]
        func section(_ title: String, _ items: [String]) {
            guard !items.isEmpty else { return }
            lines += ["", "\(title) (\(items.count)):"] + items.map { "  \($0)" }
        }
        func grouped(_ title: String, _ findings: [ContractFinding]) {
            guard !findings.isEmpty else { return }
            lines += ["", "\(title) (\(findings.count)):"]
            var current = ""
            for finding in findings.sorted() {
                if finding.operation != current {
                    current = finding.operation
                    lines.append("  \(current)")
                }
                lines.append("    \(finding.detail)  (\(finding.location))")
            }
        }
        section("Missing operations: flagged for sdk, not called in Sources", missing.sorted())
        section("Unknown routes: called in Sources, in neither document", unknown.sorted())
        grouped("Field differences", differences)
        grouped("Warning: SDK has no concrete types", warnings)
        section("Notes", notes.sorted())
        return lines.joined(separator: "\n")
    }
}

struct ReferenceOperation {
    let document: OpenAPIDocument
    let method: String
    let path: String
    let operation: JSONValue
    let parameters: [JSONValue]

    var name: String { "\(document.plane) \(method) \(path)" }
    var clients: [String] { operation["x-introspection"]?["clients"]?.arrayValue?.compactMap(\.stringValue) ?? [] }
    var key: String { "\(method) \(Self.template(path))" }

    static func template(_ path: String) -> String {
        path.replacingOccurrences(of: #"\{[^}]*\}"#, with: "{}", options: .regularExpression)
    }
}

struct ContractCheck {
    let documents: [OpenAPIDocument]
    let sites: [CallSite]
    var report = ContractReport()

    init(documents: [OpenAPIDocument], sites: [CallSite]) {
        self.documents = documents
        self.sites = sites
        report.sources = documents.map(\.source)
    }

    static let httpMethods = ["get", "post", "put", "patch", "delete"]

    var operations: [ReferenceOperation] {
        documents.flatMap { document -> [ReferenceOperation] in
            let paths = document.document["paths"]?.objectValue ?? [:]
            return paths.sorted { $0.key < $1.key }.flatMap { path, item -> [ReferenceOperation] in
                let shared = item["parameters"]?.arrayValue ?? []
                return Self.httpMethods.compactMap { method in
                    guard let operation = item[method], !operation.isNull else { return nil }
                    let parameters = (shared + (operation["parameters"]?.arrayValue ?? [])).map { document.resolve($0).0 }
                    return ReferenceOperation(
                        document: document, method: method.uppercased(), path: path, operation: operation, parameters: parameters)
                }
            }
        }
    }

    mutating func run() -> ContractReport {
        let operations = self.operations
        let byKey = Dictionary(operations.map { ($0.key, $0) }, uniquingKeysWith: { lhs, _ in lhs })
        var called: Set<String> = []
        for site in sites {
            for path in site.paths {
                guard let operation = byKey["\(site.method) \(ReferenceOperation.template(path))"] else {
                    report.unknown.append("\(site.method) \(path)  (\(site.location))")
                    continue
                }
                if called.insert(operation.name).inserted, !operation.clients.contains("sdk") {
                    report.notes.append("\(operation.name) is called (\(site.location)) but its clients are \(operation.clients)")
                }
                compare(site, operation)
            }
        }
        for operation in operations where operation.clients.contains("sdk") && !called.contains(operation.name) {
            report.missing.append(operation.name)
        }
        report.unknown = Array(Set(report.unknown))
        report.differences = Array(Set(report.differences))
        report.warnings = Array(Set(report.warnings))
        return report
    }

    // MARK: Parts

    private mutating func compare(_ site: CallSite, _ operation: ReferenceOperation) {
        compareBody(site, operation)
        compareQuery(site, operation)
        compareResponse(site, operation)
    }

    private mutating func difference(_ operation: ReferenceOperation, _ site: CallSite, _ detail: String) {
        report.differences.append(ContractFinding(operation: operation.name, detail: detail, location: site.location))
    }

    private mutating func warning(_ operation: ReferenceOperation, _ site: CallSite, _ detail: String) {
        report.warnings.append(ContractFinding(operation: operation.name, detail: detail, location: site.location))
    }

    private mutating func compareBody(_ site: CallSite, _ operation: ReferenceOperation) {
        let requestBody = operation.operation["requestBody"].map { operation.document.resolve($0).0 }
        let content = requestBody?["content"]?.objectValue ?? [:]
        let required = requestBody?["required"]?.boolValue ?? false
        let media = content.keys.sorted().joined(separator: ", ")
        switch site.body {
        case .none:
            if required { difference(operation, site, "body: the API requires a body (\(media)) this call does not send") }
        case let .unresolved(reason):
            warning(operation, site, "body: \(reason)")
        case .form, .multipart, .raw:
            let sent = site.body.mediaType
            if content.isEmpty {
                difference(operation, site, "body: sent as \(sent), the API declares no body")
            } else if sent != "*", content[sent] == nil {
                difference(operation, site, "body: sent as \(sent), the API takes \(media)")
            }
        case let .json(shape):
            guard let schema = content["application/json"]?["schema"] else {
                let declared = content.isEmpty ? "declares no body" : "takes \(media)"
                difference(operation, site, "body: sent as application/json, the API \(declared)")
                return
            }
            var comparison = ShapeComparison(direction: .encode)
            comparison.compare(shape, operation.document.shape(schema), path: "body")
            for detail in comparison.differences { difference(operation, site, detail) }
            for detail in comparison.warnings { warning(operation, site, detail) }
        }
    }

    private mutating func compareQuery(_ site: CallSite, _ operation: ReferenceOperation) {
        var reference: [String: ShapeField] = [:]
        for parameter in operation.parameters where parameter["in"]?.stringValue == "query" {
            guard let name = parameter["name"]?.stringValue else { continue }
            if let clients = parameter["x-introspection"]?["clients"]?.arrayValue, !clients.contains("sdk") { continue }
            reference[name] = ShapeField(
                shape: operation.document.shape(parameter["schema"]), required: parameter["required"]?.boolValue ?? false)
        }
        for gap in site.queryGaps { warning(operation, site, "query: \(gap)") }
        for (name, field) in site.query.sorted(by: { $0.key < $1.key }) {
            guard let expected = reference[name] else {
                difference(operation, site, "query.\(name): sent here, not a query parameter of the API")
                continue
            }
            if expected.required && field.optional {
                difference(operation, site, "query.\(name): required by the API, optional here")
            }
            guard let shape = field.shape else {
                warning(operation, site, "query.\(name): the value's type is not declared at the call site")
                continue
            }
            if case let .untyped(reason) = shape {
                warning(operation, site, "query.\(name): \(reason)")
                continue
            }
            if !Self.queryValue(shape, matches: expected.shape) {
                difference(operation, site, "query.\(name): type: SDK \(shape.basic), reference \(expected.shape.basic)")
            }
        }
        guard site.queryGaps.isEmpty else { return }
        for name in reference.keys.sorted() where site.query[name] == nil {
            let required = reference[name]?.required == true
            difference(operation, site, "query.\(name): \(required ? "required" : "accepted") by the API, not sent here")
        }
    }

    /// A query string repeats a key for a list, so one value is a list of one.
    private static func queryValue(_ sdk: Shape, matches reference: Shape) -> Bool {
        if case .any = reference { return true }
        if case let .array(item) = reference, case .array = sdk { return queryValue(sdk.element ?? .any, matches: item) }
        if case let .array(item) = reference { return queryValue(sdk, matches: item) }
        if sdk.basic == reference.basic { return true }
        return sdk.basic == "integer" && reference.basic == "number"
    }

    private mutating func compareResponse(_ site: CallSite, _ operation: ReferenceOperation) {
        let responses = operation.operation["responses"]?.objectValue ?? [:]
        let success = responses.keys.filter { $0.hasPrefix("2") }.sorted()
        let content = success.lazy.compactMap { responses[$0].map { operation.document.resolve($0).0 }?["content"]?.objectValue }.first
        // The schema of the media type the call asks for: exact, else the same type without parameters.
        let media =
            site.accept.map { accept in content?[accept] == nil ? String(accept.prefix { $0 != ";" }) : accept } ?? "application/json"
        let schema = content?[media]?["schema"]
        switch site.response {
        case .none, .nonJSON:
            return
        case let .unresolved(reason):
            warning(operation, site, "response: \(reason)")
        case .json where site.accept == "":
            warning(operation, site, "response: the Accept header is not a literal, so the media type to compare is unknown")
        case let .json(shape):
            guard let schema else {
                let returned = content.map { $0.keys.sorted().joined(separator: ", ") } ?? "no body"
                difference(operation, site, "response: decoded as \(media), the API returns \(returned)")
                return
            }
            var comparison = ShapeComparison(direction: .decode)
            comparison.compare(shape, operation.document.shape(schema), path: "response")
            for detail in comparison.differences { difference(operation, site, detail) }
            for detail in comparison.warnings { warning(operation, site, detail) }
        }
    }
}

extension BodyPart {
    var mediaType: String {
        switch self {
        case .form: return "application/x-www-form-urlencoded"
        case .multipart: return "multipart/form-data"
        case .json: return "application/json"
        case .raw, .none, .unresolved: return "*"
        }
    }
}

extension Shape {
    var element: Shape? {
        if case let .array(item) = self { return item }
        return nil
    }
}

/// Field-by-field comparison of what the SDK sends or reads with what the reference declares.
struct ShapeComparison {
    let direction: CodingDirection
    var differences: [String] = []
    var warnings: [String] = []

    private var extraMeans: String { direction == .encode ? "sent here, not declared by the API" : "read here, not returned by the API" }
    private var missingMeans: String { direction == .encode ? "accepted by the API, not sent here" : "returned by the API, not read here" }

    mutating func compare(_ sdk: Shape, _ reference: Shape, path: String) {
        switch (sdk, reference) {
        case (_, .any), (_, .recursive), (.recursive, _):
            return
        case let (.untyped(reason), _):
            warnings.append("\(path): \(reason)")
        case (.any, .object), (.any, .array):
            warnings.append("\(path): JSONValue here, the reference declares \(reference.basic == "array" ? "an array" : "fields")")
        case (.any, _):
            return
        case (.map, .object):
            warnings.append("\(path): a map here, the reference names fields")
        case let (.map(value), .map(expected)):
            compare(value, expected, path: "\(path).*")
        case (.object, .map):
            return
        case let (.array(item), .array(expected)):
            compare(item, expected, path: "\(path)[]")
        case let (.object(_, fields), .object(_, expected)):
            compareFields(fields, expected, path: path)
        default:
            if !Self.compatible(sdk, reference, direction) {
                differences.append("\(path): type: SDK \(sdk.basic), reference \(reference.basic)")
            }
        }
    }

    private static func compatible(_ sdk: Shape, _ reference: Shape, _ direction: CodingDirection) -> Bool {
        if sdk.basic == reference.basic { return true }
        // An integer is a number, so only an integer may stand where a number is expected:
        // an SDK integer sent as a number, or an API integer read into an SDK number.
        if sdk.basic == "number", reference.basic == "integer" { return direction == .decode }
        return sdk.basic == "integer" && reference.basic == "number" && direction == .encode
    }

    private mutating func compareFields(_ fields: [String: ShapeField], _ expected: [String: ShapeField], path: String) {
        for name in Set(fields.keys).union(expected.keys).sorted() {
            let fieldPath = "\(path).\(name)"
            switch (fields[name], expected[name]) {
            case (.some, .none):
                differences.append("\(fieldPath): \(extraMeans)")
            case (.none, .some):
                differences.append("\(fieldPath): \(missingMeans)")
            case let (.some(field), .some(reference)):
                if reference.required && !field.required {
                    differences.append("\(fieldPath): required by the reference, optional here")
                }
                compare(field.shape, reference.shape, path: fieldPath)
            case (.none, .none):
                continue
            }
        }
    }
}
