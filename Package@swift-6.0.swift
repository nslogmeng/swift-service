// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.
//
// Companion manifest used by Swift 6.0 toolchains. The primary `Package.swift`
// opts into Swift 6.2-only facilities (strict memory safety, nonisolated-nonsending
// default, member import visibility). Those settings are dropped here so the
// package can still be built and tested with the Swift 6.0 toolchain shipped in
// Xcode 16 / Swift 6.0 Linux builds. Source code paths that touch 6.2-only
// syntax (e.g. the `unsafe` expression marker) are gated with
// `#if compiler(>=6.2)` so the same sources compile under both manifests.
//
// Trailing commas in function call and parameter lists are intentionally omitted:
// SE-0439 (Swift 6.1+) is required for that syntax, and this manifest is parsed
// by the Swift 6.0 toolchain.

import PackageDescription

let package = Package(
    name: "swift-service",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .watchOS(.v9),
        .tvOS(.v16),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "Service", targets: ["Service"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "Service",
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ],
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "ServiceTests",
            dependencies: ["Service"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
