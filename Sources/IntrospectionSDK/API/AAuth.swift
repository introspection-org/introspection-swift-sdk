import Foundation

// MARK: Models

/// One update an agent logged under a mission.
public struct MissionLogEntry: Codable, Sendable, Hashable {
    public var at: Date?
    public var entry: String?

    public init(at: Date? = nil, entry: String? = nil) {
        self.at = at
        self.entry = entry
    }
}

/// An AAuth mission: what a person asked an agent to do, the resources it may reach and its budget.
public struct Mission: Codable, Sendable, Hashable {
    public var id: String
    public var orgId: String?
    public var projectId: String?
    /// The mission's text, as hashed (`s256`) and returned to the agent.
    public var mission: String?
    public var s256: String?
    public var agentId: String?
    /// The person the agent acts for.
    public var memberId: String?
    public var resources: [String]?
    public var budget: JSONObject?
    public var spent: Int?
    public var log: [MissionLogEntry]?
    public var expiresAt: Date?
    public var completedAt: Date?
    public var createdAt: Date?
    public var updatedAt: Date?

    public init(
        id: String, orgId: String? = nil, projectId: String? = nil, mission: String? = nil, s256: String? = nil, agentId: String? = nil,
        memberId: String? = nil, resources: [String]? = nil, budget: JSONObject? = nil, spent: Int? = nil, log: [MissionLogEntry]? = nil,
        expiresAt: Date? = nil, completedAt: Date? = nil, createdAt: Date? = nil, updatedAt: Date? = nil
    ) {
        self.id = id
        self.orgId = orgId
        self.projectId = projectId
        self.mission = mission
        self.s256 = s256
        self.agentId = agentId
        self.memberId = memberId
        self.resources = resources
        self.budget = budget
        self.spent = spent
        self.log = log
        self.expiresAt = expiresAt
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, mission, s256, resources, budget, spent, log
        case orgId = "org_id"
        case projectId = "project_id"
        case agentId = "agent_id"
        case memberId = "member_id"
        case expiresAt = "expires_at"
        case completedAt = "completed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// What an approval decides.
public struct ApprovalKind: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let mission: ApprovalKind = "mission"
    public static let authToken: ApprovalKind = "auth_token"
    public static let completion: ApprovalKind = "completion"
}

/// Where an approval stands.
public struct ApprovalStatus: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let pending: ApprovalStatus = "pending"
    public static let approved: ApprovalStatus = "approved"
    public static let denied: ApprovalStatus = "denied"
}

/// A decision the AAuth Person Server waits on; the customer's app makes it.
public struct Approval: Codable, Sendable, Hashable {
    public var id: String
    public var orgId: String?
    public var projectId: String?
    public var kind: ApprovalKind?
    public var status: ApprovalStatus?
    public var agentId: String?
    /// The person the agent acts for.
    public var memberId: String?
    public var missionId: String?
    /// The mission's description, the booking's scope, or the completion summary.
    public var description: String?
    public var resource: String?
    /// What the resource asks for, when it asks for an auth token.
    public var budget: JSONObject?
    /// The resource's own description of the request.
    public var summary: String?
    public var decidedBudget: JSONObject?
    public var decidedByMemberId: String?
    public var decidedAt: Date?
    public var expiresAt: Date?
    public var createdAt: Date?
    public var updatedAt: Date?

    // jscpd:ignore-start: memberwise init of a public type; the assignments cannot be shared
    public init(
        id: String, orgId: String? = nil, projectId: String? = nil, kind: ApprovalKind? = nil, status: ApprovalStatus? = nil,
        agentId: String? = nil, memberId: String? = nil, missionId: String? = nil, description: String? = nil, resource: String? = nil,
        budget: JSONObject? = nil, summary: String? = nil, decidedBudget: JSONObject? = nil, decidedByMemberId: String? = nil,
        decidedAt: Date? = nil, expiresAt: Date? = nil, createdAt: Date? = nil, updatedAt: Date? = nil
    ) {
        self.id = id
        self.orgId = orgId
        self.projectId = projectId
        self.kind = kind
        self.status = status
        self.agentId = agentId
        self.memberId = memberId
        self.missionId = missionId
        self.description = description
        self.resource = resource
        self.budget = budget
        self.summary = summary
        self.decidedBudget = decidedBudget
        self.decidedByMemberId = decidedByMemberId
        self.decidedAt = decidedAt
        self.expiresAt = expiresAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    // jscpd:ignore-end

    private enum CodingKeys: String, CodingKey {
        case id, kind, status, description, resource, budget, summary
        case orgId = "org_id"
        case projectId = "project_id"
        case agentId = "agent_id"
        case memberId = "member_id"
        case missionId = "mission_id"
        case decidedBudget = "decided_budget"
        case decidedByMemberId = "decided_by_member_id"
        case decidedAt = "decided_at"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// The approver as the customer knows them: the identity a runner takes, less a conversation. Set one of the two.
public struct ApproverIdentity: Encodable, Sendable, Hashable {
    public var userId: String?
    public var anonymousId: String?

    public init(userId: String? = nil, anonymousId: String? = nil) {
        self.userId = userId
        self.anonymousId = anonymousId
    }

    private enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case anonymousId = "anonymous_id"
    }
}

/// Who decides an approval: a project member or the customer's own identity.
public enum ApprovalDecider: Encodable, Sendable, Hashable {
    case member(String)
    case identity(ApproverIdentity)

    private enum CodingKeys: String, CodingKey {
        case identity
        case memberId = "member_id"
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .member(id): try container.encode(id, forKey: .memberId)
        case let .identity(identity): try container.encode(identity, forKey: .identity)
        }
    }
}

/// A budget granted by an approval.
public struct ApprovalBudget: Encodable, Sendable, Hashable {
    public var amount: Int
    public var unit: String
    public var decimals: Int

    public init(amount: Int, unit: String, decimals: Int) {
        self.amount = amount
        self.unit = unit
        self.decimals = decimals
    }
}

/// Body of `PATCH /v1/aauth/approvals/{id}`.
public struct ApprovalDecision: Encodable, Sendable, Hashable {
    /// ``ApprovalStatus/approved`` or ``ApprovalStatus/denied``.
    public var status: ApprovalStatus
    public var decidedBy: ApprovalDecider
    /// Grants less than the agent asked for.
    public var budget: ApprovalBudget?

    public init(status: ApprovalStatus, decidedBy: ApprovalDecider, budget: ApprovalBudget? = nil) {
        self.status = status
        self.decidedBy = decidedBy
        self.budget = budget
    }

    private enum CodingKeys: String, CodingKey {
        case status, budget
        case decidedBy = "decided_by"
    }
}

/// Filters for `GET /v1/aauth/missions`.
public struct MissionListParams: Sendable, Hashable {
    /// Only missions for this person.
    public var memberId: String?
    public var limit: Int?
    public var next: String?

    public init(memberId: String? = nil, limit: Int? = nil, next: String? = nil) {
        self.memberId = memberId
        self.limit = limit
        self.next = next
    }
}

/// Filters for `GET /v1/aauth/approvals`.
public struct ApprovalListParams: Sendable, Hashable {
    /// `pending` lists only the unexpired ones.
    public var status: [ApprovalStatus]?
    public var kind: ApprovalKind?
    /// Only approvals for this person.
    public var memberId: String?
    public var decidedByMemberId: String?
    public var missionId: String?
    public var limit: Int?
    public var next: String?

    public init(
        status: [ApprovalStatus]? = nil, kind: ApprovalKind? = nil, memberId: String? = nil, decidedByMemberId: String? = nil,
        missionId: String? = nil, limit: Int? = nil, next: String? = nil
    ) {
        self.status = status
        self.kind = kind
        self.memberId = memberId
        self.decidedByMemberId = decidedByMemberId
        self.missionId = missionId
        self.limit = limit
        self.next = next
    }
}

// MARK: APIs

/// Read-only AAuth missions (`/v1/aauth/missions`).
public struct MissionsAPI: Sendable {
    let http: HTTPClient

    public init(http: HTTPClient) { self.http = http }

    /// List the project's missions, newest first.
    public func list(_ params: MissionListParams = MissionListParams()) -> Paginator<Mission> {
        var query = Query()
        query.add("member_id", params.memberId)
        query.add("limit", params.limit)
        return http.paginate("/v1/aauth/missions", query: query, start: params.next)
    }

    /// Fetch one mission.
    public func get(_ id: String) async throws -> Mission {
        try await http.json("GET", "/v1/aauth/missions/\(pathSegment(id))")
    }
}

/// AAuth approvals (`/v1/aauth/approvals`).
public struct ApprovalsAPI: Sendable {
    let http: HTTPClient

    public init(http: HTTPClient) { self.http = http }

    /// List the project's approvals, newest first.
    public func list(_ params: ApprovalListParams = ApprovalListParams()) -> Paginator<Approval> {
        var query = Query()
        query.add("status", params.status)
        query.add("kind", params.kind)
        query.add("member_id", params.memberId)
        query.add("decided_by_member_id", params.decidedByMemberId)
        query.add("mission_id", params.missionId)
        query.add("limit", params.limit)
        return http.paginate("/v1/aauth/approvals", query: query, start: params.next)
    }

    /// Fetch one approval.
    public func get(_ id: String) async throws -> Approval {
        try await http.json("GET", "/v1/aauth/approvals/\(pathSegment(id))")
    }

    /// Record the approver's answer and return the decided approval; approving does what the agent asked.
    public func decide(_ id: String, _ decision: ApprovalDecision) async throws -> Approval {
        try await http.json("PATCH", "/v1/aauth/approvals/\(pathSegment(id))", body: .encode(decision))
    }
}

extension DataPlaneConnection {
    /// AAuth missions people gave their agents.
    public var missions: MissionsAPI { MissionsAPI(http: dataPlane) }
    /// AAuth approvals waiting on, or decided by, people.
    public var approvals: ApprovalsAPI { ApprovalsAPI(http: dataPlane) }
}
