import Foundation

/// A plaintext secret the API returns once or takes on write. Printing, interpolating or dumping it shows
/// `Secret(<redacted>)`, so logging a request or response never leaks it; read it with ``plaintext``.
public struct Secret: Codable, Sendable, Hashable, ExpressibleByStringLiteral, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    /// The secret itself.
    public let plaintext: String

    /// Wrap a plaintext secret.
    public init(_ plaintext: String) { self.plaintext = plaintext }

    /// Wrap a literal secret.
    public init(stringLiteral value: String) { plaintext = value }

    /// Decode from the bare JSON string the API sends.
    public init(from decoder: any Decoder) throws { plaintext = try decoder.singleString() }

    /// Encode as the bare JSON string the API takes.
    public func encode(to encoder: any Encoder) throws { try encoder.encodeSingle(plaintext) }

    /// Always `Secret(<redacted>)`.
    public var description: String { "Secret(<redacted>)" }

    /// Always `Secret(<redacted>)`.
    public var debugDescription: String { description }

    /// A mirror with no children, so `dump` and reflection never reach the plaintext.
    public var customMirror: Mirror { Mirror(self, children: [], displayStyle: .struct) }
}
