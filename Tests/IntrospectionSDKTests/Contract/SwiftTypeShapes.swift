import Foundation

// What a Swift type in Sources puts on or reads from the wire, as a `Shape`. Synthesized `Codable`
// is read from the stored properties and `CodingKeys`; a hand-written `init(from:)` or
// `encode(to:)` is read from its `decode`/`encode(…, forKey:)` calls. What neither covers is
// `.untyped`, which the check reports as a warning rather than guessing.

/// A parsed Swift type expression.
indirect enum TypeExpression: Equatable {
    case named(String, [TypeExpression])
    case array(TypeExpression)
    case dictionary(TypeExpression, TypeExpression)
    case optional(TypeExpression)
    case unknown(String)

    static func parse(_ text: String) -> TypeExpression {
        let tokens = SwiftTokenizer.tokenize(text)
        var index = 0
        let parsed = parse(tokens, &index)
        return index == tokens.count ? parsed : .unknown(text)
    }

    private static func parse(_ tokens: [SwiftToken], _ index: inout Int) -> TypeExpression {
        guard index < tokens.count else { return .unknown("") }
        var result: TypeExpression
        if tokens[index].isIdentifier("any") || tokens[index].isIdentifier("some") { index += 1 }
        if tokens[index].isPunctuation("[") {
            index += 1
            let key = parse(tokens, &index)
            if index < tokens.count, tokens[index].isPunctuation(":") {
                index += 1
                result = .dictionary(key, parse(tokens, &index))
            } else {
                result = .array(key)
            }
            index += 1
        } else if tokens[index].kind == .identifier {
            var name = tokens[index].text
            index += 1
            var arguments: [TypeExpression] = []
            while index < tokens.count {
                if tokens[index].isPunctuation("<") {
                    index += 1
                    while index < tokens.count, !tokens[index].isPunctuation(">") {
                        arguments.append(parse(tokens, &index))
                        if index < tokens.count, tokens[index].isPunctuation(",") { index += 1 }
                    }
                    index += 1
                } else if tokens[index].isPunctuation("."), index + 1 < tokens.count, tokens[index + 1].kind == .identifier {
                    name += "." + tokens[index + 1].text
                    index += 2
                } else {
                    break
                }
            }
            result = name == "Optional" && arguments.count == 1 ? .optional(arguments[0]) : .named(name, arguments)
        } else {
            let start = index
            index = tokens.count
            return .unknown(tokens.text(start..<tokens.count))
        }
        while index < tokens.count,
            tokens[index].isPunctuation("?") || tokens[index].isPunctuation("??") || tokens[index].isPunctuation("!")
        {
            result = .optional(result)
            index += 1
        }
        return result
    }

    var unwrapped: TypeExpression {
        if case let .optional(inner) = self { return inner.unwrapped }
        return self
    }

    var isOptional: Bool {
        if case .optional = self { return true }
        return false
    }
}

enum CodingDirection {
    case encode
    case decode
}

/// Every type, function and typealias declared in Sources.
struct SwiftTypeIndex {
    let files: [SwiftFile]
    private var types: [String: [SwiftType]] = [:]
    private var functions: [String: [(file: Int, function: SwiftFunction)]] = [:]
    private var aliases: [String: String] = [:]

    init(files: [SwiftFile]) {
        self.files = files
        for (fileIndex, file) in files.enumerated() {
            for type in file.types { types[type.name, default: []].append(type) }
            for function in file.functions { functions[function.owner ?? "", default: []].append((fileIndex, function)) }
            aliases.merge(file.typealiases) { lhs, _ in lhs }
        }
    }

    /// The type `name` refers to from inside `context` (a qualified type name), nearest scope first.
    func type(_ name: String, from context: String? = nil) -> SwiftType? {
        let simple = String(name.split(separator: ".").last ?? Substring(name))
        guard let candidates = types[simple] else { return nil }
        if name.contains(".") { return candidates.first { $0.qualified.hasSuffix(name) } ?? candidates.first }
        var scope = context
        while let current = scope {
            if let match = candidates.first(where: { $0.qualified == "\(current).\(name)" }) { return match }
            scope = current.contains(".") ? String(current[..<current.lastIndex(of: ".")!]) : nil
        }
        return candidates.first { !$0.qualified.contains(".") } ?? candidates.first
    }

    /// Functions and computed properties of a type, extensions included.
    func members(of type: SwiftType) -> [(file: Int, function: SwiftFunction)] {
        functions[type.qualified] ?? []
    }

    /// Functions named `name` owned by `owner` (nil for global ones).
    func functions(named name: String, owner: String?) -> [(file: Int, function: SwiftFunction)] {
        (functions[owner ?? ""] ?? []).filter { $0.function.name == name }
    }

    func alias(_ name: String) -> String? { aliases[name] }

    /// The type of property `name` on `type`, stored or computed.
    func propertyType(_ name: String, of type: SwiftType) -> String? {
        if let stored = type.properties.first(where: { $0.name == name && !$0.isStatic }) {
            return stored.type
        }
        return members(of: type).first { $0.function.isProperty && $0.function.name == name }?.function.returnType
    }

    // MARK: Shapes

    func shape(_ text: String, _ direction: CodingDirection, context: String? = nil) -> Shape {
        var builder = ShapeBuilder(index: self, direction: direction)
        return builder.shape(.parse(text), context: context, generics: [:])
    }

    func shape(
        _ expression: TypeExpression, _ direction: CodingDirection, context: String?, generics: [String: TypeExpression]
    )
        -> Shape
    {
        var builder = ShapeBuilder(index: self, direction: direction)
        return builder.shape(expression, context: context, generics: generics)
    }
}

private struct ShapeBuilder {
    let index: SwiftTypeIndex
    let direction: CodingDirection
    var stack: [String] = []

    static let builtins: [String: Shape] = [
        "String": .string, "Substring": .string, "URL": .string, "Date": .string, "UUID": .string, "Data": .string,
        "Character": .string, "Int": .integer, "Int8": .integer, "Int16": .integer, "Int32": .integer, "Int64": .integer,
        "UInt": .integer, "UInt8": .integer, "UInt16": .integer, "UInt32": .integer, "UInt64": .integer,
        "Double": .number, "Float": .number, "Decimal": .number, "TimeInterval": .number, "Bool": .boolean, "JSONValue": .any,
    ]

    mutating func shape(_ expression: TypeExpression, context: String?, generics: [String: TypeExpression]) -> Shape {
        switch expression {
        case let .optional(inner): return shape(inner, context: context, generics: generics)
        case let .array(element): return .array(shape(element, context: context, generics: generics))
        case let .dictionary(_, value): return .map(shape(value, context: context, generics: generics))
        case let .unknown(text): return .untyped("type `\(text)` is not a Codable type the check can read")
        case let .named(name, arguments):
            if let bound = generics[name] { return shape(bound, context: context, generics: [:]) }
            if let builtin = Self.builtins[name] { return builtin }
            if ["Array", "Set"].contains(name), let element = arguments.first {
                return .array(shape(element, context: context, generics: generics))
            }
            if name == "Dictionary", arguments.count == 2 { return .map(shape(arguments[1], context: context, generics: generics)) }
            if let alias = index.alias(name) { return shape(.parse(alias), context: context, generics: generics) }
            guard let type = index.type(name, from: context) else { return .untyped("type `\(name)` is not declared in Sources") }
            let bindings = Dictionary(zip(type.generics, arguments.map { resolved($0, generics) }), uniquingKeysWith: { lhs, _ in lhs })
            let key = "\(type.qualified)<\(arguments.map { "\($0)" }.joined(separator: ","))>"
            if stack.contains(key) { return .recursive(type.qualified) }
            stack.append(key)
            defer { stack.removeLast() }
            return shape(of: type, generics: bindings)
        }
    }

    private func resolved(_ expression: TypeExpression, _ generics: [String: TypeExpression]) -> TypeExpression {
        if case let .named(name, arguments) = expression {
            if arguments.isEmpty, let bound = generics[name] { return bound }
            return .named(name, arguments.map { resolved($0, generics) })
        }
        return expression
    }

    private mutating func shape(of type: SwiftType, generics: [String: TypeExpression]) -> Shape {
        if let raw = rawType(type) { return raw }
        let custom = index.members(of: type).first { entry in
            let function = entry.function
            switch direction {
            case .decode: return function.name == "init" && function.parameters.first?.label == "from"
            case .encode: return function.name == "encode" && function.parameters.first?.label == "to"
            }
        }
        if let custom, let body = custom.function.body {
            return customShape(of: type, file: index.files[custom.file], body: body, generics: generics)
        }
        if type.kind == "enum" || type.kind == "protocol" {
            return .untyped("`\(type.qualified)` has no raw value and no hand-written coding")
        }
        return synthesized(type, generics: generics)
    }

    /// A string- or integer-backed enum, or a `RawRepresentable` struct around a string.
    private func rawType(_ type: SwiftType) -> Shape? {
        if type.kind == "enum", let raw = type.inherits.first, let shape = Self.builtins[raw],
            type.cases.allSatisfy({ !$0.hasAssociatedValues })
        {
            return shape
        }
        if type.inherits.contains("RawRepresentable"), let raw = type.properties.first(where: { $0.name == "rawValue" })?.type {
            return Self.builtins[raw]
        }
        return nil
    }

    private func codingKeys(of type: SwiftType) -> [String: String]? {
        guard let keys = index.type("CodingKeys", from: type.qualified), keys.qualified == "\(type.qualified).CodingKeys" else {
            return nil
        }
        return Dictionary(keys.cases.map { ($0.name, $0.rawValue ?? $0.name) }, uniquingKeysWith: { lhs, _ in lhs })
    }

    /// Wire names of every coding-key enum nested in `type`, by case name.
    private func allKeys(of type: SwiftType) -> [String: String] {
        var keys: [String: String] = [:]
        for file in index.files {
            for nested in file.types where nested.qualified.hasPrefix("\(type.qualified).") && nested.kind == "enum" {
                for keyCase in nested.cases { keys[keyCase.name] = keys[keyCase.name] ?? keyCase.rawValue ?? keyCase.name }
            }
        }
        return keys
    }

    private mutating func synthesized(_ type: SwiftType, generics: [String: TypeExpression]) -> Shape {
        let keys = codingKeys(of: type)
        var fields: [String: ShapeField] = [:]
        for property in type.properties where !property.isStatic {
            if direction == .decode, property.initializer != nil, keys == nil { continue }
            guard let wire = keys.map({ $0[property.name] }) ?? property.name else { continue }
            guard let text = property.type else {
                fields[wire] = ShapeField(shape: .untyped("`\(type.qualified).\(property.name)` has no declared type"), required: true)
                continue
            }
            let expression = TypeExpression.parse(text)
            fields[wire] = ShapeField(
                shape: shape(expression, context: type.qualified, generics: generics), required: !expression.isOptional)
        }
        return .object(name: type.qualified, fields: fields)
    }

    private mutating func customShape(of type: SwiftType, file: SwiftFile, body: Range<Int>, generics: [String: TypeExpression]) -> Shape {
        let tokens = file.tokens
        let keys = allKeys(of: type)
        var fields: [String: ShapeField] = [:]
        var single: Shape?
        var delegated: [Shape] = []
        var position = body.lowerBound
        while position < body.upperBound {
            let token = tokens[position]
            guard token.kind == .identifier, position + 1 < body.upperBound, tokens[position + 1].isPunctuation("(") else {
                position += 1
                continue
            }
            let arguments = tokens.arguments(position + 1)
            let forKey = arguments.first { $0.label == "forKey" }.map {
                tokens.text($0.range).trimmingCharacters(in: CharacterSet(charactersIn: "."))
            }
            let first = arguments.first.map { tokens.text($0.range) } ?? ""
            let optional =
                token.text.hasSuffix("IfPresent")
                || (position >= 2 && tokens[position - 2].isIdentifier("try") && tokens[position - 1].isPunctuation("?"))
                || isTryOptional(tokens, before: position)
            if arguments.first?.label == (direction == .decode ? "from" : "to") {
                for delegate in delegateTypes(tokens, position, type: type) {
                    delegated.append(shape(.parse(delegate), context: type.qualified, generics: generics))
                }
                position += 1
                continue
            }
            switch token.text {
            case "decode" where direction == .decode, "decodeIfPresent" where direction == .decode:
                let typeText = first.hasSuffix(".self") ? String(first.dropLast(5)).trimmingCharacters(in: .whitespaces) : first
                let fieldShape = shape(.parse(typeText), context: type.qualified, generics: generics)
                if let forKey, let wire = keys[forKey] {
                    // A key read again as another type is a fallback (`Double`, else `String`): the first read is the wire type.
                    fields[wire] = fields[wire] ?? ShapeField(shape: fieldShape, required: !optional)
                } else if forKey == nil {
                    single = fieldShape
                }
            case "encode" where direction == .encode, "encodeIfPresent" where direction == .encode:
                if let forKey, let wire = keys[forKey], let argument = arguments.first {
                    let fieldShape = encodedShape(tokens, argument.range, type: type, generics: generics)
                    fields[wire] = ShapeField(shape: fieldShape, required: token.text == "encode")
                } else if forKey == nil, arguments.first?.label == nil, first != "to" {
                    single = encodedShape(tokens, arguments[0].range, type: type, generics: generics)
                }
            case "encodeSingle", "singleString":
                single = .string
            default:
                break
            }
            position += 1
        }
        if !fields.isEmpty {
            let own = Shape.object(name: type.qualified, fields: fields)
            return delegated.isEmpty ? own : .merged([own] + delegated)
        }
        if let single { return single }
        if !delegated.isEmpty { return .merged(delegated) }
        return .untyped("`\(type.qualified)` has hand-written coding the check cannot read")
    }

    private func isTryOptional(_ tokens: [SwiftToken], before position: Int) -> Bool {
        var index = position - 1
        while index > 0, tokens[index].isPunctuation(".") || tokens[index].kind == .identifier && !tokens[index].isIdentifier("try") {
            index -= 1
        }
        return index > 0 && tokens[index].isPunctuation("?") && tokens[index - 1].isIdentifier("try")
    }

    /// The types a `T(from: decoder)` or `value.encode(to: encoder)` delegates to. A value bound by
    /// `case let .x(value)` stands for every associated value of the enum.
    private func delegateTypes(_ tokens: [SwiftToken], _ position: Int, type: SwiftType) -> [String] {
        if direction == .decode, tokens[position].text.first?.isUppercase == true { return [tokens[position].text] }
        guard direction == .encode, tokens[position].isIdentifier("encode"), position >= 2, tokens[position - 1].isPunctuation(".") else {
            return []
        }
        if let property = index.propertyType(tokens[position - 2].text, of: type) { return [property] }
        return Array(Set(type.cases.flatMap(\.associatedTypes))).sorted()
    }

    /// The shape of the value expression passed to `encode(_:forKey:)` in a hand-written `encode(to:)`.
    private mutating func encodedShape(
        _ tokens: [SwiftToken], _ range: Range<Int>, type: SwiftType, generics: [String: TypeExpression]
    ) -> Shape {
        var names = range.filter { tokens[$0].kind == .identifier }.map { tokens[$0].text }
        if names.first == "self" { names.removeFirst() }
        if range.count == 1, let literal = literalShape(tokens[range.lowerBound]) { return literal }
        if names.last == "rawValue" || names.last == "absoluteString" || names.last == "uuidString" { return .string }
        if names.count == 2, range.count == 3, let first = names.first, first.first?.isUppercase == true,
            index.type(first, from: type.qualified) != nil
        {
            // A static constant such as `MemberType.customer` is a value of its type.
            return shape(.parse(first), context: type.qualified, generics: generics)
        }
        if names.count == 2, range.count == 3, index.propertyType(names[0], of: type) == nil {
            // `tag.name` where `tag` is bound by `case .access(let tag)`: a field of an associated value.
            let owners = type.cases.flatMap(\.associatedTypes).compactMap { index.type($0, from: type.qualified) }
            if let owner = owners.first(where: { index.propertyType(names[1], of: $0) != nil }),
                let member = index.propertyType(names[1], of: owner)
            {
                return shape(.parse(member), context: owner.qualified, generics: [:])
            }
        }
        if names.count == 1 || (names.count == 2 && range.count == 3), let name = names.first, let text = index.propertyType(name, of: type)
        {
            let expression = TypeExpression.parse(text)
            if names.count == 1 { return shape(expression, context: type.qualified, generics: generics) }
            if case let .named(ownerName, _) = expression.unwrapped, let owner = index.type(ownerName, from: type.qualified),
                let member = index.propertyType(names[1], of: owner)
            {
                return shape(.parse(member), context: owner.qualified, generics: [:])
            }
        }
        return .untyped("`\(type.qualified)` encodes `\(tokens.text(range))`, whose type the check cannot read")
    }

    private func literalShape(_ token: SwiftToken) -> Shape? {
        switch token.kind {
        case .string: return .string
        case .number: return token.text.contains(".") ? .number : .integer
        case .identifier where token.text == "true" || token.text == "false": return .boolean
        default: return nil
        }
    }
}
