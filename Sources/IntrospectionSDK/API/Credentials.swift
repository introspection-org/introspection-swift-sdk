import Foundation

/// Supplies the `Authorization` header for a plane and, after a 401, a chance
/// to refresh it before the request is retried once.
public protocol CredentialProvider: Sendable {
    /// The full header value (for example `"Bearer eyJ..."`), or nil to send none.
    func authorization() async throws -> String?
    /// Called after a 401. Return true when the credential changed and the
    /// request should be retried once.
    func refreshAfterUnauthorized() async throws -> Bool
}

extension CredentialProvider {
    public func refreshAfterUnauthorized() async throws -> Bool { false }
}

/// A fixed bearer token: an API key, a service-account token, a runner token.
public struct BearerToken: CredentialProvider {
    public let token: String

    public init(_ token: String) { self.token = token }

    public func authorization() async throws -> String? { "Bearer \(token)" }
}
