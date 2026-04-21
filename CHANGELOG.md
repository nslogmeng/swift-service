# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Changelog tracks minor version releases only. Patch releases are folded into their parent minor version.

## [Unreleased]

Swift 6.0 back deploy via dual package manifest.

### Features

- **Swift 6.0 Toolchain Support** — Added `Package@swift-6.0.swift` companion manifest so the package builds on Swift 6.0 toolchains (Xcode 16). The primary `Package.swift` keeps Swift 6.2 strict memory safety and `NonisolatedNonsendingByDefault`; the 6.0 manifest drops settings that are 6.2-only while preserving `ExistentialAny` and `InternalImportsByDefault`.
- **CI Matrix** — `build.yml` and `test.yml` now cover Swift 6.0 and 6.2 across macOS and Ubuntu.

### Improvements

- Gated the `unsafe` expression markers in `LockStorage` behind `#if compiler(>=6.2)` so the source compiles on both toolchains. Runtime semantics are unchanged: the markers only exist to silence strict-memory-safety diagnostics.

---

## [1.3.0]

Cross-platform support and lowered minimum platform versions.

### Features

- **Cross-Platform Locking** — Extracted `LockStorage` with platform-specific implementations (Apple: `OSAllocatedUnfairLock`, Linux/Android: `Synchronization.Mutex`, Wasm: no-op)
- **Lowered Platform Versions** — iOS 16+, macOS 13+, watchOS 9+, tvOS 16+, visionOS 1+ (previously iOS 18+)
- **PrivacyInfo** — Added `PrivacyInfo.xcprivacy` for App Store tracking compliance
- **Swinject Migration Guide** — Comprehensive guide for migrating from Swinject to Service

### Improvements

- Refactored `Locked` property wrapper to delegate to `LockStorage`, removing all conditional compilation
- Updated documentation to reflect cross-platform architecture and lowered versions

---

## [1.2.0]

Lazy injection, optional services, multi-scope registration, and unified storage architecture.

### Features

- **Provider Property Wrappers** — `@Provider` and `@MainProvider` for scope-driven uncached injection
- **Flexible Service Scopes** — Singleton, transient, graph, and custom named scopes for fine-grained lifecycle control
- **Lazy and Optional Injection** — `@Service` supports lazy resolution and optional service types

### Improvements

- Unified cache storage model with `Box` types for clearer mutual exclusion between Sendable and MainActor services
- Fixed `MainService` mutating getter issue
- Updated README and DocC documentation to cover all new features

---

## [1.1.0]

Enhanced error handling, documentation, and developer experience.

### Features

- **MainActor Service Support** — Dedicated `registerMain()` / `@MainService` for MainActor-isolated services
- **Circular Dependency Detection** — Automatic detection via `TaskLocal` resolution stack with clear error messages
- **Configurable Resolution Depth** — `maxResolutionDepth` exposed as public API
- **ServiceEnv Hashable** — `ServiceEnv` conforms to `Hashable` for use as dictionary keys and in sets
- **Reset APIs** — `resetCaches()` and `resetAll()` for service lifecycle management
- **Service Assembly** — `ServiceAssembly` protocol for modular, `@MainActor`-constrained registration
- **Chinese Localization** — Full Chinese README and DocC documentation

### Improvements

- Zero external dependencies — removed all DocC-related package dependencies
- Multi-language DocC documentation site with GitHub Pages deployment
- Linux compatibility with platform-specific lock fallback
- Swift Package Index integration with documentation links
- Comprehensive fatal error tests for property wrapper edge cases

---

## [1.0.0]

First release. Complete rewrite with Swift 6.2 strict concurrency support.

### Features

- **Swift 6.2 Strict Concurrency** — Full `Sendable` enforcement with `@Service` property wrapper
- **Multi-environment Support** — `ServiceEnv` with online, test, dev environments via `@TaskLocal` isolation
- **Thread-safe Storage** — Mutex-based `@Locked` for Sendable services
- **ServiceKey Protocol** — Simplified registration with `static var default`

### Platform Support

- iOS 18.0+, macOS 15.0+, watchOS 11.0+, tvOS 18.0+, visionOS 2.0+
- Swift 6.0+, Swift Language Mode v6

---

[Unreleased]: https://github.com/nslogmeng/swift-service/compare/1.3.0...HEAD
[1.3.0]: https://github.com/nslogmeng/swift-service/compare/1.2.0...1.3.0
[1.2.0]: https://github.com/nslogmeng/swift-service/compare/1.1.0...1.2.0
[1.1.0]: https://github.com/nslogmeng/swift-service/compare/1.0.0...1.1.0
[1.0.0]: https://github.com/nslogmeng/swift-service/releases/tag/1.0.0
