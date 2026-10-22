import Foundation

// The declarations of one Swift file that the contract check needs: types with their stored
// properties, enum cases and coding-key enums, and functions (computed properties count as
// functions without parameters) with their parameters, return type and body. Bodies are kept as
// token ranges and not parsed further here.

struct SwiftParameter {
    /// The argument label; nil for `_`.
    var label: String?
    var name: String
    var type: String
    var defaultValue: Range<Int>?
}

struct SwiftFunction {
    var name: String
    /// The type this function belongs to (an extension counts as its type), nil for a global one.
    var owner: String?
    var parameters: [SwiftParameter]
    var returnType: String?
    var body: Range<Int>?
    var isProperty: Bool
    var line: Int
}

struct SwiftProperty {
    var name: String
    var type: String?
    var isStatic: Bool
    var initializer: Range<Int>?
    var line: Int
}

struct SwiftEnumCase {
    var name: String
    var rawValue: String?
    var hasAssociatedValues: Bool
    /// The types of its associated values, labels dropped.
    var associatedTypes: [String] = []
}

struct SwiftType {
    var kind: String
    var name: String
    /// `Outer.Inner` for a nested type.
    var qualified: String
    var generics: [String]
    var inherits: [String]
    var properties: [SwiftProperty] = []
    var cases: [SwiftEnumCase] = []
    var line: Int
}

struct SwiftFile {
    let path: String
    let tokens: [SwiftToken]
    private(set) var types: [SwiftType] = []
    private(set) var functions: [SwiftFunction] = []
    private(set) var typealiases: [String: String] = [:]

    init(path: String, source: String) {
        self.path = path
        tokens = SwiftTokenizer.tokenize(source)
        parseMembers(0..<tokens.count, owner: nil, ownerKind: nil)
    }

    /// The innermost function whose body contains token `index`.
    func enclosingFunction(_ index: Int) -> SwiftFunction? {
        functions.filter { $0.body?.contains(index) == true }.min { ($0.body?.count ?? 0) < ($1.body?.count ?? 0) }
    }

    func location(_ index: Int) -> String { "\(path):\(tokens[min(index, tokens.count - 1)].line)" }

    private static let typeKeywords: Set<String> = ["struct", "class", "enum", "actor", "protocol", "extension"]

    private mutating func parseMembers(_ range: Range<Int>, owner: String?, ownerKind: String?) {
        var index = range.lowerBound
        var isStatic = false
        while index < range.upperBound {
            let token = tokens[index]
            let next = index + 1 < tokens.count ? tokens[index + 1] : nil
            if token.kind == .punctuation {
                if token.text == "{" { index = tokens.closing(index) }
                if token.text == "@" { index += 1 }
                index += 1
                continue
            }
            guard token.kind == .identifier else {
                index += 1
                continue
            }
            switch token.text {
            case let keyword
            where Self.typeKeywords.contains(keyword) && next?.kind == .identifier && next?.text != "func"
                && next?.text != "var":
                index = parseType(index, owner: owner)
            case "func":
                index = parseFunction(index, name: next?.text ?? "", owner: owner)
            case "init" where next?.isPunctuation("(") == true || next?.isPunctuation("?") == true || next?.isPunctuation("<") == true:
                index = parseFunction(index, name: "init", owner: owner)
            case "var", "let":
                index = parseProperty(index, owner: owner, isStatic: isStatic || ownerKind == "protocol")
            case "case" where ownerKind == "enum":
                index = parseCases(index, owner: owner)
            case "typealias":
                index = parseTypealias(index)
            case "static", "class":
                isStatic = true
                index += 1
                continue
            default:
                index += 1
                continue
            }
            isStatic = false
        }
    }

    private func nameTokens(from start: Int) -> (String, Int) {
        var name = tokens[start].text
        var index = start + 1
        while index + 1 < tokens.count, tokens[index].isPunctuation("."), tokens[index + 1].kind == .identifier {
            name += "." + tokens[index + 1].text
            index += 2
        }
        return (name, index)
    }

    private mutating func parseType(_ start: Int, owner: String?) -> Int {
        let kind = tokens[start].text
        var (name, index) = nameTokens(from: start + 1)
        var generics: [String] = []
        if index < tokens.count, tokens[index].isPunctuation("<") {
            let close = tokens.closing(index)
            generics = tokens.split((index + 1)..<close, at: ",").map { tokens[$0.lowerBound].text }
            index = close + 1
        }
        var inherits: [String] = []
        var current = ""
        while index < tokens.count, !tokens[index].isPunctuation("{") {
            let token = tokens[index]
            if token.isIdentifier("where") {
                index = scanTo("{", from: index)
                break
            }
            if token.isPunctuation(",") {
                inherits.append(current)
                current = ""
            } else if !token.isPunctuation(":") {
                current += token.text
            }
            index += 1
        }
        if !current.isEmpty { inherits.append(current) }
        guard index < tokens.count else { return index }
        let close = tokens.closing(index)
        let simple = String(name.split(separator: ".").last ?? Substring(name))
        let qualified = kind == "extension" ? name : (owner.map { "\($0).\(name)" } ?? name)
        if kind == "extension" {
            name = simple
        } else {
            types.append(
                SwiftType(kind: kind, name: simple, qualified: qualified, generics: generics, inherits: inherits, line: tokens[start].line))
        }
        parseMembers((index + 1)..<close, owner: qualified, ownerKind: kind == "extension" ? kindOf(qualified) : kind)
        return close + 1
    }

    private func kindOf(_ qualified: String) -> String? { types.first { $0.qualified == qualified }?.kind }

    private func scanTo(_ mark: String, from start: Int) -> Int {
        var index = start
        while index < tokens.count, !tokens[index].isPunctuation(mark) { index += 1 }
        return index
    }

    private mutating func parseFunction(_ start: Int, name: String, owner: String?) -> Int {
        var index = start + (name == "init" ? 1 : 2)
        while index < tokens.count, !tokens[index].isPunctuation("(") {
            if tokens[index].isPunctuation("<") {
                index = tokens.closing(index)
            }
            index += 1
        }
        guard index < tokens.count else { return index }
        let close = tokens.closing(index)
        let parameters = tokens.split((index + 1)..<close, at: ",").compactMap(parameter)
        index = close + 1
        var returnType: [Int] = []
        var afterArrow = false
        let stops: Set<String> = ["func", "var", "let", "case", "init", "static", "public", "private", "internal", "where"]
        while index < tokens.count {
            let token = tokens[index]
            if token.isPunctuation("{") || token.isPunctuation("}") || (token.kind == .identifier && stops.contains(token.text)) {
                break
            }
            if token.isPunctuation("->") {
                afterArrow = true
            } else if afterArrow {
                returnType.append(index)
            }
            index += 1
        }
        if index < tokens.count, tokens[index].isIdentifier("where") { index = scanTo("{", from: index) }
        var body: Range<Int>?
        if index < tokens.count, tokens[index].isPunctuation("{") {
            let end = tokens.closing(index)
            body = (index + 1)..<end
            index = end + 1
        }
        let type = returnType.isEmpty ? nil : tokens.text(returnType.first!..<(returnType.last! + 1))
        functions.append(
            SwiftFunction(
                name: name, owner: owner, parameters: parameters, returnType: type, body: body, isProperty: false,
                line: tokens[start].line))
        return index
    }

    private func parameter(_ range: Range<Int>) -> SwiftParameter? {
        let pieces = tokens.split(range, at: "=")
        guard let head = pieces.first else { return nil }
        guard let colon = head.first(where: { tokens[$0].isPunctuation(":") }) else { return nil }
        let names = (head.lowerBound..<colon).filter { tokens[$0].kind == .identifier }.map { tokens[$0].text }
        guard let name = names.last else { return nil }
        let label = names.count > 1 ? names[names.count - 2] : name
        let typeRange = (colon + 1)..<head.upperBound
        let type = typeRange.filter {
            !["@", "escaping", "Sendable", "inout", "sending", "borrowing", "consuming"].contains(tokens[$0].text)
        }
        let text = type.isEmpty ? "" : tokens.text(type.first!..<(type.last! + 1))
        let defaultValue = pieces.count > 1 ? (pieces[1].lowerBound..<range.upperBound) : nil
        return SwiftParameter(label: label == "_" ? nil : label, name: name, type: text, defaultValue: defaultValue)
    }

    /// The end of the expression or type starting at `start`: the first top-level token on a later line
    /// than the one before it, or one of `stops`.
    private func endOfLine(from start: Int, stops: Set<String>, isType: Bool = false) -> Int {
        var index = start
        while index < tokens.count {
            let token = tokens[index]
            if token.kind == .punctuation, stops.contains(token.text) { return index }
            if index > start, token.line > tokens[index - 1].line, isType || !continuesExpression(index) { return index }
            if token.kind == .punctuation, ["(", "[", "<"].contains(token.text) {
                index = token.text == "<" && !looksGeneric(index) ? index : tokens.closing(index)
            } else if token.isPunctuation("{"), !stops.contains("{") {
                index = tokens.closing(index)
            }
            index += 1
        }
        return index
    }

    private func looksGeneric(_ index: Int) -> Bool { !tokens[index].spaceBefore }

    private func continuesExpression(_ index: Int) -> Bool {
        let previous = tokens[index - 1]
        let token = tokens[index]
        if previous.kind == .punctuation, ["=", "+", "?", ":", ",", "(", "[", "??", "&&", "||"].contains(previous.text) { return true }
        if token.kind == .punctuation, [".", "+", "?", ":", "??", "&&", "||"].contains(token.text) { return true }
        return false
    }

    private mutating func parseProperty(_ start: Int, owner: String?, isStatic: Bool) -> Int {
        guard start + 1 < tokens.count, tokens[start + 1].kind == .identifier else { return start + 1 }
        let name = tokens[start + 1].text
        var index = start + 2
        var type: String?
        if index < tokens.count, tokens[index].isPunctuation(":") {
            let end = endOfLine(from: index + 1, stops: ["=", "{"], isType: true)
            type = tokens.text((index + 1)..<end)
            index = end
        }
        if index < tokens.count, tokens[index].isPunctuation("{"), tokens[index].line == tokens[start].line {
            let close = tokens.closing(index)
            let observers = tokens[index + 1].isIdentifier("didSet") || tokens[index + 1].isIdentifier("willSet")
            if !observers {
                functions.append(
                    SwiftFunction(
                        name: name, owner: owner, parameters: [], returnType: type, body: (index + 1)..<close, isProperty: true,
                        line: tokens[start].line))
                return close + 1
            }
            append(SwiftProperty(name: name, type: type, isStatic: isStatic, initializer: nil, line: tokens[start].line), to: owner)
            return close + 1
        }
        var initializer: Range<Int>?
        if index < tokens.count, tokens[index].isPunctuation("=") {
            let end = endOfLine(from: index + 1, stops: [])
            initializer = (index + 1)..<end
            index = end
        }
        append(SwiftProperty(name: name, type: type, isStatic: isStatic, initializer: initializer, line: tokens[start].line), to: owner)
        return index
    }

    private mutating func append(_ property: SwiftProperty, to owner: String?) {
        guard let typeIndex = types.lastIndex(where: { $0.qualified == owner }) else { return }
        types[typeIndex].properties.append(property)
    }

    private mutating func parseCases(_ start: Int, owner: String?) -> Int {
        let end = endOfLine(from: start + 1, stops: ["}"])
        for piece in tokens.split((start + 1)..<end, at: ",") where tokens[piece.lowerBound].kind == .identifier {
            let name = tokens[piece.lowerBound].text
            let associated = piece.count > 1 && tokens[piece.lowerBound + 1].isPunctuation("(")
            var raw: String?
            if let equals = piece.first(where: { tokens[$0].isPunctuation("=") }), equals + 1 < piece.upperBound {
                raw = tokens[equals + 1].text
            }
            var associatedTypes: [String] = []
            if associated {
                let open = piece.lowerBound + 1
                associatedTypes = tokens.split((open + 1)..<tokens.closing(open), at: ",").map { value in
                    let colon = value.first { tokens[$0].isPunctuation(":") }
                    return tokens.text(colon.map { ($0 + 1)..<value.upperBound } ?? value)
                }
            }
            if let typeIndex = types.lastIndex(where: { $0.qualified == owner }) {
                types[typeIndex].cases.append(
                    SwiftEnumCase(name: name, rawValue: raw, hasAssociatedValues: associated, associatedTypes: associatedTypes))
            }
        }
        return end
    }

    private mutating func parseTypealias(_ start: Int) -> Int {
        guard start + 3 < tokens.count, tokens[start + 2].isPunctuation("=") else { return start + 1 }
        let end = endOfLine(from: start + 3, stops: [])
        typealiases[tokens[start + 1].text] = tokens.text((start + 3)..<end)
        return end
    }
}
