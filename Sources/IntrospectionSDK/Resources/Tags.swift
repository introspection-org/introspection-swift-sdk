import Foundation

/// The project tag catalogue: the values a share, a member tag, or an annotation carries.
///
/// A catalogue row names a tag people pick from; it grants nothing. The two kinds are
/// separate catalogues with separate scopes, and their fields differ — an `access` tag is
/// an opaque value with no colour, an `annotation` tag is a slug that must have one.
/// ``TagCreate`` is an enum per kind so that rule is unrepresentable rather than validated.

/// Which catalogue a tag belongs to.
///
/// `access` tags are the values tag shares and member tags carry; `annotation` tags are
/// the annotation labels.
public enum TagKind: String, Codable, Sendable, Hashable {
    case access
    case annotation
}

/// A tag in the catalogue.
public struct Tag: Codable, Sendable, Hashable {
    public var kind: TagKind
    public var name: String
    /// Set on an `annotation` tag; never on an `access` tag.
    public var color: String?
    public var description: String?
    public var createdAt: Date?
    public var updatedAt: Date?

    public init(
        kind: TagKind,
        name: String,
        color: String? = nil,
        description: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.kind = kind
        self.name = name
        self.color = color
        self.description = description
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case kind, name, color, description
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// An access tag to add. Its name is opaque and kept verbatim, so it may contain `/`.
public struct AccessTagCreate: Sendable, Hashable {
    public var name: String
    public var description: String?

    public init(name: String, description: String? = nil) {
        self.name = name
        self.description = description
    }
}

/// An annotation tag to add. The API slugifies the name, and a colour is required.
public struct AnnotationTagCreate: Sendable, Hashable {
    public var name: String
    /// Six-digit hex colour such as `#f97316`.
    public var color: String
    public var description: String?

    public init(name: String, color: String, description: String? = nil) {
        self.name = name
        self.color = color
        self.description = description
    }
}

/// Body of `POST /v1/tags`. The kind picks the case, so an access tag has no colour to
/// set and an annotation tag cannot omit one.
public enum TagCreate: Encodable, Sendable, Hashable {
    case access(AccessTagCreate)
    case annotation(AnnotationTagCreate)

    public static func access(name: String, description: String? = nil) -> TagCreate {
        .access(AccessTagCreate(name: name, description: description))
    }

    public static func annotation(
        name: String, color: String, description: String? = nil
    ) -> TagCreate {
        .annotation(AnnotationTagCreate(name: name, color: color, description: description))
    }

    public var kind: TagKind {
        switch self {
        case .access: .access
        case .annotation: .annotation
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind, name, color, description
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch self {
        case .access(let tag):
            try container.encode(tag.name, forKey: .name)
            try container.encodeIfPresent(tag.description, forKey: .description)
        case .annotation(let tag):
            try container.encode(tag.name, forKey: .name)
            try container.encode(tag.color, forKey: .color)
            try container.encodeIfPresent(tag.description, forKey: .description)
        }
    }
}

/// Body of `PATCH /v1/tags/{kind}/{name}`.
///
/// The API tells an omitted field from a null, so a field left `nil` here is left alone
/// and `description: .some(nil)` clears it. Prefer the constructors below.
public struct TagUpdate: Encodable, Sendable, Hashable {
    public var color: String?
    public var description: String??

    public init(color: String? = nil, description: String?? = nil) {
        self.color = color
        self.description = description
    }

    /// Recolour an annotation tag.
    public static func color(_ value: String) -> TagUpdate { TagUpdate(color: value) }

    /// Set the description.
    public static func description(_ value: String) -> TagUpdate {
        TagUpdate(description: .some(value))
    }

    /// Clear the description.
    public static let clearDescription = TagUpdate(description: .some(nil))

    var namesAField: Bool { color != nil || description != nil }

    private enum CodingKeys: String, CodingKey { case color, description }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(color, forKey: .color)
        // An omitted key leaves the description; an explicit null clears it.
        if let description {
            try container.encode(description, forKey: .description)
        }
    }
}

/// Paging and search for `GET /v1/tags`.
///
/// `kind` is required: the two kinds are separate catalogues, and the API has no listing
/// that spans them.
public struct TagListParams: Sendable, Hashable {
    public var kind: TagKind
    public var search: String?
    public var limit: Int?
    public var next: String?

    public init(kind: TagKind, search: String? = nil, limit: Int? = nil, next: String? = nil) {
        self.kind = kind
        self.search = search
        self.limit = limit
        self.next = next
    }
}

/// The project tag catalogue.
public struct TagsAPI: Sendable {
    let http: HTTPClient

    public init(http: HTTPClient) { self.http = http }

    /// List one catalogue.
    public func list(_ params: TagListParams) -> Paginator<Tag> {
        var query = Query()
        query.add("kind", params.kind.rawValue)
        query.add("search", params.search)
        query.add("limit", params.limit)
        return http.paginate("/v1/tags", query: query, start: params.next)
    }

    /// Add a tag. An existing one comes back as it is, and a deleted one is revived.
    public func create(_ body: TagCreate) async throws -> Tag {
        let normalized = try validated(body)
        return try await http.json("POST", "/v1/tags", body: .encode(normalized))
    }

    /// Fetch one tag.
    public func get(_ kind: TagKind, _ name: String) async throws -> Tag {
        try await http.json("GET", path(kind, name))
    }

    /// Change a tag's colour or description.
    public func update(_ kind: TagKind, _ name: String, _ body: TagUpdate) async throws -> Tag {
        guard body.namesAField else {
            throw tagValidationError(
                "A tag update must name a color or a description", code: "invalid_tag_update"
            )
        }
        if kind == .access, body.color != nil {
            throw tagValidationError("An access tag has no color", code: "invalid_tag_color")
        }
        var body = body
        if let color = body.color {
            body.color = try lowercasedHex(color)
        }
        if let outer = body.description, let value = outer {
            try checkDescription(value)
        }
        return try await http.json("PATCH", path(kind, name), body: .encode(body))
    }

    /// Remove a tag from the catalogue. Shares, member tags and annotations keep theirs.
    public func delete(_ kind: TagKind, _ name: String) async throws {
        try await http.empty("DELETE", path(kind, name))
    }

    /// An access tag's name may contain `/`, so it is encoded even though the API matches
    /// it as a path.
    private func path(_ kind: TagKind, _ name: String) -> String {
        "/v1/tags/\(kind.rawValue)/\(pathSegment(name))"
    }

    private func validated(_ body: TagCreate) throws -> TagCreate {
        switch body {
        case .access(let tag):
            let name = try trimmedName(tag.name)
            try checkDescription(tag.description)
            return .access(AccessTagCreate(name: name, description: tag.description))
        case .annotation(let tag):
            let name = try trimmedName(tag.name)
            try checkDescription(tag.description)
            return .annotation(
                AnnotationTagCreate(
                    name: name, color: try lowercasedHex(tag.color), description: tag.description
                )
            )
        }
    }
}

// MARK: Helpers

private let maxTagDescription = 2000

private func tagValidationError(_ message: String, code: String) -> IntrospectionError {
    IntrospectionError(kind: .validation, message: message, status: 422, code: code)
}

private func tagDescriptionError() -> IntrospectionError {
    tagValidationError(
        "A tag description must not exceed 2000 characters", code: "invalid_tag_description"
    )
}

private func trimmedName(_ value: String) throws -> String {
    let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, name.count <= 128 else {
        throw tagValidationError(
            "A tag name must contain 1 to 128 characters", code: "invalid_tag_name"
        )
    }
    return name
}

private func lowercasedHex(_ value: String) throws -> String {
    let color = value.lowercased()
    let hex = color.dropFirst()
    guard color.hasPrefix("#"), hex.count == 6, hex.allSatisfy(\.isHexDigit) else {
        throw tagValidationError(
            "A tag color must be a six-digit hex color such as #f97316", code: "invalid_tag_color"
        )
    }
    return color
}

private func checkDescription(_ value: String?) throws {
    if let value, value.count > maxTagDescription { throw tagDescriptionError() }
}

extension IntrospectionClient {
    /// The project tag catalogue (Data Plane).
    public var tags: TagsAPI { TagsAPI(http: dataPlane) }
}
