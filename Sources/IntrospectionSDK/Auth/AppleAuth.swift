// Apple-only conveniences: Keychain session storage and the hosted-login sheet.
// Both compile only where their frameworks exist, so the package still builds on Linux.

#if canImport(Security)
import Foundation
import Security

/// Keeps the session in the Keychain (generic password, this device only, after first unlock).
public struct KeychainSessionStorage: SessionStorage {
    public let service: String
    public let accessGroup: String?

    public init(service: String = "dev.introspection.auth", accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    public func load(key: String) async throws -> Data? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw keychainError(status, "read") }
        return result as? Data
    }

    public func save(_ data: Data, key: String) async throws {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(baseQuery(key) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var query = baseQuery(key)
            query.merge(attributes) { _, new in new }
            let added = SecItemAdd(query as CFDictionary, nil)
            guard added == errSecSuccess else { throw keychainError(added, "save") }
        } else if status != errSecSuccess {
            throw keychainError(status, "save")
        }
    }

    public func remove(key: String) async throws {
        let status = SecItemDelete(baseQuery(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw keychainError(status, "remove") }
    }

    private func baseQuery(_ key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }

    private func keychainError(_ status: OSStatus, _ action: String) -> IntrospectionError {
        IntrospectionError(kind: .invalidRequest, message: "Keychain \(action) failed (OSStatus \(status))")
    }
}
#endif

#if canImport(AuthenticationServices) && !os(watchOS)
import AuthenticationServices
import Foundation

/// Runs the platform hosted login in the system sign-in sheet
/// (`ASWebAuthenticationSession`) and completes it on the `AuthClient`.
@MainActor
public final class HostedLoginPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let anchor: ASPresentationAnchor

    public init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
    }

    public nonisolated func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { anchor }
    }

    /// Sign in. `redirectURI` must be registered on the `spa` Application; an
    /// `https` universal link needs iOS 17.4 / macOS 14.4, a custom scheme works earlier.
    @discardableResult
    public func signIn(
        with auth: AuthClient,
        redirectURI: String,
        scope: String = "*",
        loginHint: String? = nil,
        prefersEphemeralWebBrowserSession: Bool = false
    ) async throws -> AuthSession {
        let request = auth.hostedLoginRequest(redirectURI: redirectURI, scope: scope, loginHint: loginHint)
        guard let redirect = URL(string: redirectURI) else {
            throw IntrospectionError(kind: .invalidRequest, message: "Invalid redirect URI: \(redirectURI)")
        }
        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let completion: ASWebAuthenticationSession.CompletionHandler = { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: CancellationError())
                } else {
                    continuation.resume(
                        throwing: IntrospectionError(
                            kind: .authentication,
                            message: error?.localizedDescription ?? "Sign-in did not complete",
                            underlying: error
                        ))
                }
            }
            let session: ASWebAuthenticationSession
            if redirect.scheme == "https", #available(iOS 17.4, macOS 14.4, tvOS 17.4, visionOS 1.1, *),
                let host = redirect.host
            {
                session = ASWebAuthenticationSession(
                    url: request.url, callback: .https(host: host, path: redirect.path), completionHandler: completion
                )
            } else {
                session = ASWebAuthenticationSession(
                    url: request.url, callbackURLScheme: redirect.scheme, completionHandler: completion
                )
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = prefersEphemeralWebBrowserSession
            if !session.start() {
                continuation.resume(throwing: IntrospectionError(kind: .authentication, message: "Could not start the sign-in session"))
            }
        }
        return try await auth.completeHostedLogin(request, callbackURL: callbackURL)
    }
}
#endif

#if canImport(AuthenticationServices) && (os(iOS) || os(macOS) || os(visionOS))
import AuthenticationServices
import Foundation

/// Signs in with, and registers, a platform passkey (Face ID / Touch ID) through
/// `ASAuthorizationController`. The relying party's domain must be in the app's
/// `webcredentials` associated domains. Every reason to fall back to the email code
/// throws ``PasskeyUnavailable``.
@available(iOS 16, macOS 13, visionOS 1, *)
@MainActor
public final class PasskeyPresenter: NSObject, ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
{
    private enum Outcome: Sendable {
        case assertion(PasskeyAssertion)
        case attestation(PasskeyAttestation)
    }

    private let anchor: ASPresentationAnchor
    private var controller: ASAuthorizationController?
    private var continuation: CheckedContinuation<Outcome, any Error>?

    public init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
    }

    /// Sign in as `email` with a passkey on this device. The system shows no sheet
    /// when the device has no passkey for the account; that throws ``PasskeyUnavailable``.
    @discardableResult
    public func signIn(with auth: AuthClient, email: String) async throws -> AuthSession {
        let challenge = try await auth.passkeyChallenge(email: email)
        guard let relyingPartyID = challenge.options.relyingPartyID else {
            throw PasskeyUnavailable(.notSupported)
        }
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: relyingPartyID)
        let request = provider.createCredentialAssertionRequest(challenge: challenge.options.challenge)
        request.allowedCredentials = challenge.options.allowedCredentialIDs.map {
            ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0)
        }
        if let preference = challenge.options.userVerification {
            request.userVerificationPreference = ASAuthorizationPublicKeyCredentialUserVerificationPreference(
                rawValue: preference)
        }
        guard case let .assertion(assertion) = try await perform(request, immediatelyAvailableOnly: true) else {
            throw IntrospectionError(kind: .authentication, message: "The authenticator did not return an assertion")
        }
        return try await auth.signInWithPasskey(challenge: challenge, assertion: assertion)
    }

    /// Register a passkey on this device for the signed-in member.
    @discardableResult
    public func register(with auth: AuthClient, name: String? = nil) async throws -> Passkey {
        let registration = try await auth.startPasskeyRegistration(name: name)
        let options = registration.options
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: options.relyingPartyID)
        let request = provider.createCredentialRegistrationRequest(
            challenge: options.challenge, name: options.userName, userID: options.userID)
        guard case let .attestation(attestation) = try await perform(request, immediatelyAvailableOnly: false) else {
            throw IntrospectionError(kind: .authentication, message: "The authenticator did not return an attestation")
        }
        return try await auth.finishPasskeyRegistration(registration, attestation: attestation, name: name)
    }

    private func perform(_ request: ASAuthorizationRequest, immediatelyAvailableOnly: Bool) async throws -> Outcome {
        guard continuation == nil else {
            throw IntrospectionError(kind: .invalidRequest, message: "A passkey request is already in progress")
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            self.controller = controller
            if immediatelyAvailableOnly {
                controller.performRequests(options: .preferImmediatelyAvailableCredentials)
            } else {
                controller.performRequests()
            }
        }
    }

    private func finish(_ result: Result<Outcome, any Error>) {
        let continuation = self.continuation
        self.continuation = nil
        controller = nil
        continuation?.resume(with: result)
    }

    public nonisolated func presentationAnchor(for _: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated { anchor }
    }

    public nonisolated func authorizationController(
        controller _: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        let result: Result<Outcome, any Error>
        switch authorization.credential {
        case let credential as ASAuthorizationPlatformPublicKeyCredentialAssertion:
            result = .success(
                .assertion(
                    PasskeyAssertion(
                        credentialID: credential.credentialID, clientDataJSON: credential.rawClientDataJSON,
                        authenticatorData: credential.rawAuthenticatorData, signature: credential.signature,
                        userHandle: credential.userID
                    )))
        case let credential as ASAuthorizationPlatformPublicKeyCredentialRegistration:
            if let attestationObject = credential.rawAttestationObject {
                result = .success(
                    .attestation(
                        PasskeyAttestation(
                            credentialID: credential.credentialID, clientDataJSON: credential.rawClientDataJSON,
                            attestationObject: attestationObject
                        )))
            } else {
                result = .failure(IntrospectionError(kind: .authentication, message: "The passkey has no attestation"))
            }
        default:
            result = .failure(IntrospectionError(kind: .authentication, message: "Unexpected credential type"))
        }
        MainActor.assumeIsolated { finish(result) }
    }

    public nonisolated func authorizationController(
        controller _: ASAuthorizationController, didCompleteWithError error: any Error
    ) {
        let mapped = Self.map(error)
        MainActor.assumeIsolated { finish(.failure(mapped)) }
    }

    /// Every authorization error an app should answer with the email code becomes ``PasskeyUnavailable``.
    nonisolated static func map(_ error: any Error) -> any Error {
        guard let authorization = error as? ASAuthorizationError else {
            return IntrospectionError(kind: .authentication, message: error.localizedDescription, underlying: error)
        }
        switch authorization.code {
        // With immediately-available credentials only, a device with no passkey also ends as `canceled`.
        case .canceled: return PasskeyUnavailable(.canceled, underlying: error)
        case .notHandled, .notInteractive: return PasskeyUnavailable(.noCredential, underlying: error)
        // An app without the relying party in its associated domains fails here.
        case .failed, .unknown, .invalidResponse: return PasskeyUnavailable(.notSupported, underlying: error)
        default:
            return IntrospectionError(kind: .authentication, message: error.localizedDescription, underlying: error)
        }
    }
}
#endif
