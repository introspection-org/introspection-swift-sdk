import Foundation

// Every route Sources requests, found by reading the source: a call of `json`, `empty`, `data`,
// `stream` or `send` with a literal HTTP method, `paginate` (a GET) or `url` (a GET the browser
// opens). The route is followed from the call through local constants, path helpers and private
// wrappers that take it as a parameter.

struct CallSite: Hashable {
    var method: String
    /// Route templates with each path parameter written `{}`.
    var paths: [String]
    var location: String
}

/// Where an expression is evaluated: a file, the function around it, and what that function's
/// parameters were bound to by the caller being followed.
final class Scope {
    let file: Int
    let function: SwiftFunction?
    let bindings: [String: (range: Range<Int>, scope: Scope)]
    let depth: Int

    init(file: Int, function: SwiftFunction?, bindings: [String: (range: Range<Int>, scope: Scope)] = [:], depth: Int = 0) {
        self.file = file
        self.function = function
        self.bindings = bindings
        self.depth = depth
    }
}

/// What an identifier refers to at a point in a function.
enum Referent {
    case expression(Range<Int>, Scope)
    case parameter
    case none
}

struct CallSiteScanner {
    let files: [SwiftFile]
    static let methods: Set<String> = ["GET", "POST", "PUT", "PATCH", "DELETE"]
    private static let verbs: Set<String> = ["json", "empty", "data", "stream", "send"]

    func tokens(_ scope: Scope) -> [SwiftToken] { files[scope.file].tokens }

    func scan() -> [CallSite] {
        var sites: Set<CallSite> = []
        for (fileIndex, file) in files.enumerated() {
            let tokens = file.tokens
            for position in 1..<max(tokens.count - 1, 1) {
                let token = tokens[position]
                guard token.kind == .identifier, tokens[position - 1].isPunctuation("."), tokens[position + 1].isPunctuation("(") else {
                    continue
                }
                guard Self.verbs.contains(token.text) || token.text == "paginate" || token.text == "url" else { continue }
                let function = file.enclosingFunction(position)
                if function?.owner == "HTTPClient" { continue }
                sites.formUnion(expand(position, Scope(file: fileIndex, function: function)))
            }
        }
        return Array(sites)
    }

    /// The call at `position` in `scope`, or, when its route is a parameter of a private wrapper, the call
    /// once for each caller of that wrapper.
    private func expand(_ position: Int, _ scope: Scope) -> [CallSite] {
        let tokens = tokens(scope)
        let verb = tokens[position].text
        let arguments = tokens.arguments(position + 1)
        var method = "GET"
        var pathArgument = arguments.first
        if Self.verbs.contains(verb) {
            guard let first = arguments.first, first.range.count == 1, tokens[first.range.lowerBound].kind == .string,
                Self.methods.contains(tokens[first.range.lowerBound].text), arguments.count > 1
            else { return [] }
            method = tokens[first.range.lowerBound].text
            pathArgument = arguments[1]
        }
        guard let pathArgument else { return [] }
        if scope.depth < 3, let wrapper = scope.function, isUnboundParameter(pathArgument.range, scope) {
            let callers = self.callers(of: wrapper, in: scope)
            if !callers.isEmpty { return callers.flatMap { expand(position, $0) } }
        }
        let paths = Set(self.paths(pathArgument.range, scope)).filter { $0.hasPrefix("/v1/") }
        guard !paths.isEmpty else { return [] }
        return [CallSite(method: method, paths: paths.sorted(), location: files[scope.file].location(position))]
    }

    /// Whether `range` is a parameter of the enclosing function that no caller has bound yet.
    private func isUnboundParameter(_ range: Range<Int>, _ scope: Scope) -> Bool {
        let tokens = tokens(scope)
        let stripped = strip(range, tokens)
        guard stripped.count == 1, tokens[stripped.lowerBound].kind == .identifier else { return false }
        if case .parameter = referent(tokens[stripped.lowerBound].text, before: stripped.lowerBound, scope) { return true }
        return false
    }

    /// Calls of `function` in its own file, each as the scope its body runs in for that call.
    private func callers(of function: SwiftFunction, in scope: Scope) -> [Scope] {
        let file = files[scope.file]
        let tokens = file.tokens
        var scopes: [Scope] = []
        for position in 0..<(tokens.count - 1) where tokens[position].isIdentifier(function.name) && tokens[position + 1].isPunctuation("(")
        {
            if position > 0, tokens[position - 1].isIdentifier("func") { continue }
            let caller = Scope(file: scope.file, function: file.enclosingFunction(position), depth: scope.depth + 1)
            guard let bindings = bind(function, tokens.arguments(position + 1), caller: caller, calleeFile: scope.file) else { continue }
            scopes.append(Scope(file: scope.file, function: function, bindings: bindings, depth: scope.depth + 1))
        }
        return scopes
    }

    /// The parameters of `function` bound to a call's arguments, defaults filled in; nil when they do not fit.
    private func bind(
        _ function: SwiftFunction, _ arguments: [CallArgument], caller: Scope, calleeFile: Int
    ) -> [String: (range: Range<Int>, scope: Scope)]? {
        var bindings: [String: (range: Range<Int>, scope: Scope)] = [:]
        var remaining = arguments
        for parameter in function.parameters {
            if let match = remaining.firstIndex(where: { $0.label == parameter.label }) {
                bindings[parameter.name] = (remaining[match].range, caller)
                remaining.remove(at: match)
            } else if let defaultValue = parameter.defaultValue {
                bindings[parameter.name] = (defaultValue, Scope(file: calleeFile, function: function))
            }
        }
        return remaining.isEmpty ? bindings : nil
    }

    // MARK: Expressions

    /// `range` without a leading `try`, `try?`, `await` or `self.`.
    private func strip(_ range: Range<Int>, _ tokens: [SwiftToken]) -> Range<Int> {
        var lower = range.lowerBound
        while lower < range.upperBound {
            if tokens[lower].isIdentifier("try") || tokens[lower].isIdentifier("await") {
                lower += 1
                if lower < range.upperBound, tokens[lower].isPunctuation("?") || tokens[lower].isPunctuation("!") { lower += 1 }
            } else if tokens[lower].isIdentifier("self"), lower + 1 < range.upperBound, tokens[lower + 1].isPunctuation(".") {
                lower += 2
            } else {
                break
            }
        }
        return lower..<range.upperBound
    }

    /// What `name` refers to at token `position` of `scope`.
    private func referent(_ name: String, before position: Int, _ scope: Scope) -> Referent {
        if let bound = scope.bindings[name] { return .expression(bound.range, bound.scope) }
        guard let function = scope.function, let body = function.body else { return .none }
        let tokens = tokens(scope)
        var found: Referent?
        var cursor = body.lowerBound
        while cursor < min(position, body.upperBound) - 1 {
            if tokens[cursor].isIdentifier("let") || tokens[cursor].isIdentifier("var"), tokens[cursor + 1].isIdentifier(name) {
                // `guard let name` and `if var name` unwrap the same name from further out.
                if let declared = initializer(at: cursor + 2, before: position, tokens) { found = .expression(declared, scope) }
            }
            cursor += 1
        }
        if let found { return found }
        return function.parameters.contains { $0.name == name } ? .parameter : .none
    }

    /// The initializer of the declaration whose name is just before `start`, or nil when there is none or it is
    /// still running at `position` (as in `var path = path`, whose right-hand side means the name from further out).
    private func initializer(at start: Int, before position: Int, _ tokens: [SwiftToken]) -> Range<Int>? {
        var cursor = start
        if tokens[cursor].isPunctuation(":") {
            while cursor < position, !tokens[cursor].isPunctuation("="), tokens[cursor].line == tokens[start].line { cursor += 1 }
        }
        guard cursor < position, tokens[cursor].isPunctuation("=") else { return nil }
        let end = lineEnd(from: cursor + 1, limit: tokens.count, tokens)
        return end <= position ? (cursor + 1)..<end : nil
    }

    // MARK: Routes

    /// The route templates `range` can evaluate to.
    func paths(_ range: Range<Int>, _ scope: Scope) -> [String] {
        let tokens = tokens(scope)
        let range = strip(range, tokens)
        guard !range.isEmpty else { return [] }
        if let branches = ternaryBranches(range, tokens) { return branches.flatMap { paths($0, scope) } }
        let pieces = tokens.split(range, at: "+")
        if pieces.count > 1 {
            return pieces.reduce([""]) { prefixes, piece in
                let options = paths(piece, scope)
                return prefixes.flatMap { prefix in (options.isEmpty ? ["{}"] : options).map { prefix + $0 } }
            }
        }
        let first = tokens[range.lowerBound]
        if range.count == 1, first.kind == .string { return [template(first, scope)] }
        guard first.kind == .identifier else { return [] }
        let last = range.upperBound - 1
        if tokens[last].isPunctuation(")"), let open = openParen(of: last, tokens), open > range.lowerBound {
            return helperPaths(tokens[open - 1].text, tokens.arguments(open), scope)
        }
        if range.count == 1 {
            if case let .expression(expression, inner) = referent(first.text, before: range.lowerBound, scope) {
                return paths(expression, inner)
            }
            return helperPaths(first.text, [], scope)
        }
        if tokens[last].kind == .identifier, tokens[last - 1].isPunctuation(".") { return helperPaths(tokens[last].text, [], scope) }
        return []
    }

    private func openParen(of close: Int, _ tokens: [SwiftToken]) -> Int? {
        var depth = 0
        var cursor = close
        while cursor >= 0 {
            if tokens[cursor].isPunctuation(")") { depth += 1 }
            if tokens[cursor].isPunctuation("(") {
                depth -= 1
                if depth == 0 { return cursor }
            }
            cursor -= 1
        }
        return nil
    }

    private func ternaryBranches(_ range: Range<Int>, _ tokens: [SwiftToken]) -> [Range<Int>]? {
        let question = tokens.split(range, at: "?")
        guard question.count == 2, let mark = question.first?.upperBound, tokens[mark].spaceBefore else { return nil }
        let branches = tokens.split(question[1], at: ":")
        return branches.count == 2 ? branches : nil
    }

    /// A string literal with each interpolation replaced by what it resolves to, `{}` for a path parameter.
    private func template(_ token: SwiftToken, _ scope: Scope) -> String {
        var out = token.parts[0]
        for (offset, source) in token.interpolations.enumerated() {
            let inner = SwiftTokenizer.tokenize(source)
            var value = "{}"
            if inner.count == 1, inner[0].kind == .identifier {
                if case let .expression(expression, innerScope) = referent(inner[0].text, before: Int.max, scope) {
                    value = literal(expression, innerScope) ?? paths(expression, innerScope).first ?? "{}"
                }
            } else if let call = inner.firstIndex(where: { $0.isPunctuation("(") }), call > 0, inner.last?.isPunctuation(")") == true,
                inner[call - 1].kind == .identifier
            {
                // A path helper called inside the literal; its own parameters become path parameters.
                value = helperPaths(inner[call - 1].text, [], scope).first ?? "{}"
            }
            out += value + token.parts[offset + 1]
        }
        return out
    }

    private func literal(_ range: Range<Int>, _ scope: Scope) -> String? {
        let tokens = tokens(scope)
        guard range.count == 1, tokens[range.lowerBound].kind == .string, tokens[range.lowerBound].interpolations.isEmpty else {
            return nil
        }
        return tokens[range.lowerBound].text
    }

    /// The routes a path helper (a function or computed property returning a route) returns.
    private func helperPaths(_ name: String, _ arguments: [CallArgument], _ scope: Scope) -> [String] {
        let file = files[scope.file]
        var routes: [String] = []
        for function in file.functions where function.name == name && function.body != nil {
            guard let bindings = bind(function, arguments, caller: scope, calleeFile: scope.file) else { continue }
            let inner = Scope(file: scope.file, function: function, bindings: bindings, depth: scope.depth + 1)
            guard inner.depth < 6 else { continue }
            for expression in returnedExpressions(function, file.tokens) { routes += paths(expression, inner) }
        }
        return routes
    }

    /// The expressions a function body returns: each `return`, or the whole body when it has none.
    private func returnedExpressions(_ function: SwiftFunction, _ tokens: [SwiftToken]) -> [Range<Int>] {
        guard let body = function.body else { return [] }
        let returns = body.filter { tokens[$0].isIdentifier("return") }
        guard !returns.isEmpty else { return [body] }
        return returns.map { start in (start + 1)..<lineEnd(from: start + 1, limit: body.upperBound, tokens) }
    }

    /// The end of the expression starting at `start`: the first token at bracket depth 0 on a later line that
    /// does not continue it, or the `}` closing its block.
    private func lineEnd(from start: Int, limit: Int, _ tokens: [SwiftToken]) -> Int {
        var cursor = start
        while cursor < limit {
            let token = tokens[cursor]
            if token.isPunctuation("}") { return cursor }
            if cursor > start, token.line > tokens[cursor - 1].line {
                let previous = tokens[cursor - 1]
                let continues =
                    [".", "+", "?", ":", "??", "&&", "||"].contains(token.text) && token.kind == .punctuation
                    || ["=", "+", "?", ":", ",", "(", "[", "??", "&&", "||"].contains(previous.text) && previous.kind == .punctuation
                if !continues { return cursor }
            }
            if token.kind == .punctuation, ["(", "[", "{"].contains(token.text) { cursor = tokens.closing(cursor) }
            cursor += 1
        }
        return limit
    }
}
