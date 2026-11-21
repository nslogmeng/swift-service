// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "swift-service-benchmarks",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        // The name keeps the product reference below valid when the repository is cloned into a directory
        // with another name.
        .package(name: "swift-service", path: "../")
    ],
    targets: [
        .executableTarget(
            name: "ServiceBenchmarks",
            dependencies: [
                .product(name: "Service", package: "swift-service")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
