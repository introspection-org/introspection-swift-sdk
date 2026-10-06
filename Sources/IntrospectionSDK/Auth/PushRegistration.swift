import Foundation

/// A device's push registration, sent on `/v1/oauth/token` so the platform can
/// notify the phones a member is signed in on.
///
/// The registration rides on the member's session: the `authorization_code`,
/// email-code and `refresh_token` grants write it onto the session they create or
/// rotate, a later refresh overwrites it, and ending the session clears it.
/// `description` and `dump` never show the token.
public struct PushRegistration: Sendable, Hashable {
    /// The push service a token belongs to.
    public struct Platform: RawRepresentable, Sendable, Hashable, ExpressibleByStringLiteral {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(stringLiteral value: String) { rawValue = value }

        /// Apple Push Notification service.
        public static let apns: Platform = "apns"
    }

    /// The APNs environment that issued the token: a Debug build's token is
    /// `sandbox`, a TestFlight or App Store build's is `production`.
    public struct Environment: RawRepresentable, Sendable, Hashable, ExpressibleByStringLiteral {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(stringLiteral value: String) { rawValue = value }

        public static let sandbox: Environment = "sandbox"
        public static let production: Environment = "production"
    }

    /// The device token as lowercase hex; empty clears the registration.
    public var token: String
    public var platform: Platform
    public var environment: Environment

    public init(token: String, environment: Environment, platform: Platform = .apns) {
        self.token = token
        self.environment = environment
        self.platform = platform
    }

    /// A registration from the `deviceToken` APNs hands to
    /// `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`.
    public init(deviceToken: Data, environment: Environment, platform: Platform = .apns) {
        self.init(token: Self.hex(deviceToken), environment: environment, platform: platform)
    }

    /// Stop push to this session, for example when the user turns notifications off.
    public static let cleared = PushRegistration(token: "", environment: "")

    /// True when this registration clears the session's push fields.
    public var isCleared: Bool { token.isEmpty }

    /// The `/v1/oauth/token` form fields. A cleared registration sends only an
    /// empty `push_token`, which clears both of the session's push columns.
    var parameters: [(String, String?)] {
        if isCleared { return [("push_token", "")] }
        return [
            ("push_token", token), ("push_platform", platform.rawValue), ("push_environment", environment.rawValue),
        ]
    }

    /// The form fields for an optional registration: none when nil.
    static func parameters(_ push: PushRegistration?) -> [(String, String?)] {
        push?.parameters ?? []
    }

    private static func hex(_ data: Data) -> String {
        let digits = Array("0123456789abcdef")
        var text = ""
        text.reserveCapacity(data.count * 2)
        for byte in data {
            text.append(digits[Int(byte >> 4)])
            text.append(digits[Int(byte & 0x0F)])
        }
        return text
    }
}

extension PushRegistration: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        isCleared
            ? "PushRegistration(cleared)"
            : "PushRegistration(platform: \(platform.rawValue), environment: \(environment.rawValue), token: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["platform": platform.rawValue, "environment": environment.rawValue, "isCleared": isCleared])
    }
}
