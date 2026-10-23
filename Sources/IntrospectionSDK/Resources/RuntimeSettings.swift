import Foundation

// MARK: Shared

/// Filters for `GET /v1/credentials` and `GET /v1/variables`.
public struct RuntimeSettingListParams: Sendable, Hashable {
    /// The project's slug or id, when the credential does not name one.
    public var project: String?
    public var runtimeId: String?
    /// A runtime slug.
    public var runtime: String?
    public var environment: RuntimeEnvironment?
    public var limit: Int?
    public var next: String?

    public init(
        project: String? = nil, runtimeId: String? = nil, runtime: String? = nil, environment: RuntimeEnvironment? = nil,
        limit: Int? = nil, next: String? = nil
    ) {
        self.project = project
        self.runtimeId = runtimeId
        self.runtime = runtime
        self.environment = environment
        self.limit = limit
        self.next = next
    }

    var filters: Query {
        var query = Query()
        query.add("runtime_id", runtimeId)
        query.add("runtime", runtime)
        query.add("environment", environment)
        return query
    }
}

// MARK: Credentials

/// A secret a project's runtimes read. Write-only: reads report whether one is set and a display hint.
public struct Credential: Codable, Sendable, Hashable {
    public var id: String
    public var orgId: String?
    public var projectId: String?
    public var name: String?
    /// Set when the credential applies to one runtime.
    public var runtimeId: String?
    /// Set when the credential applies to one runtime group.
    public var runtimeGroupId: String?
    /// Nil applies to every lane.
    public var environment: RuntimeEnvironment?
    public var hasSecret: Bool?
    public var secretDisplay: String?
    public var secretSetAt: Date?
    public var createdByMemberId: String?
    public var createdAt: Date?
    public var updatedAt: Date?

    /// A value with only its id set; decoding fills the rest.
    public init(id: String) { self.id = id }

    private enum CodingKeys: String, CodingKey {
        case id, name, environment
        case orgId = "org_id"
        case projectId = "project_id"
        case runtimeId = "runtime_id"
        case runtimeGroupId = "runtime_group_id"
        case hasSecret = "has_secret"
        case secretDisplay = "secret_display"
        case secretSetAt = "secret_set_at"
        case createdByMemberId = "created_by_member_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Body of `POST /v1/credentials`, which upserts on name and scope. With neither runtime nor runtime group
/// set, the credential is project-wide.
public struct CredentialCreate: Encodable, Sendable, Hashable {
    public var name: String
    public var secret: Secret
    public var runtimeId: String?
    public var runtimeGroupId: String?
    public var environment: RuntimeEnvironment?

    public init(
        name: String, secret: Secret, runtimeId: String? = nil, runtimeGroupId: String? = nil, environment: RuntimeEnvironment? = nil
    ) {
        self.name = name
        self.secret = secret
        self.runtimeId = runtimeId
        self.runtimeGroupId = runtimeGroupId
        self.environment = environment
    }

    private enum CodingKeys: String, CodingKey {
        case name, secret, environment
        case runtimeId = "runtime_id"
        case runtimeGroupId = "runtime_group_id"
    }
}

/// Body of `PATCH /v1/credentials/{id}`. A `secret` replaces the stored one.
public struct CredentialUpdate: Encodable, Sendable, Hashable {
    public var name: String?
    public var secret: Secret?
    public var runtimeId: String?
    public var runtimeGroupId: String?
    public var environment: RuntimeEnvironment?

    public init(
        name: String? = nil, secret: Secret? = nil, runtimeId: String? = nil, runtimeGroupId: String? = nil,
        environment: RuntimeEnvironment? = nil
    ) {
        self.name = name
        self.secret = secret
        self.runtimeId = runtimeId
        self.runtimeGroupId = runtimeGroupId
        self.environment = environment
    }

    private enum CodingKeys: String, CodingKey {
        case name, secret, environment
        case runtimeId = "runtime_id"
        case runtimeGroupId = "runtime_group_id"
    }
}

/// Runtime credentials (`/v1/credentials`). Needs an org credential carrying `credentials:*`.
public struct CredentialsAPI: Sendable {
    let collection: ProjectScopedCollection

    public init(http: HTTPClient) { collection = ProjectScopedCollection(http: http, path: "/v1/credentials") }

    /// List the project's credentials.
    public func list(_ params: RuntimeSettingListParams = RuntimeSettingListParams()) -> Paginator<Credential> {
        collection.list(project: params.project, limit: params.limit, next: params.next, filters: params.filters)
    }

    // jscpd:ignore-start: one-line public wrappers over ProjectScopedCollection, as ApplicationsAPI has; sharing them
    // would need a generic public API
    /// Fetch one credential, without its secret.
    public func get(_ credentialId: String, project: String? = nil) async throws -> Credential {
        try await collection.get(credentialId, project: project)
    }

    /// Store a credential.
    public func create(_ body: CredentialCreate, project: String? = nil) async throws -> Credential {
        try await collection.create(body, project: project)
    }

    /// Update a credential; set `secret` to rotate it.
    public func update(_ credentialId: String, _ body: CredentialUpdate, project: String? = nil) async throws -> Credential {
        try await collection.update(credentialId, body, project: project)
    }

    /// Delete a credential.
    public func delete(_ credentialId: String, project: String? = nil) async throws {
        try await collection.delete(credentialId, project: project)
    }
    // jscpd:ignore-end
}

// MARK: Variables

/// Whether a variable holds a value or names a credential.
public struct VariableKind: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    /// A plain value, returned on read.
    public static let value: VariableKind = "value"
    /// The name of a credential whose secret the runtime reads.
    public static let credential: VariableKind = "credential"
}

/// An environment variable a project's runtimes read, scoped like a ``Credential``.
public struct Variable: Codable, Sendable, Hashable {
    public var id: String
    public var orgId: String?
    public var projectId: String?
    public var name: String?
    public var kind: VariableKind?
    public var value: String?
    public var runtimeId: String?
    public var runtimeGroupId: String?
    /// Nil applies to every lane.
    public var environment: RuntimeEnvironment?
    public var createdByMemberId: String?
    public var createdAt: Date?
    public var updatedAt: Date?

    /// A value with only its id set; decoding fills the rest.
    public init(id: String) { self.id = id }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, value, environment
        case orgId = "org_id"
        case projectId = "project_id"
        case runtimeId = "runtime_id"
        case runtimeGroupId = "runtime_group_id"
        case createdByMemberId = "created_by_member_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Body of `POST /v1/variables`, which upserts on name and scope.
public struct VariableCreate: Encodable, Sendable, Hashable {
    public var name: String
    /// Defaults to `value`.
    public var kind: VariableKind?
    public var value: String?
    public var runtimeId: String?
    public var runtimeGroupId: String?
    public var environment: RuntimeEnvironment?

    public init(
        name: String, value: String? = nil, kind: VariableKind? = nil, runtimeId: String? = nil, runtimeGroupId: String? = nil,
        environment: RuntimeEnvironment? = nil
    ) {
        self.name = name
        self.value = value
        self.kind = kind
        self.runtimeId = runtimeId
        self.runtimeGroupId = runtimeGroupId
        self.environment = environment
    }

    private enum CodingKeys: String, CodingKey {
        case name, kind, value, environment
        case runtimeId = "runtime_id"
        case runtimeGroupId = "runtime_group_id"
    }
}

/// Body of `PATCH /v1/variables/{id}`. A nil field is left untouched.
public struct VariableUpdate: Encodable, Sendable, Hashable {
    public var name: String?
    public var kind: VariableKind?
    public var value: String?
    public var runtimeId: String?
    public var runtimeGroupId: String?
    public var environment: RuntimeEnvironment?

    public init(
        name: String? = nil, value: String? = nil, kind: VariableKind? = nil, runtimeId: String? = nil,
        runtimeGroupId: String? = nil, environment: RuntimeEnvironment? = nil
    ) {
        self.name = name
        self.value = value
        self.kind = kind
        self.runtimeId = runtimeId
        self.runtimeGroupId = runtimeGroupId
        self.environment = environment
    }

    private enum CodingKeys: String, CodingKey {
        case name, kind, value, environment
        case runtimeId = "runtime_id"
        case runtimeGroupId = "runtime_group_id"
    }
}

/// Runtime environment variables (`/v1/variables`). There is no read-one route. Needs an org credential
/// carrying `variables:*`.
public struct VariablesAPI: Sendable {
    let collection: ProjectScopedCollection

    public init(http: HTTPClient) { collection = ProjectScopedCollection(http: http, path: "/v1/variables") }

    /// List the project's variables.
    public func list(_ params: RuntimeSettingListParams = RuntimeSettingListParams()) -> Paginator<Variable> {
        collection.list(project: params.project, limit: params.limit, next: params.next, filters: params.filters)
    }

    /// Set a variable.
    public func create(_ body: VariableCreate, project: String? = nil) async throws -> Variable {
        try await collection.create(body, project: project)
    }

    /// Update a variable.
    public func update(_ variableId: String, _ body: VariableUpdate, project: String? = nil) async throws -> Variable {
        try await collection.update(variableId, body, project: project)
    }

    /// Delete a variable.
    public func delete(_ variableId: String, project: String? = nil) async throws {
        try await collection.delete(variableId, project: project)
    }
}

extension IntrospectionClient {
    /// Secrets the project's runtimes read. Not the client's own auth: that is `configuration`.
    public var credentials: CredentialsAPI { CredentialsAPI(http: controlPlane) }

    /// Environment variables the project's runtimes read.
    public var variables: VariablesAPI { VariablesAPI(http: controlPlane) }
}
