import Foundation

@testable import IntrospectionSDK

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A published OpenAPI document, read as plain JSON.
struct OpenAPIReference {
    let document: JSONObject
    /// Where it came from, so a failure names the reference it disagreed with.
    let source: String

    /// The file named by `environmentKey` when set, otherwise the published reference at `url`.
    static func load(environmentKey: String, url: String) async throws -> OpenAPIReference {
        let data: Data
        let source: String
        if let path = ProcessInfo.processInfo.environment[environmentKey], !path.isEmpty {
            data = try Data(contentsOf: URL(fileURLWithPath: path))
            source = path
        } else {
            data = try await fetch(URL(string: url)!)
            source = url
        }
        guard case let .object(document) = try JSONCoding.decoder.decode(JSONValue.self, from: data) else {
            throw IntrospectionError(kind: .decoding, message: "\(source) is not a JSON object")
        }
        return OpenAPIReference(document: document, source: source)
    }

    private static func fetch(_ url: URL) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
                    continuation.resume(throwing: IntrospectionError(kind: .network, message: "\(url) answered \(status)"))
                } else {
                    continuation.resume(returning: data ?? Data())
                }
            }.resume()
        }
    }

    var schemas: JSONObject { document["components"]?.objectValue?["schemas"]?.objectValue ?? [:] }

    /// Follow `$ref` until a schema body is reached.
    func resolve(_ schema: JSONValue) -> JSONValue {
        var current = schema
        var hops = 0
        while let ref = current["$ref"]?.stringValue, hops < 32 {
            current = schemas[String(ref.split(separator: "/").last ?? "")] ?? .null
            hops += 1
        }
        return current
    }

    /// The property names of `components.schemas.<name>`, with `allOf` merged; nil when the schema is absent.
    func properties(_ name: String) -> Set<String>? {
        guard let schema = schemas[name] else { return nil }
        return properties(of: schema)
    }

    private func properties(of schema: JSONValue) -> Set<String> {
        let body = resolve(schema)
        var names = Set(body["properties"]?.objectValue.map { Array($0.keys) } ?? [])
        for member in body["allOf"]?.arrayValue ?? [] { names.formUnion(properties(of: member)) }
        return names
    }

    /// The query parameter names an operation declares; nil when the operation is absent.
    /// Path parameters are left out: the caller passes those positionally.
    func queryParameters(_ method: String, _ path: String) -> Set<String>? {
        guard let operation = document["paths"]?[path]?[method.lowercased()], !operation.isNull else { return nil }
        let parameters = (operation["parameters"]?.arrayValue ?? []).map(resolve)
        return Set(parameters.filter { $0["in"]?.stringValue == "query" }.compactMap { $0["name"]?.stringValue })
    }

    func hasOperation(_ method: String, _ path: String) -> Bool {
        guard let operation = document["paths"]?[path]?[method.lowercased()] else { return false }
        return !operation.isNull
    }

    /// The values of an enum schema.
    func enumValues(_ name: String) -> [String]? {
        schemas[name].map(resolve)?["enum"]?.arrayValue?.compactMap(\.stringValue)
    }

    /// A value for `components.schemas.<name>` with every declared property present.
    func sample(_ name: String) -> JSONValue? {
        schemas[name].map { sample(of: $0, key: nil, depth: 0) }
    }

    /// Timestamps are declared as plain strings in places, so a `*_at` property gets one too.
    private func sample(of schema: JSONValue, key: String?, depth: Int) -> JSONValue {
        let body = resolve(schema)
        guard depth < 8 else { return .null }
        if let options = (body["anyOf"] ?? body["oneOf"])?.arrayValue {
            let concrete = options.first { resolve($0)["type"]?.stringValue != "null" } ?? .null
            return sample(of: concrete, key: key, depth: depth + 1)
        }
        if let first = body["enum"]?.arrayValue?.first { return first }
        if let constant = body["const"] { return constant }
        if let members = body["allOf"]?.arrayValue {
            var merged: JSONObject = [:]
            for member in members {
                if case let .object(fields) = sample(of: member, key: key, depth: depth + 1) { merged.merge(fields) { $1 } }
            }
            return .object(merged)
        }
        switch body["type"]?.stringValue {
        case "string":
            switch body["format"]?.stringValue {
            case "date-time": return "2026-01-01T00:00:00Z"
            case "date": return "2026-01-01"
            case "uuid": return "0192f0a0-0000-7000-8000-000000000001"
            default: return key?.hasSuffix("_at") == true ? "2026-01-01T00:00:00Z" : "x"
            }
        case "integer": return 1
        case "number": return 1.5
        case "boolean": return true
        case "array": return .array(body["items"].map { [sample(of: $0, key: nil, depth: depth + 1)] } ?? [])
        case "object", nil:
            // A named component with no declared shape is an object the server builds by hand.
            guard let properties = body["properties"]?.objectValue else {
                return body["type"] == nil && schema["$ref"] == nil ? .null : .object([:])
            }
            return .object(
                Dictionary(uniqueKeysWithValues: properties.map { ($0.key, sample(of: $0.value, key: $0.key, depth: depth + 1)) }))
        default: return .null
        }
    }
}

/// Wire keys of an `Encodable` value, as `JSONCoding.encoder` writes them.
func wireKeys<T: Encodable>(_ value: T) throws -> Set<String> {
    guard case let .object(object) = try JSONValue.from(value) else {
        throw IntrospectionError(kind: .invalidRequest, message: "\(T.self) does not encode to a JSON object")
    }
    return Set(object.keys)
}

/// The keys a `Decodable` type asks its top-level keyed container for. A decoder
/// that claims every key is present and answers each with a placeholder walks
/// every `decode`/`decodeIfPresent`, so this reads the type's coding keys without
/// needing a value of it.
func decodedKeys<T: Decodable>(_ type: T.Type) throws -> Set<String> {
    let probe = KeyProbe()
    _ = try T(from: ProbeDecoder(probe: probe, depth: 0))
    return probe.keys
}

final class KeyProbe {
    var keys: Set<String> = []
}

private struct ProbeError: Error {}

private struct ProbeDecoder: Decoder {
    let probe: KeyProbe
    let depth: Int
    var codingPath: [any CodingKey] { [] }
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    func container<Key: CodingKey>(keyedBy _: Key.Type) throws -> KeyedDecodingContainer<Key> {
        KeyedDecodingContainer(ProbeKeyedContainer<Key>(probe: probe, depth: depth))
    }

    func unkeyedContainer() throws -> any UnkeyedDecodingContainer { ProbeUnkeyedContainer() }

    func singleValueContainer() throws -> any SingleValueDecodingContainer { ProbeSingleValueContainer(probe: probe, depth: depth) }
}

private struct ProbeKeyedContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let probe: KeyProbe
    let depth: Int
    var codingPath: [any CodingKey] { [] }
    var allKeys: [Key] { [] }

    private func note(_ key: Key) {
        if depth == 0 { probe.keys.insert(key.stringValue) }
    }

    private var nested: ProbeDecoder { ProbeDecoder(probe: probe, depth: depth + 1) }

    func contains(_ key: Key) -> Bool {
        note(key)
        return true
    }

    func decodeNil(forKey key: Key) throws -> Bool {
        note(key)
        return false
    }

    func decode(_: Bool.Type, forKey key: Key) throws -> Bool { note(key); return true }
    func decode(_: String.Type, forKey key: Key) throws -> String { note(key); return "x" }
    func decode(_: Double.Type, forKey key: Key) throws -> Double { note(key); return 1 }
    func decode(_: Float.Type, forKey key: Key) throws -> Float { note(key); return 1 }
    func decode(_: Int.Type, forKey key: Key) throws -> Int { note(key); return 1 }
    func decode(_: Int8.Type, forKey key: Key) throws -> Int8 { note(key); return 1 }
    func decode(_: Int16.Type, forKey key: Key) throws -> Int16 { note(key); return 1 }
    func decode(_: Int32.Type, forKey key: Key) throws -> Int32 { note(key); return 1 }
    func decode(_: Int64.Type, forKey key: Key) throws -> Int64 { note(key); return 1 }
    func decode(_: UInt.Type, forKey key: Key) throws -> UInt { note(key); return 1 }
    func decode(_: UInt8.Type, forKey key: Key) throws -> UInt8 { note(key); return 1 }
    func decode(_: UInt16.Type, forKey key: Key) throws -> UInt16 { note(key); return 1 }
    func decode(_: UInt32.Type, forKey key: Key) throws -> UInt32 { note(key); return 1 }
    func decode(_: UInt64.Type, forKey key: Key) throws -> UInt64 { note(key); return 1 }

    func decode<T: Decodable>(_: T.Type, forKey key: Key) throws -> T {
        note(key)
        return try T(from: nested)
    }

    func nestedContainer<NestedKey: CodingKey>(keyedBy _: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> {
        note(key)
        return KeyedDecodingContainer(ProbeKeyedContainer<NestedKey>(probe: probe, depth: depth + 1))
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
        note(key)
        return ProbeUnkeyedContainer()
    }

    func superDecoder() throws -> any Decoder { nested }

    func superDecoder(forKey key: Key) throws -> any Decoder {
        note(key)
        return nested
    }
}

/// Always empty, so arrays decode without asking for elements.
private struct ProbeUnkeyedContainer: UnkeyedDecodingContainer {
    var codingPath: [any CodingKey] { [] }
    var count: Int? { 0 }
    var isAtEnd: Bool { true }
    var currentIndex: Int { 0 }

    mutating func decodeNil() throws -> Bool { true }
    mutating func decode(_: Bool.Type) throws -> Bool { throw ProbeError() }
    mutating func decode(_: String.Type) throws -> String { throw ProbeError() }
    mutating func decode(_: Double.Type) throws -> Double { throw ProbeError() }
    mutating func decode(_: Float.Type) throws -> Float { throw ProbeError() }
    mutating func decode(_: Int.Type) throws -> Int { throw ProbeError() }
    mutating func decode(_: Int8.Type) throws -> Int8 { throw ProbeError() }
    mutating func decode(_: Int16.Type) throws -> Int16 { throw ProbeError() }
    mutating func decode(_: Int32.Type) throws -> Int32 { throw ProbeError() }
    mutating func decode(_: Int64.Type) throws -> Int64 { throw ProbeError() }
    mutating func decode(_: UInt.Type) throws -> UInt { throw ProbeError() }
    mutating func decode(_: UInt8.Type) throws -> UInt8 { throw ProbeError() }
    mutating func decode(_: UInt16.Type) throws -> UInt16 { throw ProbeError() }
    mutating func decode(_: UInt32.Type) throws -> UInt32 { throw ProbeError() }
    mutating func decode(_: UInt64.Type) throws -> UInt64 { throw ProbeError() }
    mutating func decode<T: Decodable>(_: T.Type) throws -> T { throw ProbeError() }

    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy _: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> {
        throw ProbeError()
    }

    mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer { throw ProbeError() }
    mutating func superDecoder() throws -> any Decoder { throw ProbeError() }
}

private struct ProbeSingleValueContainer: SingleValueDecodingContainer {
    let probe: KeyProbe
    let depth: Int
    var codingPath: [any CodingKey] { [] }

    func decodeNil() -> Bool { false }
    func decode(_: Bool.Type) throws -> Bool { true }
    func decode(_: String.Type) throws -> String { "x" }
    func decode(_: Double.Type) throws -> Double { 1 }
    func decode(_: Float.Type) throws -> Float { 1 }
    func decode(_: Int.Type) throws -> Int { 1 }
    func decode(_: Int8.Type) throws -> Int8 { 1 }
    func decode(_: Int16.Type) throws -> Int16 { 1 }
    func decode(_: Int32.Type) throws -> Int32 { 1 }
    func decode(_: Int64.Type) throws -> Int64 { 1 }
    func decode(_: UInt.Type) throws -> UInt { 1 }
    func decode(_: UInt8.Type) throws -> UInt8 { 1 }
    func decode(_: UInt16.Type) throws -> UInt16 { 1 }
    func decode(_: UInt32.Type) throws -> UInt32 { 1 }
    func decode(_: UInt64.Type) throws -> UInt64 { 1 }

    func decode<T: Decodable>(_: T.Type) throws -> T {
        try T(from: ProbeDecoder(probe: probe, depth: depth + 1))
    }
}
