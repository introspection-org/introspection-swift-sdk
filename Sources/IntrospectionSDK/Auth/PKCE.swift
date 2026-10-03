import Foundation

/// A PKCE (RFC 7636) verifier and its S256 challenge.
public struct PKCE: Sendable, Hashable {
    /// The secret sent at the token step as `code_verifier`.
    public let verifier: String
    /// The value sent at the authorize step as `code_challenge`.
    public let challenge: String
    /// Always `S256`.
    public let method: String

    /// Characters RFC 7636 allows in a verifier (`unreserved`).
    static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// Generate a cryptographically random verifier of `length` characters (43...128).
    public init(length: Int = 64) {
        let clamped = min(max(length, 43), 128)
        var generator = SystemRandomNumberGenerator()
        let verifier = String(
            (0..<clamped).map { _ in
                Self.alphabet[Int.random(in: 0..<Self.alphabet.count, using: &generator)]
            })
        self.verifier = verifier
        challenge = Self.challenge(for: verifier)
        method = "S256"
    }

    /// Use an existing verifier; throws `.invalidRequest` if it breaks RFC 7636's rules.
    public init(verifier: String) throws {
        guard (43...128).contains(verifier.count), verifier.allSatisfy({ Self.alphabet.contains($0) }) else {
            throw IntrospectionError(
                kind: .invalidRequest,
                message: "A PKCE verifier is 43 to 128 characters of [A-Za-z0-9-._~]"
            )
        }
        self.verifier = verifier
        challenge = Self.challenge(for: verifier)
        method = "S256"
    }

    init(uncheckedVerifier verifier: String) {
        self.verifier = verifier
        challenge = Self.challenge(for: verifier)
        method = "S256"
    }

    /// The S256 challenge: `BASE64URL(SHA256(ASCII(verifier)))` without padding.
    public static func challenge(for verifier: String) -> String {
        OAuthBase64URL.encode(Data(SHA256Digest.hash(Data(verifier.utf8))))
    }

    /// A random URL-safe string (base64url of `byteCount` random bytes), for `state` and `nonce`.
    public static func randomURLSafeString(byteCount: Int = 32) -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<max(1, byteCount)).map { _ in UInt8.random(in: 0...255, using: &generator) }
        return OAuthBase64URL.encode(Data(bytes))
    }
}

/// Unpadded base64url (RFC 4648 section 5).
enum OAuthBase64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ text: String) -> Data? {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder == 1 { return nil }
        if remainder > 0 { base64 += String(repeating: "=", count: 4 - remainder) }
        return Data(base64Encoded: base64)
    }
}
