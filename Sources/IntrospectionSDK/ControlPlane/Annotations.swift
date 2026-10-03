import Foundation

// MARK: Models

/// A span to annotate, by OTel hex ids (32-char trace, 16-char span).
public struct AnnotationTarget: Sendable, Hashable {
    public var traceId: String
    public var spanId: String

    public init(traceId: String, spanId: String) {
        self.traceId = traceId
        self.spanId = spanId
    }
}

/// Review state of an annotated span.
public struct AnnotationReviewStatus: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let backlog: AnnotationReviewStatus = "backlog"
    public static let assigned: AnnotationReviewStatus = "assigned"
    public static let reviewed: AnnotationReviewStatus = "reviewed"
}

/// Current labels, assignees and comments folded from one span's annotation events.
public struct AnnotationState: Codable, Sendable, Hashable {
    public var traceId: String
    public var spanId: String
    public var conversationId: String?
    public var labels: [String]?
    public var assigneeMemberIds: [String]?
    public var annotatorMemberIds: [String]?
    public var commenterMemberIds: [String]?
    public var hasComment: Bool?
    public var humanCommenterMemberIds: [String]?
    public var hasHumanComment: Bool?
    public var commentCount: Int?
    public var latestComment: String?
    public var latestCommentMemberId: String?
    public var latestCommentActorMemberId: String?
    public var latestCommentActorType: String?
    public var updatedAt: Date?
    public var updatedByMemberId: String?
    public var assignmentEventId: String?

    public init(
        traceId: String, spanId: String, conversationId: String? = nil, labels: [String]? = nil,
        assigneeMemberIds: [String]? = nil, annotatorMemberIds: [String]? = nil, commenterMemberIds: [String]? = nil,
        hasComment: Bool? = nil, humanCommenterMemberIds: [String]? = nil, hasHumanComment: Bool? = nil,
        commentCount: Int? = nil, latestComment: String? = nil, latestCommentMemberId: String? = nil,
        latestCommentActorMemberId: String? = nil, latestCommentActorType: String? = nil, updatedAt: Date? = nil,
        updatedByMemberId: String? = nil, assignmentEventId: String? = nil
    ) {
        self.traceId = traceId
        self.spanId = spanId
        self.conversationId = conversationId
        self.labels = labels
        self.assigneeMemberIds = assigneeMemberIds
        self.annotatorMemberIds = annotatorMemberIds
        self.commenterMemberIds = commenterMemberIds
        self.hasComment = hasComment
        self.humanCommenterMemberIds = humanCommenterMemberIds
        self.hasHumanComment = hasHumanComment
        self.commentCount = commentCount
        self.latestComment = latestComment
        self.latestCommentMemberId = latestCommentMemberId
        self.latestCommentActorMemberId = latestCommentActorMemberId
        self.latestCommentActorType = latestCommentActorType
        self.updatedAt = updatedAt
        self.updatedByMemberId = updatedByMemberId
        self.assignmentEventId = assignmentEventId
    }

    private enum CodingKeys: String, CodingKey {
        case labels
        case traceId = "trace_id"
        case spanId = "span_id"
        case conversationId = "conversation_id"
        case assigneeMemberIds = "assignee_member_ids"
        case annotatorMemberIds = "annotator_member_ids"
        case commenterMemberIds = "commenter_member_ids"
        case hasComment = "has_comment"
        case humanCommenterMemberIds = "human_commenter_member_ids"
        case hasHumanComment = "has_human_comment"
        case commentCount = "comment_count"
        case latestComment = "latest_comment"
        case latestCommentMemberId = "latest_comment_member_id"
        case latestCommentActorMemberId = "latest_comment_actor_member_id"
        case latestCommentActorType = "latest_comment_actor_type"
        case updatedAt = "updated_at"
        case updatedByMemberId = "updated_by_member_id"
        case assignmentEventId = "assignment_event_id"
    }
}

/// One filter bucket over current annotation state.
public struct AnnotationFacet: Codable, Sendable, Hashable {
    public var dimension: String
    public var value: String
    public var count: Int

    public init(dimension: String, value: String, count: Int) {
        self.dimension = dimension
        self.value = value
        self.count = count
    }
}

/// The previous, current and next annotation around one span in the filtered review order.
public struct AnnotationNavigation: Codable, Sendable, Hashable {
    public var previous: AnnotationState?
    public var current: AnnotationState?
    public var next: AnnotationState?
    public var currentPosition: Int?
    public var totalCount: Int?

    public init(
        previous: AnnotationState? = nil, current: AnnotationState? = nil, next: AnnotationState? = nil, currentPosition: Int? = nil,
        totalCount: Int? = nil
    ) {
        self.previous = previous
        self.current = current
        self.next = next
        self.currentPosition = currentPosition
        self.totalCount = totalCount
    }

    private enum CodingKeys: String, CodingKey {
        case previous, current, next
        case currentPosition = "current_position"
        case totalCount = "total_count"
    }
}

/// Filters for `GET /v1/annotations`. Email filters are resolved to active business members first.
public struct AnnotationListParams: Sendable, Hashable {
    public var annotatedByMemberId: String?
    public var assigneeMemberId: String?
    /// Resolved to `annotatedByMemberId`; do not combine with it.
    public var annotatedByEmail: String?
    /// Resolved to `assigneeMemberId`; do not combine with it.
    public var assignedToEmail: String?
    public var traceId: String?
    public var spanId: String?
    public var conversationId: String?
    public var labels: [String]?
    public var status: AnnotationReviewStatus?
    /// Ask the server for `total_count`.
    public var includeTotal: Bool?
    public var limit: Int?
    public var next: String?

    public init(
        annotatedByMemberId: String? = nil, assigneeMemberId: String? = nil, annotatedByEmail: String? = nil,
        assignedToEmail: String? = nil, traceId: String? = nil, spanId: String? = nil, conversationId: String? = nil,
        labels: [String]? = nil, status: AnnotationReviewStatus? = nil, includeTotal: Bool? = nil,
        limit: Int? = nil, next: String? = nil
    ) {
        self.annotatedByMemberId = annotatedByMemberId
        self.assigneeMemberId = assigneeMemberId
        self.annotatedByEmail = annotatedByEmail
        self.assignedToEmail = assignedToEmail
        self.traceId = traceId
        self.spanId = spanId
        self.conversationId = conversationId
        self.labels = labels
        self.status = status
        self.includeTotal = includeTotal
        self.limit = limit
        self.next = next
    }
}

/// One annotation event: at most one snapshot (labels or reviewers, where empty
/// clears), optionally with a comment, or a standalone comment.
public struct AnnotationMutation: Sendable, Hashable {
    /// Complete label snapshot.
    public var labels: [String]?
    public var comment: String?
    /// Complete reviewer snapshot by member id.
    public var assigneeMemberIds: [String]?
    /// Complete reviewer snapshot by email, resolved to active business members.
    public var reviewerEmails: [String]?

    public init(labels: [String]? = nil, comment: String? = nil, assigneeMemberIds: [String]? = nil, reviewerEmails: [String]? = nil) {
        self.labels = labels
        self.comment = comment
        self.assigneeMemberIds = assigneeMemberIds
        self.reviewerEmails = reviewerEmails
    }

    /// Replace the span's labels.
    public static func labels(_ labels: [String], comment: String? = nil) -> AnnotationMutation {
        AnnotationMutation(labels: labels, comment: comment)
    }

    /// Append a comment.
    public static func comment(_ comment: String) -> AnnotationMutation {
        AnnotationMutation(comment: comment)
    }

    /// Replace the span's reviewers by email.
    public static func reviewers(_ emails: [String], comment: String? = nil) -> AnnotationMutation {
        AnnotationMutation(comment: comment, reviewerEmails: emails)
    }

    /// Replace the span's reviewers by member id.
    public static func assignees(_ memberIds: [String], comment: String? = nil) -> AnnotationMutation {
        AnnotationMutation(comment: comment, assigneeMemberIds: memberIds)
    }
}

/// The outcome of an annotation write.
public struct AnnotationWriteResult: Sendable, Hashable {
    /// The event id (minted by the SDK unless supplied).
    public var eventId: String
    /// False when the write was accepted but not yet readable; refetch once later.
    public var visible: Bool

    public init(eventId: String, visible: Bool) {
        self.eventId = eventId
        self.visible = visible
    }
}

/// A reusable project label.
public struct ProjectLabel: Codable, Sendable, Hashable {
    public var slug: String
    public var color: String?
    public var description: String?
    public var createdAt: Date?
    public var updatedAt: Date?

    public init(slug: String, color: String? = nil, description: String? = nil, createdAt: Date? = nil, updatedAt: Date? = nil) {
        self.slug = slug
        self.color = color
        self.description = description
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case slug, color, description
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Body of `POST /v1/project-labels`.
public struct ProjectLabelCreate: Encodable, Sendable, Hashable {
    public var slug: String
    /// Six-digit hex color such as `#f97316`.
    public var color: String
    public var description: String?

    public init(slug: String, color: String, description: String? = nil) {
        self.slug = slug
        self.color = color
        self.description = description
    }
}

/// Body of `PATCH /v1/project-labels/{slug}`. Slug and color are immutable; nil clears the description.
public struct ProjectLabelUpdate: Encodable, Sendable, Hashable {
    public var description: String?

    public init(description: String?) { self.description = description }

    private enum CodingKeys: String, CodingKey { case description }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(description, forKey: .description)
    }
}

/// Paging and search for `GET /v1/project-labels`.
public struct ProjectLabelListParams: Sendable, Hashable {
    public var search: String?
    public var limit: Int?
    public var next: String?

    public init(search: String? = nil, limit: Int? = nil, next: String? = nil) {
        self.search = search
        self.limit = limit
        self.next = next
    }
}

// MARK: Helpers

private func annotationValidationError(_ message: String, code: String) -> IntrospectionError {
    IntrospectionError(kind: .validation, message: message, status: 422, code: code)
}

/// Mint a time-ordered UUIDv7 for an annotation event.
func makeAnnotationEventId(now: Date = Date()) -> String {
    var generator = SystemRandomNumberGenerator()
    var bytes = (0..<16).map { _ in UInt8.random(in: 0...255, using: &generator) }
    let millis = UInt64(max(0, now.timeIntervalSince1970 * 1000))
    for index in 0..<6 {
        bytes[index] = UInt8((millis >> UInt64(8 * (5 - index))) & 0xff)
    }
    bytes[6] = (bytes[6] & 0x0f) | 0x70
    bytes[8] = (bytes[8] & 0x3f) | 0x80
    let hex = bytes.map { String(format: "%02x", $0) }.joined()
    let chars = Array(hex)
    return [0..<8, 8..<12, 12..<16, 16..<20, 20..<32].map { String(chars[$0]) }.joined(separator: "-")
}

private func normalizedEmail(_ email: String) -> String {
    email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

private func normalizedReviewerEmails(_ emails: [String]) throws -> [String] {
    var seen = Set<String>()
    var normalized: [String] = []
    for email in emails {
        let value = normalizedEmail(email)
        if seen.insert(value).inserted { normalized.append(value) }
    }
    if normalized.isEmpty || normalized.contains(where: \.isEmpty) {
        throw annotationValidationError("At least one non-empty reviewer email is required", code: "invalid_annotation_reviewer_email")
    }
    if normalized.count > 64 {
        throw annotationValidationError("At most 64 reviewer emails are allowed", code: "too_many_annotation_reviewers")
    }
    return normalized
}

/// Resolves the list's email filters once, however many pages are read.
private actor AnnotationFilterResolver {
    private let resolve: @Sendable () async throws -> Query
    private var resolved: Query?

    init(resolve: @escaping @Sendable () async throws -> Query) { self.resolve = resolve }

    func query() async throws -> Query {
        if let resolved { return resolved }
        let query = try await resolve()
        resolved = query
        return query
    }
}

private struct AnnotationCreateBody: Encodable {
    let traceId: String
    let spanId: String
    let eventId: String
    let labels: [String]?
    let comment: String?
    let assigneeMemberIds: [String]?

    private enum CodingKeys: String, CodingKey {
        case labels, comment
        case traceId = "trace_id"
        case spanId = "span_id"
        case eventId = "event_id"
        case assigneeMemberIds = "assignee_member_ids"
    }
}

// MARK: APIs

/// Member-authored span annotations on the Data Plane. Every create appends
/// exactly one event; labels and reviewers are complete snapshots. Reviewer
/// emails resolve through the Control Plane's member list.
public struct AnnotationsAPI: Sendable {
    let controlPlane: HTTPClient
    let dataPlane: HTTPClient

    public init(controlPlane: HTTPClient, dataPlane: HTTPClient) {
        self.controlPlane = controlPlane
        self.dataPlane = dataPlane
    }

    /// List one folded state per annotated span.
    public func list(_ params: AnnotationListParams = AnnotationListParams()) -> Paginator<AnnotationState> {
        let http = dataPlane
        guard params.annotatedByMemberId == nil || params.annotatedByEmail == nil else {
            return Paginator { _ in
                throw annotationValidationError(
                    "Use annotatedByMemberId or annotatedByEmail, not both", code: "conflicting_annotation_annotator_filters"
                )
            }
        }
        guard params.assigneeMemberId == nil || params.assignedToEmail == nil else {
            return Paginator { _ in
                throw annotationValidationError(
                    "Use assigneeMemberId or assignedToEmail, not both", code: "conflicting_annotation_assignee_filters"
                )
            }
        }
        let api = self
        let resolver = AnnotationFilterResolver {
            var annotatedBy = params.annotatedByMemberId
            var assignee = params.assigneeMemberId
            let emails = [params.annotatedByEmail, params.assignedToEmail].compactMap { $0 }
            if !emails.isEmpty {
                let ids = try await api.resolveReviewerMap(emails)
                if let email = params.annotatedByEmail { annotatedBy = ids[normalizedEmail(email)] }
                if let email = params.assignedToEmail { assignee = ids[normalizedEmail(email)] }
            }
            var query = Query()
            query.add("annotated_by_member_id", annotatedBy)
            query.add("assignee_member_id", assignee)
            query.add("trace_id", params.traceId)
            query.add("span_id", params.spanId)
            query.add("conversation_id", params.conversationId)
            query.add("label", params.labels)
            query.add("status", params.status)
            query.add("include_total", params.includeTotal)
            query.add("limit", params.limit)
            return query
        }
        return Paginator(start: params.next) { cursor in
            var query = try await resolver.query()
            query.set("next", cursor)
            return try await http.json("GET", "/v1/annotations", query: query, as: Page<AnnotationState>.self)
        }
    }

    /// Append one annotation event. Pass `eventId` (a UUIDv7) to make a retry idempotent.
    @discardableResult
    public func create(
        _ target: AnnotationTarget, _ mutation: AnnotationMutation, eventId: String? = nil
    ) async throws -> AnnotationWriteResult {
        let snapshots = [mutation.labels != nil, mutation.assigneeMemberIds != nil, mutation.reviewerEmails != nil].filter { $0 }.count
        if snapshots > 1 {
            throw annotationValidationError(
                "At most one of labels, assigneeMemberIds or reviewerEmails per event", code: "invalid_annotation_mutation"
            )
        }
        if let comment = mutation.comment, comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw annotationValidationError("Annotation comment must not be blank", code: "invalid_annotation_mutation")
        }
        if snapshots == 0, mutation.comment == nil {
            throw annotationValidationError("One of labels, comment or reviewers is required", code: "invalid_annotation_mutation")
        }
        var assignees = mutation.assigneeMemberIds
        if let emails = mutation.reviewerEmails {
            assignees = emails.isEmpty ? [] : try await resolveReviewerIds(emails)
        }
        let id = eventId ?? makeAnnotationEventId()
        let body = AnnotationCreateBody(
            traceId: target.traceId, spanId: target.spanId, eventId: id,
            labels: mutation.labels, comment: mutation.comment, assigneeMemberIds: assignees
        )
        let response = try await dataPlane.send("POST", "/v1/annotations", body: .encode(body))
        let echoed = response.headers["x-introspection-event-id"] ?? id
        if response.status == 202 {
            let payload = try? HTTPClient.decode(JSONValue.self, from: response)
            return AnnotationWriteResult(
                eventId: payload?["event_id"]?.stringValue ?? echoed,
                visible: payload?["visible"]?.boolValue ?? false
            )
        }
        return AnnotationWriteResult(eventId: echoed, visible: true)
    }

    /// Annotator, assignee, label and status counts for filter menus.
    public func facets() async throws -> [AnnotationFacet] {
        try await dataPlane.json("GET", "/v1/annotations/facets")
    }

    /// The bounded previous/current/next window around one span in the filtered review order.
    public func navigation(
        _ target: AnnotationTarget,
        annotatedByMemberId: String? = nil,
        assigneeMemberId: String? = nil,
        labels: [String]? = nil,
        status: AnnotationReviewStatus? = nil
    ) async throws -> AnnotationNavigation {
        var query = Query()
        query.add("trace_id", target.traceId)
        query.add("span_id", target.spanId)
        query.add("annotated_by_member_id", annotatedByMemberId)
        query.add("assignee_member_id", assigneeMemberId)
        query.add("label", labels)
        query.add("status", status)
        return try await dataPlane.json("GET", "/v1/annotations/navigation", query: query)
    }

    /// Resolve emails to active business member ids, in order. Throws `.notFound` or `.conflict` (ambiguous).
    public func resolveReviewerIds(_ emails: [String]) async throws -> [String] {
        let requested = try normalizedReviewerEmails(emails)
        let ids = try await resolveReviewerMap(requested)
        return requested.compactMap { ids[$0] }
    }

    /// Resolve emails to a map keyed by normalized (trimmed, lowercased) email.
    func resolveReviewerMap(_ emails: [String]) async throws -> [String: String] {
        let requested = try normalizedReviewerEmails(emails)
        var matches: [String: [String]] = Dictionary(uniqueKeysWithValues: requested.map { ($0, []) })
        let members = MembersAPI(http: controlPlane).list(MemberListParams(memberType: .business, limit: 1000))
        for try await member in members {
            guard member.isDeactivated != true, let email = member.email else { continue }
            matches[normalizedEmail(email)]?.append(member.id)
        }
        var resolved: [String: String] = [:]
        for email in requested {
            let candidates = matches[email] ?? []
            guard let first = candidates.first else {
                throw IntrospectionError(
                    kind: .notFound, message: "No active domain expert found for '\(email)'", status: 404,
                    code: "annotation_reviewer_not_found", body: ["email": .string(email)]
                )
            }
            if candidates.count > 1 {
                throw IntrospectionError(
                    kind: .conflict, message: "Multiple active domain experts found for '\(email)'", status: 409,
                    code: "annotation_reviewer_ambiguous",
                    body: ["email": .string(email), "member_ids": .array(candidates.map(JSONValue.string))]
                )
            }
            resolved[email] = first
        }
        return resolved
    }
}

/// The managed project label catalog annotations use.
public struct ProjectLabelsAPI: Sendable {
    let http: HTTPClient

    public init(http: HTTPClient) { self.http = http }

    /// List labels.
    public func list(_ params: ProjectLabelListParams = ProjectLabelListParams()) -> Paginator<ProjectLabel> {
        var query = Query()
        query.add("search", params.search)
        query.add("limit", params.limit)
        return http.paginate("/v1/project-labels", query: query, start: params.next)
    }

    /// Create a label. The slug is trimmed and the color lowercased.
    public func create(_ body: ProjectLabelCreate) async throws -> ProjectLabel {
        let slug = body.slug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !slug.isEmpty, slug.count <= 128 else {
            throw annotationValidationError("Project label slug must contain 1 to 128 characters", code: "invalid_project_label_slug")
        }
        let color = body.color.lowercased()
        let hex = color.dropFirst()
        guard color.hasPrefix("#"), hex.count == 6, hex.allSatisfy(\.isHexDigit) else {
            throw annotationValidationError(
                "Project label color must be a six-digit hex color such as #f97316", code: "invalid_project_label_color"
            )
        }
        if let description = body.description, description.count > 2000 {
            throw annotationValidationError(
                "Project label description must not exceed 2000 characters", code: "invalid_project_label_description"
            )
        }
        let normalized = ProjectLabelCreate(slug: slug, color: color, description: body.description)
        return try await http.json("POST", "/v1/project-labels", body: .encode(normalized))
    }

    /// Fetch one label.
    public func get(_ slug: String) async throws -> ProjectLabel {
        try await http.json("GET", "/v1/project-labels/\(pathSegment(slug))")
    }

    /// Update a label's description.
    public func update(_ slug: String, _ body: ProjectLabelUpdate) async throws -> ProjectLabel {
        if let description = body.description, description.count > 2000 {
            throw annotationValidationError(
                "Project label description must not exceed 2000 characters", code: "invalid_project_label_description"
            )
        }
        return try await http.json("PATCH", "/v1/project-labels/\(pathSegment(slug))", body: .encode(body))
    }
}

extension IntrospectionClient {
    /// Span annotations (Data Plane), with reviewer emails resolved on the Control Plane.
    public var annotations: AnnotationsAPI { AnnotationsAPI(controlPlane: controlPlane, dataPlane: dataPlane) }

    /// Reusable project labels (Data Plane).
    public var projectLabels: ProjectLabelsAPI { ProjectLabelsAPI(http: dataPlane) }
}
