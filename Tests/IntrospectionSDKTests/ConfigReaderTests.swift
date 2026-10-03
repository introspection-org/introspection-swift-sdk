#if Configuration
import Configuration
import Foundation
import XCTest

@testable import IntrospectionSDK

final class ConfigReaderTests: XCTestCase {
    func testReadsTheSameKeysAsTheRustSDK() throws {
        let config = ConfigReader(
            provider: InMemoryProvider(values: [
                "introspection.token": ConfigValue("intro_key", isSecret: true),
                "introspection.base_api_url": "https://api.staging.introspection.dev",
                "introspection.runtime": "ark",
            ]))
        let configuration = try IntrospectionClient.Configuration(config: config)
        XCTAssertEqual(configuration.controlPlaneURL.absoluteString, "https://api.staging.introspection.dev")
        XCTAssertNil(configuration.dataPlaneURL)
        XCTAssertEqual(configuration.runtime, "ark")
        XCTAssertEqual((configuration.controlPlaneCredentials as? BearerToken)?.token, "intro_key")
    }

    func testTokenIsRequiredAndTheControlPlaneDefaults() throws {
        XCTAssertThrowsError(try IntrospectionClient.Configuration(config: ConfigReader(provider: InMemoryProvider(values: [:]))))
        let configuration = try IntrospectionClient.Configuration(
            config: ConfigReader(provider: InMemoryProvider(values: ["introspection.token": "k"])))
        XCTAssertEqual(configuration.controlPlaneURL.absoluteString, "https://api.introspection.dev")
    }
}
#endif
