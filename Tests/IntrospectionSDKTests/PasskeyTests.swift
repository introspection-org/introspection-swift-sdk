import Foundation
import Testing

@testable import IntrospectionSDK

#if canImport(AuthenticationServices) && (os(iOS) || os(macOS) || os(visionOS))
import AuthenticationServices
#endif

@Suite struct PasskeyTests {
    private let challengeJSON = """
        {"challenge_id": "ch1", "public_key_credential_request_options": {"publicKey": {
          "challenge": "AQID_w", "rpId": "id.test", "timeout": 300000, "userVerification": "required",
          "allowCredentials": [{"type": "public-key", "id": "-_8"}, {"type": "public-key", "id": "+/8="}]}}}
        """

    private let registrationJSON = """
        {"id": "pk1", "name": "iPhone", "public_key_credential_creation_options": {"publicKey": {
          "rp": {"id": "id.test", "name": "Introspection"},
          "user": {"id": "dXNlci0x", "name": "a@b.co", "displayName": "A B"},
          "challenge": "AQID/w==", "pubKeyCredParams": [{"type": "public-key", "alg": -7}],
          "authenticatorSelection": {"userVerification": "required"}, "timeout": 300000, "attestation": "none"}}}
        """

    private func signedInJWT() -> String {
        let claims: JSONObject = ["member_id": "m1", "org_id": "o1", "jti": "s1", "exp": 4_102_444_800]
        return "e30.\(OAuthBase64URL.encode(try! JSONCoding.encoder.encode(claims))).sig"
    }

    private func tokenJSON(_ access: String) -> String {
        """
        {"access_token": "\(access)", "token_type": "Bearer", "expires_in": 3600, "refresh_token": "r1",
         "session_id": "s1", "org_id": "o1", "project_id": "p1", "dp_url": "https://dp.test"}
        """
    }

    private func auth(_ transport: MockTransport) -> AuthClient {
        AuthClient(
            configuration: .init(
                controlPlaneURL: URL(string: "https://cp.test")!, clientID: "ark", method: .emailCode, transport: transport))
    }

    private func form(_ request: MockTransport.Recorded) -> [String: String] {
        var result: [String: String] = [:]
        for item in URLComponents(string: "?" + request.bodyString)?.queryItems ?? [] {
            result[item.name] = item.value?.replacingOccurrences(of: "+", with: " ")
        }
        return result
    }

    @Test func challengeDecodesBase64URLAndStandardBase64() async throws {
        let transport = MockTransport(json: challengeJSON)
        let challenge = try await auth(transport).passkeyChallenge(email: "a@b.co")
        #expect(transport.last?.request.method == "POST")
        #expect(transport.last?.path == "/v1/oauth/passkey/challenge")
        #expect(transport.last?.json == ["client_id": "ark", "email": "a@b.co"])
        #expect(challenge.challengeId == "ch1")
        #expect(challenge.options.challenge == Data([1, 2, 3, 255]))
        #expect(challenge.options.relyingPartyID == "id.test")
        #expect(challenge.options.allowedCredentialIDs == [Data([251, 255]), Data([251, 255])])
        #expect(challenge.options.userVerification == "required")
        #expect(challenge.options.timeout == 300_000)
    }

    @Test func challengeWithPasskeysOffIsUnavailable() async throws {
        let transport = MockTransport(status: 400, json: #"{"error": "unsupported_grant_type"}"#)
        await #expect {
            try await auth(transport).passkeyChallenge(email: "a@b.co")
        } throws: { ($0 as? PasskeyUnavailable)?.reason == .disabled }
    }

    @Test func assertionEncodesAsUnpaddedBase64URL() throws {
        let assertion = PasskeyAssertion(
            credentialID: Data([251, 255]), clientDataJSON: Data("{}".utf8), authenticatorData: Data([1, 2, 3]),
            signature: Data([255, 254]), userHandle: Data("user-1".utf8))
        let json = try JSONCoding.decoder.decode(JSONValue.self, from: JSONCoding.encoder.encode(assertion))
        #expect(
            json == [
                "id": "-_8", "rawId": "-_8", "type": "public-key",
                "response": [
                    "clientDataJSON": "e30", "authenticatorData": "AQID", "signature": "__4", "userHandle": "dXNlci0x",
                ],
            ])
    }

    @Test func signInSendsTheGrantAndStoresTheSession() async throws {
        let access = signedInJWT()
        let transport = MockTransport { request, _ in
            request.url.path == "/v1/oauth/token"
                ? .response(.json(self.tokenJSON(access))) : .response(.json(self.challengeJSON))
        }
        let client = auth(transport)
        let challenge = try await client.passkeyChallenge(email: "a@b.co")
        let assertion = PasskeyAssertion(
            credentialID: Data([1]), clientDataJSON: Data([2]), authenticatorData: Data([3]), signature: Data([4]))
        let session = try await client.signInWithPasskey(challenge: challenge, assertion: assertion)

        let fields = form(transport.requests[1])
        #expect(fields["grant_type"] == OAuthGrantType.passkey)
        #expect(fields["client_id"] == "ark")
        #expect(fields["challenge_id"] == "ch1")
        let credential = try JSONCoding.decoder.decode(
            JSONValue.self, from: Data(try #require(fields["public_key_credential"]).utf8))
        #expect(
            credential == [
                "id": "AQ", "rawId": "AQ", "type": "public-key",
                "response": ["clientDataJSON": "Ag", "authenticatorData": "Aw", "signature": "BA"],
            ])
        #expect(session.user.memberId == "m1")
        #expect(try await client.session?.accessToken == access)
    }

    @Test func refusedAssertionIsInvalidGrant() async throws {
        let transport = MockTransport(status: 400, json: #"{"error": "invalid_grant"}"#)
        let challenge = PasskeyChallenge(challengeId: "ch1", options: PasskeyRequestOptions(challenge: Data([1])))
        let assertion = PasskeyAssertion(
            credentialID: Data([1]), clientDataJSON: Data([2]), authenticatorData: Data([3]), signature: Data([4]))
        await #expect {
            try await auth(transport).signInWithPasskey(challenge: challenge, assertion: assertion)
        } throws: { ($0 as? IntrospectionError)?.oauthError == "invalid_grant" }
    }

    /// `handler` answers every request but the token grant; it receives the request's index.
    private func signedIn(
        _ handler: @escaping (HTTPRequest, Int) -> HTTPResponse
    ) async throws -> (AuthClient, MockTransport) {
        let access = signedInJWT()
        let transport = MockTransport { request, index in
            request.url.path == "/v1/oauth/token"
                ? .response(.json(self.tokenJSON(access))) : .response(handler(request, index))
        }
        let client = auth(transport)
        try await client.verifyOTP(email: "a@b.co", token: "123456")
        return (client, transport)
    }

    @Test func registrationRoundTrip() async throws {
        let (client, transport) = try await signedIn { request, _ in
            request.method == "POST"
                ? .json(self.registrationJSON, status: 201) : .json(#"{"id": "pk1", "name": "iPhone", "state": "active"}"#)
        }
        let registration = try await client.startPasskeyRegistration(name: "iPhone")
        #expect(transport.requests[1].path == "/v1/passkeys")
        #expect(transport.requests[1].json == ["name": "iPhone"])
        #expect(transport.requests[1].request.headers["Authorization"] == "Bearer \(signedInJWT())")
        #expect(registration.id == "pk1")
        #expect(registration.options.relyingPartyID == "id.test")
        #expect(registration.options.userID == Data("user-1".utf8))
        #expect(registration.options.userName == "a@b.co")
        #expect(registration.options.challenge == Data([1, 2, 3, 255]))

        let attestation = PasskeyAttestation(
            credentialID: Data([251, 255]), clientDataJSON: Data("{}".utf8), attestationObject: Data([1, 2, 3]))
        let passkey = try await client.finishPasskeyRegistration(registration, attestation: attestation)
        #expect(transport.requests[2].request.method == "PATCH")
        #expect(transport.requests[2].path == "/v1/passkeys/pk1")
        #expect(
            transport.requests[2].json == [
                "name": "iPhone",
                "public_key_credential": [
                    "id": "-_8", "rawId": "-_8", "type": "public-key",
                    "response": ["clientDataJSON": "e30", "attestationObject": "AQID"],
                ],
            ])
        #expect(passkey == Passkey(id: "pk1", name: "iPhone", state: .active))
    }

    @Test func listAndRemove() async throws {
        let (client, transport) = try await signedIn { request, _ in
            request.method == "GET"
                ? .json(#"{"records": [{"id": "pk1", "name": "iPhone", "state": "AUTH_FACTOR_STATE_READY"}], "count": 1, "next": null}"#)
                : HTTPResponse(status: 204, headers: [:], body: Data())
        }
        #expect(try await client.listPasskeys() == [Passkey(id: "pk1", name: "iPhone", state: .ready)])
        try await client.removePasskey(id: "pk/1")
        #expect(transport.requests[2].request.method == "DELETE")
        #expect(transport.requests[2].request.url.absoluteString == "https://cp.test/v1/passkeys/pk%2F1")
    }

    @Test func unauthorizedRefreshesAndRetries() async throws {
        let (client, transport) = try await signedIn { _, index in
            index == 1 ? .json(#"{"detail": "expired"}"#, status: 401) : .json(#"{"records": [], "count": 0}"#)
        }
        #expect(try await client.listPasskeys().isEmpty)
        #expect(transport.requests.map(\.path) == ["/v1/oauth/token", "/v1/passkeys", "/v1/oauth/token", "/v1/passkeys"])
        #expect(form(transport.requests[2])["grant_type"] == OAuthGrantType.refreshToken)
    }

    @Test func passkeysOffOnTheControlPlaneIsUnavailable() async throws {
        let (client, _) = try await signedIn { _, _ in .json(#"{"detail": "Passkeys are not enabled"}"#, status: 404) }
        await #expect { try await client.listPasskeys() } throws: { ($0 as? PasskeyUnavailable)?.reason == .disabled }
        await #expect {
            try await client.startPasskeyRegistration()
        } throws: { ($0 as? PasskeyUnavailable)?.reason == .disabled }
    }

    @Test func registrationNeedsASession() async throws {
        let transport = MockTransport(json: "{}")
        await #expect {
            try await auth(transport).listPasskeys()
        } throws: { ($0 as? IntrospectionError)?.kind == .authentication }
        #expect(transport.requests.isEmpty)
    }

    #if canImport(AuthenticationServices) && (os(iOS) || os(macOS) || os(visionOS))
    @Test(arguments: [
        (ASAuthorizationError.Code.canceled, PasskeyUnavailable.Reason.canceled),
        (.notHandled, .noCredential),
        (.notInteractive, .noCredential),
        (.failed, .notSupported),
        (.unknown, .notSupported),
    ])
    func authorizationErrorsFallBack(code: ASAuthorizationError.Code, reason: PasskeyUnavailable.Reason) {
        let mapped = PasskeyPresenter.map(ASAuthorizationError(code))
        #expect((mapped as? PasskeyUnavailable)?.reason == reason)
    }

    @Test func otherErrorsDoNotFallBack() {
        struct Other: Error {}
        #expect(PasskeyPresenter.map(Other()) is IntrospectionError)
    }
    #endif
}
