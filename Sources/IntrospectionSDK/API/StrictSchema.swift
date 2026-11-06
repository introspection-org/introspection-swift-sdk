import Foundation

/// Opt-in strict decoding: a response field this SDK does not model fails the decode.
///
/// By default a field the models do not name is ignored, so a server that adds one never breaks a client.
/// With strict decoding on (``HTTPClient/Options/strictSchema``, which `INTROSPECTION_STRICT_SCHEMA=1`
/// turns on) the same response throws an ``IntrospectionError`` of kind `.decoding` and code
/// `schema_drift`, naming the route and every unmodelled field by its JSON path:
///
///     /v1/tags: response fields this SDK does not model: $.records[0].color
///
/// The SDK's end-to-end walk decodes strictly, so a field the API adds shows up there before a release
/// ships without it. Open-ended values (`JSONObject`, `JSONValue`, a type that keeps unknown keys in
/// `extra`) read every key, so they never report one.
public enum StrictSchema {
    /// The environment variable that turns strict decoding on by default (`1`, `true`, `yes` or `on`).
    public static let environmentVariable = "INTROSPECTION_STRICT_SCHEMA"

    /// Whether `INTROSPECTION_STRICT_SCHEMA` asks for strict decoding.
    public static var environmentEnabled: Bool {
        let value = ProcessInfo.processInfo.environment[environmentVariable] ?? ""
        return ["1", "true", "yes", "on"].contains(value.trimmingCharacters(in: .whitespaces).lowercased())
    }

    /// The error code of a strict-decoding failure.
    public static let errorCode = "schema_drift"

    /// The JSON paths of the keys in `body` that decoding `T` does not read; empty for a non-JSON body.
    static func unmodelled<T: Decodable>(_: T.Type, in body: Data) throws -> [String] {
        guard !body.isEmpty, let raw = try? JSONCoding.decoder.decode(JSONValue.self, from: body) else { return [] }
        let tracker = KeyTracker()
        _ = try TrackingDecoder(value: raw, path: "$", codingPath: [], tracker: tracker).decodeValue(T.self)
        var found: [String] = []
        tracker.collect(raw, at: "$", into: &found)
        return found
    }

    /// Throw a `schema_drift` error when `response` holds a field `T` does not model.
    static func check<T: Decodable>(_: T.Type, response: HTTPResponse, route: String) throws {
        let fields: [String]
        do {
            fields = try unmodelled(T.self, in: response.body)
        } catch {
            throw IntrospectionError(
                kind: .decoding, message: "\(route): strict decoding of \(T.self) failed: \(error)",
                status: response.status, code: errorCode, requestId: response.headers["x-request-id"], underlying: error)
        }
        guard !fields.isEmpty else { return }
        var error = IntrospectionError(
            kind: .decoding, message: "\(route): response fields this SDK does not model: \(fields.joined(separator: ", "))",
            status: response.status, code: errorCode, requestId: response.headers["x-request-id"])
        error.unmodelledFields = fields
        throw error
    }
}

/// A model whose wire object is open by design: strict decoding reports none of its keys.
protocol OpenSchema {}

/// Which keys each visited JSON object had read, by JSON path.
private final class KeyTracker {
    var read: [String: Set<String>] = [:]
    var open: Set<String> = []

    func visit(_ path: String) {
        if read[path] == nil { read[path] = [] }
    }

    func mark(_ key: String, at path: String) {
        read[path, default: []].insert(key)
    }

    /// Every unread key of a visited object, in document order (keys sorted, items by index).
    func collect(_ value: JSONValue, at path: String, into found: inout [String]) {
        guard !open.contains(path) else { return }
        switch value {
        case let .object(object):
            let readKeys = read[path]
            for key in object.keys.sorted() {
                let child = "\(path).\(key)"
                if let readKeys, !readKeys.contains(key) {
                    found.append(child)
                } else if let item = object[key] {
                    collect(item, at: child, into: &found)
                }
            }
        case let .array(items):
            for (index, item) in items.enumerated() { collect(item, at: "\(path)[\(index)]", into: &found) }
        default: return
        }
    }
}

private struct PathKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init(stringValue: String) { self.stringValue = stringValue }
    init(intValue: Int) {
        stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

/// A `Decoder` over a parsed response that records every object key a `Decodable` reads. Its decoded
/// values are thrown away, so it decodes only as faithfully as a model's own branching needs.
private struct TrackingDecoder: Decoder {
    let value: JSONValue
    let path: String
    let codingPath: [any CodingKey]
    let tracker: KeyTracker
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    func child(_ value: JSONValue, path: String, key: any CodingKey) -> TrackingDecoder {
        TrackingDecoder(value: value, path: path, codingPath: codingPath + [key], tracker: tracker)
    }

    func mismatch(_ type: Any.Type) -> DecodingError {
        .typeMismatch(type, .init(codingPath: codingPath, debugDescription: "Expected \(type) at \(path), found \(value)"))
    }

    func container<Key: CodingKey>(keyedBy _: Key.Type) throws -> KeyedDecodingContainer<Key> {
        guard case let .object(object) = value else { throw mismatch([String: Any].self) }
        tracker.visit(path)
        return KeyedDecodingContainer(TrackingKeyedContainer<Key>(decoder: self, object: object))
    }

    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        guard case let .array(items) = value else { throw mismatch([Any].self) }
        return TrackingUnkeyedContainer(decoder: self, items: items)
    }

    func singleValueContainer() throws -> any SingleValueDecodingContainer { TrackingSingleValueContainer(decoder: self) }

    func decodeValue<T: Decodable>(_ type: T.Type) throws -> T {
        if T.self is any OpenSchema.Type { tracker.open.insert(path) }
        if let primitive = try primitive(T.self) { return primitive }
        return try T(from: self)
    }

    private func primitive<T>(_ type: T.Type) throws -> T? {
        switch value {
        case let .string(text):
            if T.self == String.self { return text as? T }
            if T.self == Date.self { return try require(ISO8601.parse(text), as: T.self) }
            if T.self == URL.self { return try require(URL(string: text), as: T.self) }
            if T.self == Data.self { return try require(Data(base64Encoded: text), as: T.self) }
        case let .number(number):
            if T.self == Date.self { return Date(timeIntervalSince1970: number) as? T }
            if T.self == Decimal.self { return Decimal(number) as? T }
            if let integer = T.self as? any BinaryInteger.Type { return try require(integer.init(exactly: number), as: T.self) }
            if let floating = T.self as? any BinaryFloatingPoint.Type { return floating.init(number) as? T }
        case let .bool(flag):
            if T.self == Bool.self { return flag as? T }
        default: break
        }
        let primitives: [Any.Type] = [String.self, Bool.self, Date.self, URL.self, Data.self]
        if primitives.contains(where: { $0 == T.self }) || T.self is any Numeric.Type { throw mismatch(T.self) }
        return nil
    }

    private func require<T>(_ decoded: Any?, as _: T.Type) throws -> T {
        guard let typed = decoded as? T else { throw mismatch(T.self) }
        return typed
    }
}

private struct TrackingKeyedContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let decoder: TrackingDecoder
    let object: [String: JSONValue]
    var codingPath: [any CodingKey] { decoder.codingPath }
    var allKeys: [Key] { object.keys.compactMap { Key(stringValue: $0) } }

    func contains(_ key: Key) -> Bool {
        decoder.tracker.mark(key.stringValue, at: decoder.path)
        return object[key.stringValue] != nil
    }

    private func child(_ key: any CodingKey) throws -> TrackingDecoder {
        decoder.tracker.mark(key.stringValue, at: decoder.path)
        guard let value = object[key.stringValue] else {
            throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "No value at \(decoder.path)"))
        }
        return decoder.child(value, path: "\(decoder.path).\(key.stringValue)", key: key)
    }

    func decodeNil(forKey key: Key) throws -> Bool { try child(key).value.isNull }

    func decode<T: Decodable>(_: T.Type, forKey key: Key) throws -> T { try child(key).decodeValue(T.self) }

    func nestedContainer<Nested: CodingKey>(keyedBy type: Nested.Type, forKey key: Key) throws -> KeyedDecodingContainer<Nested> {
        try child(key).container(keyedBy: type)
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer { try child(key).unkeyedContainer() }

    func superDecoder() throws -> any Decoder { try child(PathKey(stringValue: "super")) }

    func superDecoder(forKey key: Key) throws -> any Decoder { try child(key) }
}

private struct TrackingUnkeyedContainer: UnkeyedDecodingContainer {
    let decoder: TrackingDecoder
    let items: [JSONValue]
    var currentIndex = 0
    var codingPath: [any CodingKey] { decoder.codingPath }
    var count: Int? { items.count }
    var isAtEnd: Bool { currentIndex >= items.count }

    /// Read the next item; as in `JSONDecoder`, a failed read does not advance past it.
    private mutating func next<T>(_ read: (TrackingDecoder) throws -> T) throws -> T {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(Any.self, .init(codingPath: codingPath, debugDescription: "End of \(decoder.path)"))
        }
        let item = decoder.child(items[currentIndex], path: "\(decoder.path)[\(currentIndex)]", key: PathKey(intValue: currentIndex))
        let value = try read(item)
        currentIndex += 1
        return value
    }

    mutating func decodeNil() throws -> Bool {
        guard !isAtEnd, items[currentIndex].isNull else { return false }
        currentIndex += 1
        return true
    }

    mutating func decode<T: Decodable>(_: T.Type) throws -> T { try next { try $0.decodeValue(T.self) } }

    mutating func nestedContainer<Nested: CodingKey>(keyedBy type: Nested.Type) throws -> KeyedDecodingContainer<Nested> {
        try next { try $0.container(keyedBy: type) }
    }

    mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer { try next { try $0.unkeyedContainer() } }

    mutating func superDecoder() throws -> any Decoder { try next { $0 } }
}

private struct TrackingSingleValueContainer: SingleValueDecodingContainer {
    let decoder: TrackingDecoder
    var codingPath: [any CodingKey] { decoder.codingPath }

    func decodeNil() -> Bool { decoder.value.isNull }

    func decode<T: Decodable>(_: T.Type) throws -> T { try decoder.decodeValue(T.self) }
}
