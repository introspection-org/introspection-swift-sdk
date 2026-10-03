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
        prefersEphemeralWebBrowserSession: Bool = false
    ) async throws -> AuthSession {
        let request = auth.hostedLoginRequest(redirectURI: redirectURI)
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
