import Foundation
import IntrospectionSDK

/// The methods the walk reaches that no docs page shows yet.
enum PlatformRoutes {
    /// A person's answer to what an agent asked for.
    static func decideApproval(connection: DataPlaneConnection, approvalId: String, memberId: String) async throws -> Approval {
        try await connection.approvals.decide(approvalId, ApprovalDecision(status: .denied, decidedBy: .member(memberId)))
    }

    /// An upstream API the runtime's egress may call, with the header it adds from a credential.
    static func createEndpoint(client: IntrospectionClient, project: String) async throws -> Endpoint {
        try await client.endpoints.create(
            EndpointCreate(name: "billing", host: "billing.example.com", headers: ["Authorization": "Bearer ${BILLING_TOKEN}"], kind: .api),
            project: project)
    }

    /// The Git provider token of the runtime a sandbox runs on: only that sandbox's session gets one.
    static func repositoryToken(client: IntrospectionClient, repositoryId: String) async throws -> RepositoryAccessGrant {
        try await client.repositories.accessToken(repositoryId)
    }

    /// The frames a remote exchanges with the cloud at `/v1/remotes/connect`.
    static func remoteProtocol(connection: DataPlaneConnection) async throws -> [String] {
        let docs = try await connection.remotes.connectDocs()
        return docs.messageProtocol.remoteToCloud.map(\.frame)
    }

    /// The connections held on one connector, the project's own grant among them.
    static func connectionsOnConnector(client: IntrospectionClient, connectorId: String) async throws -> [AppConnection] {
        try await client.connections.list(AppConnectionListParams(connectorId: connectorId)).collect()
    }
}
