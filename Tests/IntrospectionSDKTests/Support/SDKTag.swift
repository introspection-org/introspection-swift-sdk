@testable import IntrospectionSDK

// `Testing` declares its own `Tag`, so a test file importing both cannot name
// the SDK's; this file imports only the SDK.
typealias SDKTag = Tag
