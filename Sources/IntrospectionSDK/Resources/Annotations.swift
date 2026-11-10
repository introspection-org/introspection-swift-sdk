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

/// One comment on an annotated span.
public struct AnnotationComment: Codable, Sendable, Hashable {
    public var eventId: String
    public var comment: String
    /// The author.
    public var memberId: String
    public var actorMemberId: String?
    /// The kind of actor that wrote on the member's behalf, such as `agent`.
    public var actorMemberType: String?
    public var createdAt: Date?

    public init(
        eventId: String, comment: String, memberId: String, actorMemberId: String? = nil, actorMemberType: String? = nil,
        createdAt: Date? = nil
    ) {
        self.eventId = eventId
        self.comment = comment
        self.memberId = memberId
        self.actorMemberId = actorMemberId
        self.actorMemberType = actorMemberType
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case comment
        case eventId = "event_id"
        case memberId = "member_id"
        case actorMemberId = "actor_member_id"
        case actorMemberType = "actor_member_type"
        case createdAt = "created_at"
    }
}

/// Current labels, assignees and reviewers folded from one span's annotation events.
public struct AnnotationState: Codable, Sendable, Hashable {
    public var traceId: String
    public var spanId: String
    public var conversationId: String?
    public var labels: [String]?
    public var assigneeMemberIds: [String]?
    /// Members whose comment completed a review.
    public var reviewerMemberIds: [String]?
    public var commentCount: Int?
    public var updatedAt: Date?
    public var updatedByMemberId: String?
    public var assignmentEventId: String?
    /// Every comment on the span, oldest first, when the list was asked for `include: [.comments]`; nil otherwise.
    public var comments: [AnnotationComment]?

    public init(
        traceId: String, spanId: String, conversationId: String? = nil, labels: [String]? = nil,
        assigneeMemberIds: [String]? = nil, reviewerMemberIds: [String]? = nil, commentCount: Int? = nil,
        updatedAt: Date? = nil, updatedByMemberId: String? = nil, assignmentEventId: String? = nil,
        comments: [AnnotationComment]? = nil
    ) {
        self.traceId = traceId
        self.spanId = spanId
        self.conversationId = conversationId
        self.labels = labels
        self.assigneeMemberIds = assigneeMemberIds
        self.reviewerMemberIds = reviewerMemberIds
        self.commentCount = commentCount
        self.updatedAt = updatedAt
        self.updatedByMemberId = updatedByMemberId
        self.assignmentEventId = assignmentEventId
        self.comments = comments
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        traceId = try container.decode(String.self, forKey: .traceId)
        spanId = try container.decode(String.self, forKey: .spanId)
        conversationId = try container.decodeIfPresent(String.self, forKey: .conversationId)
        labels = try container.decodeIfPresent([String].self, forKey: .labels)
        assigneeMemberIds = try container.decodeIfPresent([String].self, forKey: .assigneeMemberIds)
        // A data plane that predates the rename still sends `human_commenter_member_ids`.
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        let reviewers = try container.decodeIfPresent([String].self, forKey: .reviewerMemberIds)
        reviewerMemberIds = try reviewers ?? legacy.decodeIfPresent([String].self, forKey: .humanCommenterMemberIds)
        commentCount = try container.decodeIfPresent(Int.self, forKey: .commentCount)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        updatedByMemberId = try container.decodeIfPresent(String.self, forKey: .updatedByMemberId)
        assignmentEventId = try container.decodeIfPresent(String.self, forKey: .assignmentEventId)
        comments = try container.decodeIfPresent([AnnotationComment].self, forKey: .comments)
    }

    private enum CodingKeys: String, CodingKey {
        case labels, comments
        case traceId = "trace_id"
        case spanId = "span_id"
        case conversationId = "conversation_id"
        case assigneeMemberIds = "assignee_member_ids"
        case reviewerMemberIds = "reviewer_member_ids"
        case commentCount = "comment_count"
        case updatedAt = "updated_at"
        case updatedByMemberId = "updated_by_member_id"
        case assignmentEventId = "assignment_event_id"
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case humanCommenterMemberIds = "human_commenter_member_ids"
    }
}

/// One filter bucket over current annotation state. The `label` and `review_queue` buckets also
/// summarize their dataset: its conversations, comments, reviewers and last update.
public struct AnnotationFacet: Codable, Sendable, Hashable {
    public var dimension: String
    public var value: String
    public var count: Int
    public var conversationCount: Int?
    public var commentCount: Int?
    public var reviewerMemberIds: [String]?
    public var updatedAt: Date?

    public init(
        dimension: String, value: String, count: Int, conversationCount: Int? = nil, commentCount: Int? = nil,
        reviewerMemberIds: [String]? = nil, updatedAt: Date? = nil
    ) {
        self.dimension = dimension
        self.value = value
        self.count = count
        self.conversationCount = conversationCount
        self.commentCount = commentCount
        self.reviewerMemberIds = reviewerMemberIds
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case dimension, value, count
        case conversationCount = "conversation_count"
        case commentCount = "comment_count"
        case reviewerMemberIds = "reviewer_member_ids"
        case updatedAt = "updated_at"
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
/// Optional expansions of a listed annotation row (repeated `include`).
public struct AnnotationInclude: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }

    /// Every comment on the span, oldest first, as the row's `comments`.
    public static let comments: AnnotationInclude = "comments"
}

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
    public var include: [AnnotationInclude]?

    public init(
        annotatedByMemberId: String? = nil, assigneeMemberId: String? = nil, annotatedByEmail: String? = nil,
        assignedToEmail: String? = nil, traceId: String? = nil, spanId: String? = nil, conversationId: String? = nil,
        labels: [String]? = nil, status: AnnotationReviewStatus? = nil, includeTotal: Bool? = nil,
        limit: Int? = nil, next: String? = nil, include: [AnnotationInclude]? = nil
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
        self.include = include
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

// MARK: Helpers

private func annotationValidationError(_ message: String, code: String) -> IntrospectionError {
    IntrospectionError(kind: .validation, message: message, status: 422, code: code)
}

/// Mint a time-ordered UUIDv7 (annotation event ids, issue request ids).
func makeUUIDv7(now: Date = Date()) -> String {
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

    /// List one folded state per annotated span. `include: [.comments]` loads each row's `comments`.
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
            query.add("include", params.include)
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
        let id = eventId ?? makeUUIDv7()
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

extension IntrospectionClient {
    /// Span annotations (Data Plane), with reviewer emails resolved on the Control Plane.
    public var annotations: AnnotationsAPI { AnnotationsAPI(controlPlane: controlPlane, dataPlane: dataPlane) }
}
