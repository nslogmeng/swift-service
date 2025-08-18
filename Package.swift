// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let swiftSettings: [SwiftSetting] = [
//    .enableUpcomingFeature("ConciseMagicFile"),             // SE-0274
//    .enableUpcomingFeature("StrictConcurrency"),            // SE-0337
//    .enableUpcomingFeature("ImplicitOpenExistentials"),     // SE-0352
]

let package = Package(
    name: "Service",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(name: "Service", targets: ["Service"]),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(name: "Service", swiftSettings: swiftSettings),
        .testTarget( name: "ServiceTests", dependencies: ["Service"]),
    ]
)
