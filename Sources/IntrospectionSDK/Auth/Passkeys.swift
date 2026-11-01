import Foundation

// MARK: Errors

/// Passkey sign-in or registration could not run, so an app should fall back to
/// the email code: there is no passkey, the user cancelled, the device cannot, or
/// the platform has passkeys turned off.
public struct PasskeyUnavailable: Error, Sendable {
    public enum Reason: String, Sendable, Hashable {
        /// The platform has passkeys turned off.
        case disabled
        /// The device has no passkey for this account.
        case noCredential
        /// The user dismissed the passkey sheet.
        case canceled
        /// The device or app cannot use passkeys (for example, no associated domain).
        case notSupported
    }

    public var reason: Reason
    public var underlying: (any Error)?

    public init(_ reason: Reason, underlying: (any Error)? = nil) {
        self.reason = reason
        self.underlying = underlying
    }
}

// MARK: Models

/// A passkey sign-in challenge from `POST /v1/oauth/passkey/challenge`. Single use.
public struct PasskeyChallenge: Decodable, Sendable, Hashable {
    public var challengeId: String
    public var options: PasskeyRequestOptions

    public init(challengeId: String, options: PasskeyRequestOptions) {
        self.challengeId = challengeId
        self.options = options
    }

    enum CodingKeys: String, CodingKey {
        case challengeId = "challenge_id"
        case options = "public_key_credential_request_options"
    }
}

/// WebAuthn `PublicKeyCredentialRequestOptions`. Byte fields arrive as base64url or base64.
public struct PasskeyRequestOptions: Decodable, Sendable, Hashable {
    public var challenge: Data
    public var relyingPartyID: String?
    /// Empty when the email has no passkey: no credential answers the challenge.
    public var allowedCredentialIDs: [Data]
    /// `required`, `preferred` or `discouraged`.
    public var userVerification: String?
    /// Milliseconds.
    public var timeout: Int?

    public init(
        challenge: Data, relyingPartyID: String? = nil, allowedCredentialIDs: [Data] = [], userVerification: String? = nil,
        timeout: Int? = nil
    ) {
        self.challenge = challenge
        self.relyingPartyID = relyingPartyID
        self.allowedCredentialIDs = allowedCredentialIDs
        self.userVerification = userVerification
        self.timeout = timeout
    }

    enum CodingKeys: String, CodingKey {
        case challenge, timeout, userVerification
        case relyingPartyID = "rpId"
        case allowCredentials
    }

    public init(from decoder: any Decoder) throws {
        let container = try WebAuthnJSON.publicKey(decoder, CodingKeys.self)
        challenge = try WebAuthnJSON.bytes(container, .challenge)
        relyingPartyID = try container.decodeIfPresent(String.self, forKey: .relyingPartyID)
        let descriptors = try container.decodeIfPresent([WebAuthnJSON.Descriptor].self, forKey: .allowCredentials) ?? []
        allowedCredentialIDs = descriptors.map(\.id)
        userVerification = try container.decodeIfPresent(String.self, forKey: .userVerification)
        timeout = try container.decodeIfPresent(Int.self, forKey: .timeout)
    }
}

/// WebAuthn `PublicKeyCredentialCreationOptions`, as much of it as a platform authenticator needs.
public struct PasskeyCreationOptions: Decodable, Sendable, Hashable {
    public var challenge: Data
    public var relyingPartyID: String
    public var relyingPartyName: String?
    public var userID: Data
    public var userName: String
    public var userDisplayName: String?
    /// Milliseconds.
    public var timeout: Int?

    public init(
        challenge: Data, relyingPartyID: String, userID: Data, userName: String, relyingPartyName: String? = nil,
        userDisplayName: String? = nil, timeout: Int? = nil
    ) {
        self.challenge = challenge
        self.relyingPartyID = relyingPartyID
        self.relyingPartyName = relyingPartyName
        self.userID = userID
        self.userName = userName
        self.userDisplayName = userDisplayName
        self.timeout = timeout
    }

    enum CodingKeys: String, CodingKey { case challenge, rp, user, timeout }

    private struct RelyingParty: Decodable {
        let id: String
        let name: String?
    }

    private struct User: Decodable {
        let id: String
        let name: String
        let displayName: String?
    }

    public init(from decoder: any Decoder) throws {
        let container = try WebAuthnJSON.publicKey(decoder, CodingKeys.self)
        challenge = try WebAuthnJSON.bytes(container, .challenge)
        let rp = try container.decode(RelyingParty.self, forKey: .rp)
        let user = try container.decode(User.self, forKey: .user)
        guard let userID = OAuthBase64URL.decode(user.id) else {
            throw DecodingError.dataCorruptedError(forKey: .user, in: container, debugDescription: "user.id is not base64")
        }
        relyingPartyID = rp.id
        relyingPartyName = rp.name
        self.userID = userID
        userName = user.name
        userDisplayName = user.displayName
        timeout = try container.decodeIfPresent(Int.self, forKey: .timeout)
    }
}

/// A started registration from `POST /v1/passkeys`: the device signs `options`.
public struct PasskeyRegistration: Decodable, Sendable, Hashable {
    public var id: String
    public var name: String?
    public var options: PasskeyCreationOptions

    public init(id: String, options: PasskeyCreationOptions, name: String? = nil) {
        self.id = id
        self.options = options
        self.name = name
    }

    enum CodingKeys: String, CodingKey {
        case id, name
        case options = "public_key_credential_creation_options"
    }
}

/// A passkey's state as the platform reports it.
public struct PasskeyState: RawRepresentable, Codable, Sendable, Hashable {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Returned when a registration finishes.
    public static let active = PasskeyState(rawValue: "active")
    public static let ready = PasskeyState(rawValue: "AUTH_FACTOR_STATE_READY")
    public static let notReady = PasskeyState(rawValue: "AUTH_FACTOR_STATE_NOT_READY")
}

/// One of the signed-in member's passkeys.
public struct Passkey: Codable, Sendable, Hashable {
    public var id: String
    public var name: String?
    public var state: PasskeyState?

    public init(id: String, name: String? = nil, state: PasskeyState? = nil) {
        self.id = id
        self.name = name
        self.state = state
    }
}

/// A WebAuthn assertion from the authenticator, sent as base64url JSON.
public struct PasskeyAssertion: Encodable, Sendable, Hashable {
    public var credentialID: Data
    public var clientDataJSON: Data
    public var authenticatorData: Data
    public var signature: Data
    public var userHandle: Data?

    public init(credentialID: Data, clientDataJSON: Data, authenticatorData: Data, signature: Data, userHandle: Data? = nil) {
        self.credentialID = credentialID
        self.clientDataJSON = clientDataJSON
        self.authenticatorData = authenticatorData
        self.signature = signature
        self.userHandle = userHandle
    }

    public func encode(to encoder: any Encoder) throws {
        var response: [String: String] = [
            "clientDataJSON": OAuthBase64URL.encode(clientDataJSON),
            "authenticatorData": OAuthBase64URL.encode(authenticatorData),
            "signature": OAuthBase64URL.encode(signature),
        ]
        if let userHandle { response["userHandle"] = OAuthBase64URL.encode(userHandle) }
        try WebAuthnJSON.Credential(id: credentialID, response: response).encode(to: encoder)
    }
}

/// A WebAuthn attestation from the authenticator, sent as base64url JSON.
public struct PasskeyAttestation: Encodable, Sendable, Hashable {
    public var credentialID: Data
    public var clientDataJSON: Data
    public var attestationObject: Data

    public init(credentialID: Data, clientDataJSON: Data, attestationObject: Data) {
        self.credentialID = credentialID
        self.clientDataJSON = clientDataJSON
        self.attestationObject = attestationObject
    }

    public func encode(to encoder: any Encoder) throws {
        let response = [
            "clientDataJSON": OAuthBase64URL.encode(clientDataJSON),
            "attestationObject": OAuthBase64URL.encode(attestationObject),
        ]
        try WebAuthnJSON.Credential(id: credentialID, response: response).encode(to: encoder)
    }
}

/// WebAuthn JSON helpers: options may be wrapped in `publicKey`, and bytes may be base64url or base64.
enum WebAuthnJSON {
    struct Descriptor: Decodable {
        let id: Data

        enum CodingKeys: String, CodingKey { case id }

        init(from decoder: any Decoder) throws {
            id = try WebAuthnJSON.bytes(try decoder.container(keyedBy: CodingKeys.self), .id)
        }
    }

    struct Credential: Encodable {
        let id: Data
        let response: [String: String]

        enum CodingKeys: String, CodingKey { case id, rawId, type, response }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            let encoded = OAuthBase64URL.encode(id)
            try container.encode(encoded, forKey: .id)
            try container.encode(encoded, forKey: .rawId)
            try container.encode("public-key", forKey: .type)
            try container.encode(response, forKey: .response)
        }
    }

    private enum Wrapper: String, CodingKey { case publicKey }

    static func publicKey<Key: CodingKey>(_ decoder: any Decoder, _: Key.Type) throws -> KeyedDecodingContainer<Key> {
        let wrapper = try decoder.container(keyedBy: Wrapper.self)
        if wrapper.contains(.publicKey) {
            return try wrapper.nestedContainer(keyedBy: Key.self, forKey: .publicKey)
        }
        return try decoder.container(keyedBy: Key.self)
    }

    static func bytes<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, _ key: Key) throws -> Data {
        let text = try container.decode(String.self, forKey: key)
        guard let data = OAuthBase64URL.decode(text) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "\(key.stringValue) is not base64")
        }
        return data
    }
}

// MARK: AuthClient

extension AuthClient {
    /// Ask for a passkey challenge for `email`. The answer has the same shape whether or not
    /// the email has a passkey. Throws ``PasskeyUnavailable`` when passkeys are off.
    public func passkeyChallenge(email: String) async throws -> PasskeyChallenge {
        do {
            return try await api.http.json(
                "POST", "/v1/oauth/passkey/challenge",
                body: .encode(PasskeyChallengeRequest(clientId: configuration.clientID, email: email)),
                authenticated: false, as: PasskeyChallenge.self
            )
        } catch let error as IntrospectionError where error.oauthError == "unsupported_grant_type" {
            throw PasskeyUnavailable(.disabled, underlying: error)
        }
    }

    /// Sign in with the authenticator's answer to `challenge`. A refused assertion or a reused
    /// challenge throws with `oauthError == "invalid_grant"`.
    @discardableResult
    public func signInWithPasskey(challenge: PasskeyChallenge, assertion: PasskeyAssertion) async throws -> AuthSession {
        let generation = self.generation
        let credential = String(decoding: try JSONCoding.encoder.encode(assertion), as: UTF8.self)
        let response: OAuthToken
        do {
            response = try await api.token(
                grantType: OAuthGrantType.passkey, clientId: configuration.clientID,
                parameters: [("challenge_id", challenge.challengeId), ("public_key_credential", credential)]
            )
        } catch let error as IntrospectionError where error.oauthError == "unsupported_grant_type" {
            throw PasskeyUnavailable(.disabled, underlying: error)
        }
        return try await signedIn(SessionToken(oauth: response, receivedAt: now()), ifCurrent: generation)
    }

    /// Start registering a passkey for the signed-in member: `POST /v1/passkeys`.
    public func startPasskeyRegistration(name: String? = nil) async throws -> PasskeyRegistration {
        let http = try await signedInControlPlane()
        do {
            return try await http.json(
                "POST", "/v1/passkeys", body: .encode(PasskeyCreateRequest(name: name)), as: PasskeyRegistration.self)
        } catch let error as IntrospectionError where error.kind == .notFound {
            throw PasskeyUnavailable(.disabled, underlying: error)
        }
    }

    /// Finish a registration with the authenticator's attestation: `PATCH /v1/passkeys/{id}`.
    @discardableResult
    public func finishPasskeyRegistration(
        _ registration: PasskeyRegistration, attestation: PasskeyAttestation, name: String? = nil
    ) async throws -> Passkey {
        let http = try await signedInControlPlane()
        return try await http.json(
            "PATCH", "/v1/passkeys/\(pathSegment(registration.id))",
            body: .encode(PasskeyUpdateRequest(publicKeyCredential: attestation, name: name ?? registration.name)),
            as: Passkey.self
        )
    }

    /// The signed-in member's passkeys: `GET /v1/passkeys`. Throws ``PasskeyUnavailable`` when passkeys are off.
    public func listPasskeys() async throws -> [Passkey] {
        let http = try await signedInControlPlane()
        do {
            return try await http.json("GET", "/v1/passkeys", as: Page<Passkey>.self).records
        } catch let error as IntrospectionError where error.kind == .notFound {
            throw PasskeyUnavailable(.disabled, underlying: error)
        }
    }

    /// Remove one of the signed-in member's passkeys: `DELETE /v1/passkeys/{id}`.
    public func removePasskey(id: String) async throws {
        let http = try await signedInControlPlane()
        try await http.empty("DELETE", "/v1/passkeys/\(pathSegment(id))")
    }

    /// The Control Plane, authenticated as the signed-in member and refreshed after a `401`.
    private func signedInControlPlane() async throws -> HTTPClient {
        guard try await session != nil else {
            throw IntrospectionError(kind: .authentication, message: "Not signed in")
        }
        return HTTPClient(baseURL: configuration.controlPlaneURL, credentials: credentials, transport: configuration.transport)
    }
}

struct PasskeyChallengeRequest: Encodable {
    let clientId: String
    let email: String

    enum CodingKeys: String, CodingKey {
        case clientId = "client_id"
        case email
    }
}

struct PasskeyCreateRequest: Encodable {
    let name: String?
}

struct PasskeyUpdateRequest: Encodable {
    let publicKeyCredential: PasskeyAttestation
    let name: String?

    enum CodingKeys: String, CodingKey {
        case publicKeyCredential = "public_key_credential"
        case name
    }
}
