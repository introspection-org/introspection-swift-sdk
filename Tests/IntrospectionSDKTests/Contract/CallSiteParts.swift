import Foundation

// The body, response and query of a call site, read from its arguments and the code around it.

extension CallSiteScanner {
    // MARK: Types of expressions

    /// The declared type of the value `range` evaluates to, nil when the source does not say.
    func typeOf(_ range: Range<Int>, _ scope: Scope) -> String? {
        let tokens = tokens(scope)
        let range = strip(range, tokens)
        guard !range.isEmpty else { return nil }
        if let branches = ternaryBranches(range, tokens) {
            return branches.lazy.filter { !(tokens[$0.lowerBound].isIdentifier("nil") && $0.count == 1) }.compactMap { typeOf($0, scope) }
                .first
        }
        let first = tokens[range.lowerBound]
        if range.count == 1 {
            switch first.kind {
            case .string: return "String"
            case .number: return first.text.contains(".") ? "Double" : "Int"
            case .identifier where first.text == "true" || first.text == "false": return "Bool"
            case .identifier: return identifierType(first.text, before: range.lowerBound, scope)
            case .punctuation: return nil
            }
        }
        guard first.kind == .identifier else { return nil }
        if ["rawValue", "absoluteString", "uuidString"].contains(tokens[range.upperBound - 1].text) { return "String" }
        if first.text.first?.isUppercase == false, range.count > 2, tokens[range.lowerBound + 1].isPunctuation("("),
            tokens.closing(range.lowerBound + 1) == range.upperBound - 1
        {
            // A call of a function declared alongside this one: its declared return type.
            let owner = scope.function?.owner
            let candidates = index.functions(named: first.text, owner: owner) + index.functions(named: first.text, owner: nil)
            return candidates.lazy.compactMap(\.function.returnType).first
        }
        if first.text.first?.isUppercase == true, range.count > 1 {
            // `T(…)`, `T.init(…)`, or a static factory `T.make(…)`, which returns a `T`.
            if tokens[range.lowerBound + 1].isPunctuation("(") || tokens[range.lowerBound + 1].isPunctuation(".") {
                return first.text
            }
            if tokens[range.lowerBound + 1].isPunctuation("<") {
                return tokens.text(range.lowerBound..<(tokens.closing(range.lowerBound + 1) + 1))
            }
        }
        // `a.b`: the type of `a`, then its property `b`.
        if range.count == 3, tokens[range.lowerBound + 1].isPunctuation("."), tokens[range.lowerBound + 2].kind == .identifier,
            let ownerText = identifierType(first.text, before: range.lowerBound, scope),
            case let .named(ownerName, _) = TypeExpression.parse(ownerText).unwrapped,
            let owner = index.type(ownerName, from: scope.function?.owner)
        {
            return index.propertyType(tokens[range.lowerBound + 2].text, of: owner)
        }
        return nil
    }

    private func identifierType(_ name: String, before position: Int, _ scope: Scope) -> String? {
        switch referent(name, before: position, scope) {
        case let .expression(expression, inner, type): return type ?? typeOf(expression, inner)
        case let .parameter(parameter): return parameter.type
        case let .property(type): return type
        case .none: return nil
        }
    }

    // MARK: Body

    func body(_ argument: Range<Int>?, _ scope: Scope) -> BodyPart {
        guard let argument else { return .none }
        let tokens = tokens(scope)
        let range = strip(argument, tokens)
        guard !range.isEmpty else { return .none }
        let first = tokens[range.lowerBound]
        if first.isPunctuation("."), range.count > 1 {
            switch tokens[range.lowerBound + 1].text {
            case "none": return .none
            case "form": return .form
            case "multipart": return .multipart
            case "raw": return .raw
            case "encode":
                let open = range.lowerBound + 2
                guard open < range.upperBound, tokens[open].isPunctuation("("), let value = tokens.arguments(open).first else {
                    return .unresolved("`\(tokens.text(range))` is not a call the check can read")
                }
                return encoded(value.range, scope)
            default: return .unresolved("`\(tokens.text(range))` builds a body the check cannot read")
            }
        }
        if range.count == 1, first.kind == .identifier {
            switch referent(first.text, before: range.lowerBound, scope) {
            case let .expression(expression, inner, _) where !expression.isEmpty: return body(expression, inner)
            default: break
            }
        }
        return .unresolved("`\(tokens.text(range))` is a prebuilt body the check cannot follow")
    }

    private func encoded(_ range: Range<Int>, _ scope: Scope) -> BodyPart {
        let tokens = tokens(scope)
        let stripped = strip(range, tokens)
        if let first = stripped.first, tokens[first].isPunctuation("[") {
            return .unresolved("the body is a dictionary literal, so its fields have no declared types")
        }
        guard let type = typeOf(range, scope) else {
            return .unresolved("the type of `\(tokens.text(range))` is not declared at the call site")
        }
        let shape = index.shape(.parse(type), .encode, context: scope.function?.owner, generics: [:])
        if case let .untyped(reason) = shape { return .unresolved(reason) }
        return .json(shape)
    }

    // MARK: Response

    func response(_ verb: String, _ position: Int, _ arguments: [CallArgument], _ scope: Scope) -> ResponsePart {
        let tokens = tokens(scope)
        switch verb {
        case "empty": return .none
        case "data", "stream", "url": return .nonJSON
        case "send": return .unresolved("the call reads the raw response, which has no declared type")
        default: break
        }
        var typeText: String?
        if let explicit = arguments.first(where: { $0.label == "as" }) {
            let text = tokens.text(explicit.range)
            typeText = text.hasSuffix(".self") ? String(text.dropLast(5)).trimmingCharacters(in: .whitespaces) : nil
        } else {
            typeText = contextType(position, scope)
            if verb == "paginate" {
                guard let text = typeText, case let .named("Paginator", items) = TypeExpression.parse(text), let item = items.first else {
                    return .unresolved("the page type is inferred from context the check cannot read")
                }
                return pageShape(item, scope)
            }
        }
        if verb == "paginate", let typeText { return pageShape(.parse(typeText), scope) }
        guard let typeText else { return .unresolved("the response type is inferred from context the check cannot read") }
        if typeText == "Void" || typeText == "()" { return .none }
        let expression = TypeExpression.parse(typeText)
        if case let .named(name, _) = expression.unwrapped, scope.function.map({ isGeneric(name, $0) }) == true {
            return .unresolved("the response type is the generic `\(name)`")
        }
        let shape = index.shape(expression, .decode, context: scope.function?.owner, generics: [:])
        if case let .untyped(reason) = shape { return .unresolved(reason) }
        return .json(shape)
    }

    private func pageShape(_ item: TypeExpression, _ scope: Scope) -> ResponsePart {
        let shape = index.shape(.named("Page", [item]), .decode, context: scope.function?.owner, generics: [:])
        if case let .untyped(reason) = shape { return .unresolved(reason) }
        return .json(shape)
    }

    private func isGeneric(_ name: String, _ function: SwiftFunction) -> Bool {
        name.count == 1 || ["T", "Item", "Value", "Response"].contains(name) && index.type(name) == nil
    }

    /// The type the expression containing the call at `position` is used as: the function's return type when
    /// it is returned, or the annotation of the constant it initializes.
    private func contextType(_ position: Int, _ scope: Scope) -> String? {
        let tokens = tokens(scope)
        var cursor = position - 1
        while cursor > 0, tokens[cursor].isPunctuation(".") || tokens[cursor].kind == .identifier && !keywords.contains(tokens[cursor].text)
        {
            cursor -= 1
        }
        while cursor > 0,
            tokens[cursor].isIdentifier("try") || tokens[cursor].isIdentifier("await")
                || tokens[cursor].isPunctuation("?")
                    && tokens[cursor - 1].isIdentifier("try")
        {
            cursor -= 1
        }
        guard let function = scope.function, let body = function.body else { return nil }
        if cursor < body.lowerBound || tokens[cursor].isIdentifier("return") || cursor + 1 == body.lowerBound {
            return function.returnType.map(stripEffects)
        }
        if tokens[cursor].isPunctuation("=") {
            if tokens[cursor - 1].isIdentifier("_") { return "Void" }
            var start = cursor - 1
            while start > body.lowerBound, !tokens[start].isIdentifier("let"), !tokens[start].isIdentifier("var"),
                !tokens[start].isPunctuation(":")
            {
                start -= 1
            }
            if tokens[start].isPunctuation(":") { return tokens.text((start + 1)..<cursor) }
        }
        return nil
    }

    private var keywords: Set<String> { ["return", "try", "await", "let", "var", "in", "else", "case"] }

    private func stripEffects(_ text: String) -> String { text.trimmingCharacters(in: .whitespaces) }
}

/// The query items a call site sends, followed through `Query` builders.
struct QueryCollector {
    let scanner: CallSiteScanner
    var fields: [String: QueryField] = [:]
    var gaps: [String] = []
    private var seen: Set<String> = []

    init(scanner: CallSiteScanner) { self.scanner = scanner }

    mutating func collect(_ argument: Range<Int>, _ scope: Scope) {
        let tokens = scanner.tokens(scope)
        let range = scanner.strip(argument, tokens)
        guard !range.isEmpty, scope.depth < 8 else { return }
        let first = tokens[range.lowerBound]
        let key = "\(scope.file):\(range.lowerBound)"
        guard seen.insert(key).inserted else { return }
        if range.count == 1, first.kind == .identifier {
            switch scanner.referent(first.text, before: range.lowerBound, scope) {
            case let .expression(expression, inner, _):
                if !expression.isEmpty { collect(expression, inner) }
                if let body = inner.function?.body { adds(on: first.text, in: body, inner) }
            case .parameter:
                if let body = scope.function?.body { adds(on: first.text, in: body, scope) }
            case .property, .none:
                gaps.append("`\(first.text)` is a query the check cannot follow")
            }
            return
        }
        if first.isIdentifier("Query"), range.count == 3 { return }
        let last = range.upperBound - 1
        if tokens[last].isPunctuation(")"), let open = scanner.openParen(of: last, tokens), open > range.lowerBound {
            builder(tokens[open - 1].text, receiver: range.lowerBound..<max(open - 2, range.lowerBound), tokens.arguments(open), scope)
            return
        }
        if tokens[last].kind == .identifier, range.count >= 3, tokens[last - 1].isPunctuation(".") {
            builder(tokens[last].text, receiver: range.lowerBound..<(last - 1), [], scope)
            return
        }
        gaps.append("`\(tokens.text(range))` is a query the check cannot follow")
    }

    /// A function or computed property that builds a `Query`: global, or a member of the receiver's type.
    private mutating func builder(_ name: String, receiver: Range<Int>, _ arguments: [CallArgument], _ scope: Scope) {
        let index = scanner.index
        var candidates: [(file: Int, function: SwiftFunction)] = []
        if !receiver.isEmpty, let typeText = scanner.typeOf(receiver, scope),
            case let .named(typeName, _) = TypeExpression.parse(typeText).unwrapped,
            let type = index.type(typeName, from: scope.function?.owner)
        {
            candidates = index.members(of: type).filter { $0.function.name == name }
        } else {
            candidates = index.functions(named: name, owner: scope.function?.owner) + index.functions(named: name, owner: nil)
        }
        guard let (file, function) = candidates.first, let body = function.body else {
            gaps.append("`\(name)` builds a query the check cannot find")
            return
        }
        let caller = scope
        let bindings = scanner.bind(function, arguments, caller: caller, calleeFile: file) ?? [:]
        let inner = Scope(file: file, function: function, bindings: bindings, depth: scope.depth + 1)
        adds(on: nil, in: body, inner)
        for returned in scanner.returnedExpressions(function, index.files[file].tokens) {
            let tokens = index.files[file].tokens
            if returned.count == 1, tokens[returned.lowerBound].kind == .identifier { continue }
            collect(returned, inner)
        }
    }

    /// `helper(to: &query, …)`: the items the helper adds to its `inout` parameter.
    private mutating func inoutHelper(_ ampersand: Int, in body: Range<Int>, _ scope: Scope) {
        let tokens = scanner.tokens(scope)
        var open = ampersand
        var depth = 0
        while open > body.lowerBound {
            open -= 1
            if tokens[open].isPunctuation(")") { depth += 1 }
            if tokens[open].isPunctuation("(") {
                if depth == 0 { break }
                depth -= 1
            }
        }
        guard open > body.lowerBound, tokens[open - 1].kind == .identifier else { return }
        let name = tokens[open - 1].text
        let arguments = tokens.arguments(open)
        guard let argument = arguments.first(where: { $0.range.lowerBound == ampersand }) else { return }
        let candidates =
            scanner.index.functions(named: name, owner: scope.function?.owner) + scanner.index.functions(named: name, owner: nil)
        guard let (file, function) = candidates.first, let calleeBody = function.body,
            let parameter = function.parameters.first(where: { $0.label == argument.label })
        else {
            gaps.append("`\(name)` adds to the query in a way the check cannot follow")
            return
        }
        let bindings = scanner.bind(function, arguments, caller: scope, calleeFile: file) ?? [:]
        adds(on: parameter.name, in: calleeBody, Scope(file: file, function: function, bindings: bindings, depth: scope.depth + 1))
    }

    /// Every `<receiver>.add("name", value)` and `.set("name", value)` in `body`; any receiver when nil.
    private mutating func adds(on receiver: String?, in body: Range<Int>, _ scope: Scope) {
        let tokens = scanner.tokens(scope)
        for position in body where position >= 2 && position + 1 < tokens.count {
            if tokens[position].isPunctuation("&"), tokens[position + 1].kind == .identifier,
                receiver == nil || tokens[position + 1].isIdentifier(receiver!)
            {
                inoutHelper(position, in: body, scope)
                continue
            }
            guard tokens[position].isIdentifier("add") || tokens[position].isIdentifier("set"), tokens[position - 1].isPunctuation("."),
                tokens[position + 1].isPunctuation("(")
            else { continue }
            if let receiver, !tokens[position - 2].isIdentifier(receiver) { continue }
            let arguments = tokens.arguments(position + 1)
            guard arguments.count == 2, arguments[0].range.count == 1, tokens[arguments[0].range.lowerBound].kind == .string else {
                continue
            }
            let name = tokens[arguments[0].range.lowerBound].text
            guard let typeText = scanner.typeOf(arguments[1].range, scope) else {
                fields[name] = fields[name] ?? QueryField(shape: nil, optional: true)
                continue
            }
            let expression = TypeExpression.parse(typeText)
            let shape = scanner.index.shape(expression, .encode, context: scope.function?.owner, generics: [:])
            fields[name] = QueryField(shape: shape, optional: expression.isOptional || tokens[position].isIdentifier("set"))
        }
    }
}
