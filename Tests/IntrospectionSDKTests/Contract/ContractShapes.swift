import Foundation

@testable import IntrospectionSDK

// The wire shape both sides are reduced to before they are compared: field names, required vs
// optional, and basic JSON types, nested. Nullability is not part of it: the reference writes every
// optional field as `anyOf: [T, null]`, so comparing it would flag nearly every field.

indirect enum Shape: Equatable, Sendable {
    case string
    case integer
    case number
    case boolean
    /// Any JSON value: `JSONValue` on the SDK side, a schema without a type in the reference.
    case any
    case array(Shape)
    /// An object without declared fields: `[String: T]`, `JSONObject`, or `additionalProperties`.
    case map(Shape)
    case object(name: String, fields: [String: ShapeField])
    /// SDK side only: the check cannot say what goes on the wire here, and why.
    case untyped(String)
    /// A type already being expanded further up, so the comparison stops here.
    case recursive(String)

    var basic: String {
        switch self {
        case .string: return "string"
        case .integer: return "integer"
        case .number: return "number"
        case .boolean: return "boolean"
        case .any, .untyped, .recursive: return "any"
        case .array: return "array"
        case .map, .object: return "object"
        }
    }
}

struct ShapeField: Equatable, Sendable {
    var shape: Shape
    var required: Bool
}

extension Shape {
    /// Alternatives of one value (a `oneOf`, an enum with associated values) as one object: every field
    /// of any alternative, required only when every alternative requires it.
    static func merged(_ options: [Shape]) -> Shape {
        let objects = options.compactMap { option -> [String: ShapeField]? in
            if case let .object(_, fields) = option { return fields }
            return nil
        }
        guard objects.count == options.count, !objects.isEmpty else {
            let basics = Set(options.map(\.basic))
            return basics.count == 1 ? options[0] : .any
        }
        var fields: [String: ShapeField] = [:]
        for object in objects {
            for (name, field) in object {
                if var existing = fields[name] {
                    existing.required = existing.required && field.required
                    fields[name] = existing
                } else {
                    fields[name] = field
                }
            }
        }
        for name in fields.keys where objects.contains(where: { $0[name] == nil }) { fields[name]?.required = false }
        return .object(name: "", fields: fields)
    }
}

// MARK: - The reference

/// One OpenAPI document, read as plain JSON.
struct OpenAPIDocument {
    /// `controlplane` or `dataplane`.
    let plane: String
    let document: JSONObject
    /// Where it came from, so a finding names the reference it disagreed with.
    let source: String

    var schemas: JSONObject { document["components"]?.objectValue?["schemas"]?.objectValue ?? [:] }

    func resolve(_ schema: JSONValue) -> (JSONValue, String?) {
        var current = schema
        var name: String?
        var hops = 0
        while let ref = current["$ref"]?.stringValue, hops < 32 {
            name = String(ref.split(separator: "/").last ?? "")
            current = schemas[name ?? ""] ?? .null
            hops += 1
        }
        return (current, name)
    }

    func shape(_ schema: JSONValue?, stack: [String] = []) -> Shape {
        guard let schema else { return .any }
        let (body, name) = resolve(schema)
        if let name, stack.contains(name) { return .recursive(name) }
        let stack = name.map { stack + [$0] } ?? stack
        if let options = (body["anyOf"] ?? body["oneOf"])?.arrayValue {
            let concrete = options.filter { resolve($0).0["type"]?.stringValue != "null" }
            if concrete.count == 1 { return shape(concrete[0], stack: stack) }
            return .merged(concrete.map { shape($0, stack: stack) })
        }
        if let members = body["allOf"]?.arrayValue {
            return allOf(members.map { shape($0, stack: stack) }, name: name)
        }
        return typed(body, name: name, stack: stack)
    }

    private func allOf(_ members: [Shape], name: String?) -> Shape {
        var fields: [String: ShapeField] = [:]
        for case let .object(_, memberFields) in members { fields.merge(memberFields) { lhs, rhs in lhs.required ? lhs : rhs } }
        if fields.isEmpty, let first = members.first { return first }
        return .object(name: name ?? "", fields: fields)
    }

    private func typed(_ body: JSONValue, name: String?, stack: [String]) -> Shape {
        var type = body["type"]?.stringValue
        if type == nil, let types = body["type"]?.arrayValue?.compactMap(\.stringValue) {
            type = types.first { $0 != "null" }
        }
        if type == nil, body["properties"] != nil { type = "object" }
        if type == nil, let values = body["enum"]?.arrayValue ?? body["const"].map({ [$0] }) {
            type = values.first.map(Self.jsonType)
        }
        switch type {
        case "string": return .string
        case "integer": return .integer
        case "number": return .number
        case "boolean": return .boolean
        case "array": return .array(body["items"].map { shape($0, stack: stack) } ?? .any)
        case "object":
            guard let properties = body["properties"]?.objectValue, !properties.isEmpty else {
                if case .object = body["additionalProperties"] { return .map(shape(body["additionalProperties"], stack: stack)) }
                return .map(.any)
            }
            let required = Set(body["required"]?.arrayValue?.compactMap(\.stringValue) ?? [])
            var fields: [String: ShapeField] = [:]
            for (key, value) in properties { fields[key] = ShapeField(shape: shape(value, stack: stack), required: required.contains(key)) }
            return .object(name: name ?? "", fields: fields)
        default: return .any
        }
    }

    private static func jsonType(_ value: JSONValue) -> String {
        switch value {
        case .string: return "string"
        case .bool: return "boolean"
        case let .number(number): return number == number.rounded() ? "integer" : "number"
        default: return "any"
        }
    }
}
