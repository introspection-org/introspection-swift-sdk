// swift-tools-version:6.2
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .treatAllWarnings(as: .error),
]

let package = Package(
    name: "IntrospectionSDK",
    platforms: [.iOS(.v18), .macOS(.v15), .tvOS(.v18), .watchOS(.v11), .visionOS(.v2)],
    products: [
        .library(name: "IntrospectionSDK", targets: ["IntrospectionSDK"])
    ],
    traits: [
        .trait(
            name: "Configuration",
            description: "Reads the client configuration through swift-configuration (environment variables, files, arguments)."
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0"..<"5.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
        .package(url: "https://github.com/apple/swift-distributed-tracing.git", from: "1.1.0"),
        .package(url: "https://github.com/apple/swift-service-context.git", from: "1.1.0"),
        .package(url: "https://github.com/apple/swift-configuration.git", from: "1.2.0"),
    ],
    targets: [
        .target(
            name: "IntrospectionSDK",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Instrumentation", package: "swift-distributed-tracing"),
                .product(name: "ServiceContextModule", package: "swift-service-context"),
                .product(
                    name: "Configuration", package: "swift-configuration",
                    condition: .when(traits: ["Configuration"])),
            ],
            resources: [.copy("PrivacyInfo.xcprivacy")],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "IntrospectionSDKTests",
            dependencies: [
                "IntrospectionSDK",
                .product(
                    name: "Configuration", package: "swift-configuration",
                    condition: .when(traits: ["Configuration"])),
            ],
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "RuntimesExample", dependencies: ["IntrospectionSDK"], path: "Examples/Runtimes",
            swiftSettings: swiftSettings),
        .executableTarget(
            name: "FederatedExample", dependencies: ["IntrospectionSDK"], path: "Examples/Federated",
            swiftSettings: swiftSettings),
    ]
)
