import Foundation

/// How `/v1/remotes/connect` authenticates.
public struct WebSocketAuthenticationDocs: Codable, Sendable, Hashable {
    public var method: String
    public var description: String
    public var example: String

    public init(method: String, description: String, example: String) {
        self.method = method
        self.description = description
        self.example = example
    }
}

/// One frame of the remote connection's protocol.
public struct WebSocketFrameDocs: Codable, Sendable, Hashable {
    public var frame: String
    public var description: String

    public init(frame: String, description: String) {
        self.frame = frame
        self.description = description
    }
}

/// The frames each side of the remote connection sends.
public struct WebSocketMessageProtocolDocs: Codable, Sendable, Hashable {
    public var remoteToCloud: [WebSocketFrameDocs]
    public var cloudToRemote: [WebSocketFrameDocs]

    public init(remoteToCloud: [WebSocketFrameDocs], cloudToRemote: [WebSocketFrameDocs]) {
        self.remoteToCloud = remoteToCloud
        self.cloudToRemote = cloudToRemote
    }

    private enum CodingKeys: String, CodingKey {
        case remoteToCloud = "remote_to_cloud"
        case cloudToRemote = "cloud_to_remote"
    }
}

/// What a plain `GET /v1/remotes/connect` answers: the WebSocket protocol that route upgrades to.
public struct RemotesConnectDocs: Codable, Sendable, Hashable {
    public var endpoint: String
    public var `protocol`: String
    public var authentication: WebSocketAuthenticationDocs
    public var handshake: [String]
    public var schemaVersion: Int
    public var encoding: String
    public var messageProtocol: WebSocketMessageProtocolDocs

    public init(
        endpoint: String, protocol: String, authentication: WebSocketAuthenticationDocs, handshake: [String], schemaVersion: Int,
        encoding: String, messageProtocol: WebSocketMessageProtocolDocs
    ) {
        self.endpoint = endpoint
        self.protocol = `protocol`
        self.authentication = authentication
        self.handshake = handshake
        self.schemaVersion = schemaVersion
        self.encoding = encoding
        self.messageProtocol = messageProtocol
    }

    private enum CodingKeys: String, CodingKey {
        case endpoint, `protocol`, authentication, handshake, encoding
        case schemaVersion = "schema_version"
        case messageProtocol = "message_protocol"
    }
}

/// The remote connection `introspection dev` attaches over (`/v1/remotes`). The SDK reads its documentation; it does
/// not open the WebSocket, whose frames are the CLI's protocol and which needs a development credential.
public struct RemotesAPI: Sendable {
    let http: HTTPClient

    public init(http: HTTPClient) { self.http = http }

    /// Read the remote connection's protocol.
    public func connectDocs() async throws -> RemotesConnectDocs {
        try await http.json("GET", "/v1/remotes/connect")
    }
}

extension DataPlaneConnection {
    /// The remote connection's protocol.
    public var remotes: RemotesAPI { RemotesAPI(http: dataPlane) }
}
