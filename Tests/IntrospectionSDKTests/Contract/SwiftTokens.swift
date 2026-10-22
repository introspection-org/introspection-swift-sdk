import Foundation

// A tokenizer for the Swift this SDK is written in, enough for the contract check to read call
// sites and type declarations without a compiler: comments are dropped, a string literal is one
// token with its interpolations kept apart, and every token knows its line and whether whitespace
// came before it (which tells a ternary `?` from optional chaining).

struct SwiftToken: Equatable {
    enum Kind: Equatable {
        case identifier
        case number
        case string
        case punctuation
    }

    var kind: Kind
    /// The identifier, number or punctuation; for a string, the literal text with every
    /// interpolation written as `\(…)` placeholders numbered into `interpolations`.
    var text: String
    var line: Int
    var spaceBefore: Bool
    /// Source of each `\(…)` in a string literal, in order.
    var interpolations: [String] = []
    /// A string's literal text split around its interpolations: `parts.count == interpolations.count + 1`.
    var parts: [String] = []

    func isIdentifier(_ name: String) -> Bool { kind == .identifier && text == name }
    func isPunctuation(_ mark: String) -> Bool { kind == .punctuation && text == mark }
}

struct SwiftTokenizer {
    private let chars: [Character]
    private var index = 0
    private var line = 1
    private var tokens: [SwiftToken] = []
    private var sawSpace = true

    static func tokenize(_ source: String) -> [SwiftToken] {
        var tokenizer = SwiftTokenizer(chars: Array(source))
        tokenizer.run()
        return tokenizer.tokens
    }

    private init(chars: [Character]) { self.chars = chars }

    private func peek(_ offset: Int = 0) -> Character? {
        index + offset < chars.count ? chars[index + offset] : nil
    }

    private mutating func run() {
        while let char = peek() {
            if char == "\n" {
                line += 1
                index += 1
                sawSpace = true
            } else if char.isWhitespace {
                index += 1
                sawSpace = true
            } else if char == "/" && peek(1) == "/" {
                while let next = peek(), next != "\n" { index += 1 }
            } else if char == "/" && peek(1) == "*" {
                skipBlockComment()
            } else if char == "\"" || (char == "#" && rawStringAhead()) {
                lexString()
            } else if char.isLetter || char == "_" || char == "$" || char == "`" {
                lexIdentifier()
            } else if char.isNumber {
                lexNumber()
            } else {
                lexPunctuation(char)
            }
        }
    }

    private mutating func emit(_ kind: SwiftToken.Kind, _ text: String, line: Int) {
        tokens.append(SwiftToken(kind: kind, text: text, line: line, spaceBefore: sawSpace))
        sawSpace = false
    }

    private mutating func skipBlockComment() {
        var depth = 0
        while let char = peek() {
            if char == "/" && peek(1) == "*" {
                depth += 1
                index += 2
            } else if char == "*" && peek(1) == "/" {
                depth -= 1
                index += 2
                if depth == 0 { break }
            } else {
                if char == "\n" { line += 1 }
                index += 1
            }
        }
        sawSpace = true
    }

    private func rawStringAhead() -> Bool {
        var offset = 0
        while peek(offset) == "#" { offset += 1 }
        return peek(offset) == "\""
    }

    private mutating func lexIdentifier() {
        let start = line
        var text = ""
        if peek() == "`" {
            index += 1
            while let char = peek(), char != "`" {
                text.append(char)
                index += 1
            }
            index += 1
        } else {
            while let char = peek(), char.isLetter || char.isNumber || char == "_" || char == "$" {
                text.append(char)
                index += 1
            }
        }
        emit(.identifier, text, line: start)
    }

    private mutating func lexNumber() {
        let start = line
        var text = ""
        while let char = peek(), char.isNumber || char.isLetter || char == "_" || (char == "." && peek(1)?.isNumber == true) {
            text.append(char)
            index += 1
        }
        emit(.number, text, line: start)
    }

    private mutating func lexPunctuation(_ char: Character) {
        let pair = String([char, peek(1) ?? " "])
        if ["->", "==", "!=", "&&", "||", "??", "...", "..<"].contains(pair) || pair == ".." {
            let text = pair == ".." ? (peek(2) == "<" ? "..<" : "...") : pair
            emit(.punctuation, text, line: line)
            index += text.count
        } else {
            emit(.punctuation, String(char), line: line)
            index += 1
        }
    }

    /// A string literal, plain, multi-line or raw, as one token.
    private mutating func lexString() {
        let start = line
        var hashes = 0
        while peek() == "#" {
            hashes += 1
            index += 1
        }
        let multiline = peek() == "\"" && peek(1) == "\"" && peek(2) == "\""
        index += multiline ? 3 : 1
        let closing = String(repeating: "\"", count: multiline ? 3 : 1) + String(repeating: "#", count: hashes)
        let escape = "\\" + String(repeating: "#", count: hashes)
        var parts = [""]
        var interpolations: [String] = []
        while index < chars.count {
            if matches(closing) {
                index += closing.count
                break
            }
            if matches(escape) {
                index += escape.count
                if peek() == "(" {
                    interpolations.append(readInterpolation())
                    parts.append("")
                } else if let escaped = peek() {
                    parts[parts.count - 1].append(escaped == "n" ? "\n" : escaped)
                    index += 1
                }
                continue
            }
            if peek() == "\n" { line += 1 }
            parts[parts.count - 1].append(chars[index])
            index += 1
        }
        var token = SwiftToken(kind: .string, text: parts.joined(separator: "\\(…)"), line: start, spaceBefore: sawSpace)
        token.parts = parts
        token.interpolations = interpolations
        tokens.append(token)
        sawSpace = false
    }

    private func matches(_ text: String) -> Bool {
        for (offset, char) in text.enumerated() where peek(offset) != char { return false }
        return true
    }

    /// The source between `(` and its matching `)`, nested strings included.
    private mutating func readInterpolation() -> String {
        index += 1
        var depth = 1
        var text = ""
        var inString = false
        while let char = peek() {
            index += 1
            if char == "\"" { inString.toggle() }
            if !inString {
                if char == "(" { depth += 1 }
                if char == ")" {
                    depth -= 1
                    if depth == 0 { break }
                }
            }
            text.append(char)
        }
        return text
    }
}

extension Array where Element == SwiftToken {
    /// The index of the bracket closing the one at `open` (`(`, `[`, `{` or `<`).
    func closing(_ open: Int) -> Int {
        let pairs: [String: String] = ["(": ")", "[": "]", "{": "}", "<": ">"]
        guard let close = pairs[self[open].text] else { return open }
        var depth = 0
        var index = open
        while index < count {
            if self[index].isPunctuation(self[open].text) {
                depth += 1
            } else if self[index].isPunctuation(close) {
                depth -= 1
                if depth == 0 { return index }
            }
            index += 1
        }
        return count - 1
    }

    /// Split `range` at top-level occurrences of `separator`, bracket depth aware.
    func split(_ range: Range<Int>, at separator: String) -> [Range<Int>] {
        var pieces: [Range<Int>] = []
        var start = range.lowerBound
        var index = range.lowerBound
        while index < range.upperBound {
            let token = self[index]
            if token.kind == .punctuation, ["(", "[", "{"].contains(token.text) {
                index = closing(index) + 1
                continue
            }
            if token.isPunctuation(separator) {
                pieces.append(start..<index)
                start = index + 1
            }
            index += 1
        }
        pieces.append(start..<range.upperBound)
        return pieces.filter { !$0.isEmpty }
    }

    /// The source text of `range`, tokens joined the way they were spaced.
    func text(_ range: Range<Int>) -> String {
        var out = ""
        for index in range {
            let token = self[index]
            if token.spaceBefore && !out.isEmpty { out += " " }
            out += token.kind == .string ? "\"\(token.text)\"" : token.text
        }
        return out
    }
}

/// One argument of a call: its label (nil when unlabeled) and its expression's token range.
struct CallArgument {
    var label: String?
    var range: Range<Int>
}

extension Array where Element == SwiftToken {
    /// The arguments of the call whose `(` is at `open`.
    func arguments(_ open: Int) -> [CallArgument] {
        let close = closing(open)
        return split((open + 1)..<close, at: ",").map { piece in
            if piece.count > 1, self[piece.lowerBound].kind == .identifier, self[piece.lowerBound + 1].isPunctuation(":") {
                return CallArgument(label: self[piece.lowerBound].text, range: (piece.lowerBound + 2)..<piece.upperBound)
            }
            return CallArgument(label: nil, range: piece)
        }
    }
}
