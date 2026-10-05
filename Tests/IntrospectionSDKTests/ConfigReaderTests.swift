#if Configuration
import Configuration
import Foundation
import Testing

@testable import IntrospectionSDK

@Suite struct ConfigReaderTests {
    @Test func readsTheSameKeysAsTheRustSDK() throws {
        let config = ConfigReader(
            provider: InMemoryProvider(values: [
                "introspection.token": ConfigValue("intro_key", isSecret: true),
                "introspection.base_api_url": "https://api.staging.introspection.dev",
            ]))
        let configuration = try IntrospectionClient.Configuration(config: config)
        #expect(configuration.controlPlaneURL.absoluteString == "https://api.staging.introspection.dev")
        #expect(configuration.dataPlaneURL == nil)
        #expect((configuration.controlPlaneCredentials as? BearerToken)?.token == "intro_key")
    }

    @Test func tokenIsRequiredAndTheControlPlaneDefaults() throws {
        #expect(throws: (any Error).self) {
            try IntrospectionClient.Configuration(config: ConfigReader(provider: InMemoryProvider(values: [:])))
        }
        let configuration = try IntrospectionClient.Configuration(
            config: ConfigReader(provider: InMemoryProvider(values: ["introspection.token": "k"])))
        #expect(configuration.controlPlaneURL.absoluteString == "https://api.introspection.dev")
        #expect(configuration.otelURL == nil)
    }

    @Test func readsTheOTelURLLikeTheJavaScriptSDK() throws {
        let configuration = try IntrospectionClient.Configuration(
            config: ConfigReader(
                provider: InMemoryProvider(values: [
                    "introspection.token": "k", "introspection.base_otel_url": "https://otel.staging.introspection.dev",
                ])))
        #expect(configuration.otelURL?.absoluteString == "https://otel.staging.introspection.dev")
        #expect(IntrospectionClient(configuration: configuration).eventLogger.otelURL == configuration.otelURL)
        #expect(throws: IntrospectionError.self) {
            try IntrospectionClient.Configuration(
                config: ConfigReader(provider: InMemoryProvider(values: ["introspection.token": "k", "introspection.base_otel_url": ""])))
        }
    }
}
#endif
