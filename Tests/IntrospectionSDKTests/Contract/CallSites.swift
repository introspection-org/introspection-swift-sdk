import Foundation

// Every request Sources sends, found by reading the source: a call of `json`, `empty`, `data`,
// `stream` or `send` with a literal HTTP method, `paginate` (a GET) or `url` (a GET the browser
// opens). The route, body, query and response type are followed from the call through local
// constants, path helpers, `params.query` builders and private wrappers that pass them through.

enum BodyPart {
    case none
    case json(Shape)
    case form
    case multipart
    case raw
    case unresolved(String)
}

enum ResponsePart {
    /// The call decodes nothing (`empty`, or a result it drops).
    case none
    /// Bytes, a stream or a redirect URL: not compared, they declare no fields.
    case nonJSON
    case json(Shape)
    case unresolved(String)
}

struct QueryField {
    var shape: Shape?
    var optional: Bool
}

struct CallSite {
    var method: String
    /// Route templates with each path parameter written `{}`.
    var paths: [String]
    var location: String
    var body: BodyPart
    var query: [String: QueryField]
    /// Why some of the query could not be read; empty when all of it was.
    var queryGaps: [String]
    var response: ResponsePart
    /// The media type a literal `Accept` header asks for; empty when the header is not a literal.
    var accept: String?
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
    case expression(Range<Int>, Scope, type: String?)
    case parameter(SwiftParameter)
    case property(String)
    case none
}

struct CallSiteScanner {
    let index: SwiftTypeIndex
    static let methods: Set<String> = ["GET", "POST", "PUT", "PATCH", "DELETE"]
    private static let verbs: Set<String> = ["json", "empty", "data", "stream", "send"]

    func tokens(_ scope: Scope) -> [SwiftToken] { index.files[scope.file].tokens }

    func scan() -> [CallSite] {
        var sites: [CallSite] = []
        for (fileIndex, file) in index.files.enumerated() {
            let tokens = file.tokens
            for position in 1..<max(tokens.count - 1, 1) {
                let token = tokens[position]
                guard token.kind == .identifier, tokens[position - 1].isPunctuation("."), tokens[position + 1].isPunctuation("(") else {
                    continue
                }
                guard Self.verbs.contains(token.text) || token.text == "paginate" || token.text == "url" else { continue }
                let function = file.enclosingFunction(position)
                if function?.owner == "HTTPClient" { continue }
                sites += expand(position, Scope(file: fileIndex, function: function))
            }
        }
        return sites
    }

    /// The call at `position` in `scope`, or, when its route, body or query is a parameter of a private
    /// wrapper, the call once for each caller of that wrapper.
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
        let passthrough = [pathArgument.range] + arguments.filter { ["body", "query"].contains($0.label) }.map(\.range)
        if scope.depth < 3, let wrapper = scope.function, passthrough.contains(where: { unboundParameter($0, scope) != nil }) {
            let callers = self.callers(of: wrapper, in: scope)
            if !callers.isEmpty { return Self.merged(callers.flatMap { expand(position, $0) }) }
        }
        let paths = Set(self.paths(pathArgument.range, scope)).filter { $0.hasPrefix("/v1/") }
        guard !paths.isEmpty else { return [] }
        let file = index.files[scope.file]
        var site = CallSite(
            method: method, paths: paths.sorted(), location: file.location(position), body: .none, query: [:], queryGaps: [],
            response: .none)
        if verb != "url" {
            site.body = body(arguments.first { $0.label == "body" }?.range, scope)
        }
        if let query = arguments.first(where: { $0.label == "query" })?.range {
            var collector = QueryCollector(scanner: self)
            collector.collect(query, scope)
            site.query = collector.fields
            site.queryGaps = collector.gaps
        }
        if verb == "paginate" { site.query["next"] = QueryField(shape: .string, optional: true) }
        site.response = response(verb, position, arguments, scope)
        site.accept = accept(arguments.first { $0.label == "headers" }?.range, tokens)
        return [site]
    }

    private func accept(_ range: Range<Int>?, _ tokens: [SwiftToken]) -> String? {
        guard let range else { return nil }
        for position in range where position + 2 < range.upperBound && tokens[position].kind == .string && tokens[position].text == "Accept"
        {
            guard tokens[position + 1].isPunctuation(":") else { continue }
            let value = tokens[position + 2]
            let alone = position + 3 >= tokens.count || tokens[position + 3].isPunctuation(",") || tokens[position + 3].isPunctuation("]")
            return value.kind == .string && value.interpolations.isEmpty && alone ? value.text : ""
        }
        return nil
    }

    /// One wrapper call reached from several callers is one call site: what it sends is what any caller passes.
    private static func merged(_ sites: [CallSite]) -> [CallSite] {
        var merged: [CallSite] = []
        for site in sites {
            guard
                let existing = merged.firstIndex(where: {
                    $0.location == site.location && $0.method == site.method && $0.paths == site.paths
                })
            else {
                merged.append(site)
                continue
            }
            if case let .json(lhs) = merged[existing].body, case let .json(rhs) = site.body {
                merged[existing].body = .json(.merged([lhs, rhs]))
            }
            for (name, field) in site.query where merged[existing].query[name] == nil { merged[existing].query[name] = field }
            merged[existing].queryGaps += site.queryGaps
        }
        return merged
    }

    /// The parameter of the enclosing function that `range` is, when no caller has bound it yet.
    private func unboundParameter(_ range: Range<Int>, _ scope: Scope) -> SwiftParameter? {
        let tokens = tokens(scope)
        let stripped = strip(range, tokens)
        guard stripped.count == 1, tokens[stripped.lowerBound].kind == .identifier else { return nil }
        if case let .parameter(parameter) = referent(tokens[stripped.lowerBound].text, before: stripped.lowerBound, scope) {
            return parameter
        }
        return nil
    }

    /// Calls of `function` in its own file, each as the scope its body runs in for that call.
    private func callers(of function: SwiftFunction, in scope: Scope) -> [Scope] {
        let file = index.files[scope.file]
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
    func bind(
        _ function: SwiftFunction, _ arguments: [CallArgument], caller: Scope, calleeFile: Int
    )
        -> [String: (range: Range<Int>, scope: Scope)]?
    {
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
    func strip(_ range: Range<Int>, _ tokens: [SwiftToken]) -> Range<Int> {
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
    func referent(_ name: String, before position: Int, _ scope: Scope) -> Referent {
        if let bound = scope.bindings[name] { return .expression(bound.range, bound.scope, type: nil) }
        let tokens = tokens(scope)
        if let function = scope.function, let body = function.body {
            var found: Referent?
            var cursor = body.lowerBound
            while cursor < min(position, body.upperBound) - 1 {
                if tokens[cursor].isIdentifier("let") || tokens[cursor].isIdentifier("var"), tokens[cursor + 1].isIdentifier(name) {
                    // `guard let name` and `if var name` unwrap the same name from further out.
                    let next = tokens[cursor + 2]
                    if next.isPunctuation("=") || next.isPunctuation(":"),
                        let declared = declaration(at: cursor + 2, before: position, scope)
                    {
                        found = declared
                    }
                }
                cursor += 1
            }
            if let found { return found }
            if let parameter = function.parameters.first(where: { $0.name == name }) { return .parameter(parameter) }
            if isPaginatorCursor(name, before: position, in: body, tokens) { return .property("String?") }
        }
        if let owner = scope.function?.owner, let type = index.type(owner), let property = index.propertyType(name, of: type) {
            return .property(property)
        }
        return .none
    }

    /// `Paginator { cursor in … }`: the fetch closure's one parameter is the page cursor, a `String?`.
    private func isPaginatorCursor(_ name: String, before position: Int, in body: Range<Int>, _ tokens: [SwiftToken]) -> Bool {
        for cursor in body where cursor < position && tokens[cursor].isIdentifier("Paginator") {
            var open = cursor + 1
            if open < tokens.count, tokens[open].isPunctuation("(") { open = tokens.closing(open) + 1 }
            guard open + 2 < tokens.count, tokens[open].isPunctuation("{") else { continue }
            var parameter = open + 1
            if tokens[parameter].isPunctuation("[") { parameter = tokens.closing(parameter) + 1 }
            if tokens[parameter].isIdentifier(name), tokens[parameter + 1].isIdentifier("in"), tokens.closing(open) > position {
                return true
            }
        }
        return false
    }

    /// The declaration whose name is just before `start`, or nil when its initializer is still running at `position`
    /// (as in `var body = body`, whose right-hand side means the name from further out).
    private func declaration(at start: Int, before position: Int, _ scope: Scope) -> Referent? {
        let tokens = tokens(scope)
        var cursor = start
        var type: String?
        if tokens[cursor].isPunctuation(":") {
            var end = cursor + 1
            while end < position, !tokens[end].isPunctuation("="), tokens[end].line == tokens[cursor].line { end += 1 }
            type = tokens.text((cursor + 1)..<end)
            cursor = end
        }
        guard cursor < position, tokens[cursor].isPunctuation("=") else {
            return type.map { .expression(cursor..<cursor, scope, type: $0) }
        }
        let end = lineEnd(from: cursor + 1, limit: tokens.count, tokens)
        guard end <= position else { return nil }
        return .expression((cursor + 1)..<end, scope, type: type)
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
        if first.kind == .identifier {
            let last = range.upperBound - 1
            if tokens[last].isPunctuation(")"), let open = openParen(of: last, tokens), open > range.lowerBound {
                return helperPaths(tokens[open - 1].text, tokens.arguments(open), scope)
            }
            if range.count == 1 {
                switch referent(first.text, before: range.lowerBound, scope) {
                case let .expression(expression, inner, _): return paths(expression, inner)
                default: return helperPaths(first.text, [], scope)
                }
            }
            if tokens[last].kind == .identifier, tokens[last - 1].isPunctuation(".") {
                return helperPaths(tokens[last].text, [], scope)
            }
        }
        return []
    }

    func openParen(of close: Int, _ tokens: [SwiftToken]) -> Int? {
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

    func ternaryBranches(_ range: Range<Int>, _ tokens: [SwiftToken]) -> [Range<Int>]? {
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
                if case let .expression(expression, innerScope, _) = referent(inner[0].text, before: Int.max, scope) {
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
        let file = index.files[scope.file]
        let candidates = file.functions.filter { $0.name == name && $0.body != nil }
        var routes: [String] = []
        for function in candidates {
            guard let bindings = bind(function, arguments, caller: scope, calleeFile: scope.file) else { continue }
            let inner = Scope(file: scope.file, function: function, bindings: bindings, depth: scope.depth + 1)
            guard inner.depth < 6 else { continue }
            for expression in returnedExpressions(function, file.tokens) { routes += paths(expression, inner) }
        }
        return routes
    }

    /// The expressions a function body returns: each `return`, or the whole body when it has none.
    func returnedExpressions(_ function: SwiftFunction, _ tokens: [SwiftToken]) -> [Range<Int>] {
        guard let body = function.body else { return [] }
        let returns = body.filter { tokens[$0].isIdentifier("return") }
        guard !returns.isEmpty else { return [body] }
        return returns.map { start in (start + 1)..<lineEnd(from: start + 1, limit: body.upperBound, tokens) }
    }

    /// The end of the expression starting at `start`: the first token at bracket depth 0 on a later line that
    /// does not continue it, or the `}` closing its block.
    func lineEnd(from start: Int, limit: Int, _ tokens: [SwiftToken]) -> Int {
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
