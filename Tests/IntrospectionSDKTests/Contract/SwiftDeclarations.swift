import Foundation

// The declarations of one Swift file that the route scan needs: functions (computed properties
// count as functions without parameters) with their owner, parameters and body. Bodies are kept as
// token ranges and not parsed further here.

struct SwiftParameter {
    /// The argument label; nil for `_`.
    var label: String?
    var name: String
    var defaultValue: Range<Int>?
}

struct SwiftFunction {
    var name: String
    /// The type this function belongs to (an extension counts as its type), nil for a global one.
    var owner: String?
    var parameters: [SwiftParameter]
    var body: Range<Int>?
}

struct SwiftFile {
    let path: String
    let tokens: [SwiftToken]
    private(set) var functions: [SwiftFunction] = []

    init(path: String, source: String) {
        self.path = path
        tokens = SwiftTokenizer.tokenize(source)
        parseMembers(0..<tokens.count, owner: nil)
    }

    /// The innermost function whose body contains token `index`.
    func enclosingFunction(_ index: Int) -> SwiftFunction? {
        functions.filter { $0.body?.contains(index) == true }.min { ($0.body?.count ?? 0) < ($1.body?.count ?? 0) }
    }

    func location(_ index: Int) -> String { "\(path):\(tokens[min(index, tokens.count - 1)].line)" }

    private static let typeKeywords: Set<String> = ["struct", "class", "enum", "actor", "protocol", "extension"]

    private mutating func parseMembers(_ range: Range<Int>, owner: String?) {
        var index = range.lowerBound
        while index < range.upperBound {
            let token = tokens[index]
            let next = index + 1 < tokens.count ? tokens[index + 1] : nil
            if token.isPunctuation("{") {
                index = tokens.closing(index) + 1
            } else if token.kind != .identifier {
                index += 1
            } else if Self.typeKeywords.contains(token.text), next?.kind == .identifier, next?.text != "func", next?.text != "var" {
                index = parseType(index, owner: owner)
            } else if token.text == "func" {
                index = parseFunction(index, name: next?.text ?? "", owner: owner)
            } else if token.text == "init",
                next?.isPunctuation("(") == true || next?.isPunctuation("?") == true || next?.isPunctuation("<") == true
            {
                index = parseFunction(index, name: "init", owner: owner)
            } else if token.text == "var", next?.kind == .identifier {
                index = parseComputedProperty(index, owner: owner)
            } else {
                index += 1
            }
        }
    }

    private mutating func parseType(_ start: Int, owner: String?) -> Int {
        var name = tokens[start + 1].text
        var index = start + 2
        while index + 1 < tokens.count, tokens[index].isPunctuation("."), tokens[index + 1].kind == .identifier {
            name += "." + tokens[index + 1].text
            index += 2
        }
        while index < tokens.count, !tokens[index].isPunctuation("{") { index += 1 }
        guard index < tokens.count else { return index }
        let close = tokens.closing(index)
        let qualified = tokens[start].isIdentifier("extension") ? name : (owner.map { "\($0).\(name)" } ?? name)
        parseMembers((index + 1)..<close, owner: qualified)
        return close + 1
    }

    private mutating func parseFunction(_ start: Int, name: String, owner: String?) -> Int {
        var index = start + (name == "init" ? 1 : 2)
        while index < tokens.count, !tokens[index].isPunctuation("(") {
            if tokens[index].isPunctuation("<") { index = tokens.closing(index) }
            index += 1
        }
        guard index < tokens.count else { return index }
        let close = tokens.closing(index)
        let parameters = tokens.split((index + 1)..<close, at: ",").compactMap(parameter)
        index = close + 1
        // A protocol requirement has no body: stop at the next declaration.
        let stops: Set<String> = ["func", "var", "let", "case", "init", "static", "public", "private", "internal"]
        while index < tokens.count, !tokens[index].isPunctuation("{"), !tokens[index].isPunctuation("}"),
            !(tokens[index].kind == .identifier && stops.contains(tokens[index].text))
        {
            index += 1
        }
        var body: Range<Int>?
        if index < tokens.count, tokens[index].isPunctuation("{") {
            let end = tokens.closing(index)
            body = (index + 1)..<end
            index = end + 1
        }
        functions.append(SwiftFunction(name: name, owner: owner, parameters: parameters, body: body))
        return index
    }

    private func parameter(_ range: Range<Int>) -> SwiftParameter? {
        let pieces = tokens.split(range, at: "=")
        guard let head = pieces.first, let colon = head.first(where: { tokens[$0].isPunctuation(":") }) else { return nil }
        let names = (head.lowerBound..<colon).filter { tokens[$0].kind == .identifier }.map { tokens[$0].text }
        guard let name = names.last else { return nil }
        let label = names.count > 1 ? names[names.count - 2] : name
        let defaultValue = pieces.count > 1 ? (pieces[1].lowerBound..<range.upperBound) : nil
        return SwiftParameter(label: label == "_" ? nil : label, name: name, defaultValue: defaultValue)
    }

    /// `var name: Type { … }` on one line is a computed property; anything else is stepped over.
    private mutating func parseComputedProperty(_ start: Int, owner: String?) -> Int {
        var index = start + 2
        guard index < tokens.count, tokens[index].isPunctuation(":") else { return index }
        while index < tokens.count, tokens[index].line == tokens[start].line, !tokens[index].isPunctuation("{"),
            !tokens[index].isPunctuation("=")
        {
            if tokens[index].kind == .punctuation, ["(", "["].contains(tokens[index].text) { index = tokens.closing(index) }
            index += 1
        }
        guard index < tokens.count, tokens[index].isPunctuation("{"), tokens[index].line == tokens[start].line else { return index }
        let close = tokens.closing(index)
        if !(tokens[index + 1].isIdentifier("didSet") || tokens[index + 1].isIdentifier("willSet")) {
            functions.append(SwiftFunction(name: tokens[start + 1].text, owner: owner, parameters: [], body: (index + 1)..<close))
        }
        return close + 1
    }
}
