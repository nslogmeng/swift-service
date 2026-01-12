// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-service",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .watchOS(.v11),
        .tvOS(.v18),
        .visionOS(.v2),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(name: "Service", targets: ["Service"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-docc-plugin", .upToNextMajor(from: "1.4.5")),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "Service",
            swiftSettings: [
                .enableUpcomingFeature("MemberImportVisibility")
            ],
            plugins: [
                .plugin(name: "Swift-DocC", package: "swift-docc-plugin")
            ]
        ),
        .testTarget(name: "ServiceTests", dependencies: ["Service"]),
    ],
    swiftLanguageModes: [.v6]
)
