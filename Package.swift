// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "IntrospectionSDK",
    platforms: [.iOS(.v16), .macOS(.v13), .tvOS(.v16), .watchOS(.v9), .visionOS(.v1)],
    products: [
        .library(name: "IntrospectionSDK", targets: ["IntrospectionSDK"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0"..<"5.0.0")
    ],
    targets: [
        .target(name: "IntrospectionSDK", dependencies: [.product(name: "Crypto", package: "swift-crypto")]),
        .testTarget(name: "IntrospectionSDKTests", dependencies: ["IntrospectionSDK"]),
        .executableTarget(name: "RuntimesExample", dependencies: ["IntrospectionSDK"], path: "Examples/Runtimes"),
        .executableTarget(name: "FederatedExample", dependencies: ["IntrospectionSDK"], path: "Examples/Federated"),
    ]
)
