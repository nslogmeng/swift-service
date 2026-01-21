# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.8]

### Changed
- **Zero Dependencies**: Removed all external package dependencies
  - Eliminated DocC-related dependencies from `Package.swift`
  - Removed `Package.resolved` file
  - Replaced dependency-based documentation build with standalone script
  - Service is now truly zero-dependency with no external dependencies required

### Added
- **Resetting Services Documentation**: Comprehensive guide on service lifecycle management
  - Complete documentation for `resetCaches()` and `resetAll()` methods
  - Detailed examples for testing scenarios and state management
  - Bilingual support (English and Simplified Chinese)

### Improved
- Enhanced documentation terminology consistency in Chinese translations
  - Unified terminology for ServiceAssembly and related concepts
  - Improved clarity and consistency across documentation
- Improved cross-platform compatibility for documentation builds
- Streamlined GitHub Actions workflows for documentation deployment

---

## [1.0.7]

### Added
- `ServiceEnv` now conforms to the `Hashable` protocol, enabling more flexible usage patterns
  - `ServiceEnv` instances can now be used as dictionary keys
  - `ServiceEnv` instances can be stored in `Set` collections
  - Equality comparison is based on the environment's `name` property
  - Hash values are computed from the environment's `name` property

### Documents Improved
- Root path (`/`) automatically redirects to `/documentation/service/`
- Language-specific root paths (e.g., `/zh-Hans/`) redirect to their respective documentation pages
- Redirect logic preserves SPA (Single Page Application) functionality
- Seamless navigation for both English and Chinese documentation
- Direct access to documentation from the site root
- Consistent behavior across all language versions

---

## [1.0.6]

### Added
- Complete multilingual documentation site with English and Simplified Chinese support
- Swift Package Index (SPI) integration
  - Direct documentation links from the SPI package page
  - Enhanced package visibility in the Swift Package Index ecosystem
  - Documentation links available for both English and Chinese

### Improved
- Complete bilingual documentation coverage
- Consistent documentation experience across languages
- Easy navigation between English and Chinese versions
- Import cleanup: Removed unused imports to reduce unnecessary dependencies and improve compilation efficiency
- Refined Chinese documentation: Improved clarity, consistency, and organization of Chinese translations
- Enhanced README files: Added new topics and improved documentation links
- Better navigation: Clearer structure and cross-references between documentation articles

---

## [1.0.5]

### Added
- **Comprehensive Chinese Localization**: Full Chinese localization support with Simplified Chinese (简体中文) documentation
  - Complete Chinese translation of all documentation articles
  - Localized README with Chinese examples and usage guides
  - Chinese documentation for Swift Package Index integration
  - Bilingual support in all documentation topics with easy language switching

- **MainActor Service Support**: Dedicated APIs for MainActor-isolated services
  - MainActor service registration: Register services bound to the main actor
  - MainActor service resolution: Resolve MainActor services with `resolveMain`
  - MainActor property wrapper: Use `@MainService` for automatic injection
  - MainActor instance registration: Register pre-created MainActor instances directly
  - ServiceKey support: Simplified registration using `ServiceKey` protocol for both Sendable and MainActor services

- **Automatic Circular Dependency Detection**: Automatically detects circular dependencies during service resolution through the new `ServiceContext` system
  - Clear error messages showing the full dependency chain when circular dependencies are detected

- **Resolution Depth Protection**: Prevents stack overflow from excessively deep dependency graphs by enforcing a maximum resolution depth (default: 100)

### Improved
- Enhanced thread safety and Swift 6.2 support
  - Better thread safety: More reliable behavior in concurrent and async contexts
  - Improved type safety: Better compile-time checking for potential concurrency issues
  - Enhanced compatibility: Full support for Swift 6.2 concurrency features

### Fixed
- Fixed compatibility issues with different Swift compiler versions
- Improved error handling in service resolution

### Changed
- **Breaking Change**: Service now requires Swift 6.2 (previously Swift 6.0+)

---

## [1.0.4]

### Changed
- **Breaking Change**: `ServiceAssembly` protocol now marked with `@MainActor` instead of `Sendable`
  - Ensures thread safety and predictable, sequential execution context for service registration
  - Assembly operations are constrained to the main actor

### Improved
- Enhanced thread safety for `ServiceAssembly`
- Better documentation explaining `@MainActor` usage for `ServiceAssembly`
- Enhanced README with detailed examples for calling `assemble()` from different contexts
- Updated API reference with thread safety notes and usage guidelines

### Fixed
- Fixed typo in README

### Documentation
- Added comprehensive documentation explaining `@MainActor` usage for `ServiceAssembly`
- Enhanced README with detailed examples for calling `assemble()` from different contexts
- Updated API reference with thread safety notes and usage guidelines

### Testing
- Updated tests to ensure proper `@MainActor` context handling
- Improved test coverage for service assembly in different execution contexts

---

## [1.0.3]

### Added
- **Service Lifecycle Management**:
  - `resetCaches()`: Clears all cached service instances while keeping registered providers intact
  - `resetAll()`: Completely resets the service environment by clearing both cached instances and all registered providers
- **Variadic Arguments for ServiceAssembly**: Added support for variadic arguments in the `assemble()` method

### Changed
- Replaced subscript access with explicit `resolve()` method in `ServiceEnv` for improved API clarity and consistency

### Documentation
- Updated README with `resetCaches()` and `resetAll()` usage examples
- Added variadic arguments example for `ServiceAssembly.assemble()`
- Improved API reference documentation

---

## [1.0.2]

### Added
- **ServiceAssembly Protocol**: Introduced `ServiceAssembly` protocol for modular, reusable service registration, similar to Swinject's Assembly pattern
  - Support for assembling single or multiple assemblies
  - Clean separation of service registration logic

### Improved
- Refactored import statements in `Lock.swift` for better readability
- Improved test coverage

### Documentation
- Updated README with ServiceAssembly usage examples
- Enhanced API reference documentation

---

## [1.0.1]

### Fixed
- Fixed Swift 6.0 compiler compatibility issues
- Fixed build errors
- Added support for both Linux and Darwin platforms

### Improved
- Refactored thread lock implementation for better Linux compatibility and thread safety
- Adjusted Swift tools version to 6.0

### Documentation
- Updated README with project logo and badges

---

## [1.0.0]

### Added
- **Initial Stable Release**: First stable release of Service - a lightweight, zero-dependency, type-safe dependency injection framework for modern Swift

### Features
- **Modern Swift**: Built with property wrappers, TaskLocal, and Swift 6 concurrency
- **Zero Dependencies**: No external dependencies, minimal footprint
- **Type-Safe**: Compile-time checked service registration and resolution
- **Thread-Safe**: Full support for Swift 6's strict concurrency model
- **Simple API**: Intuitive registration and injection APIs

### Platform Support
- iOS 18.0+
- macOS 15.0+
- watchOS 11.0+
- tvOS 18.0+
- visionOS 2.0+

### Requirements
- Swift 6.0+
- Swift Language Mode v6

---

[1.0.8]: https://github.com/nslogmeng/swift-service/compare/1.0.7...1.0.8
[1.0.7]: https://github.com/nslogmeng/swift-service/compare/1.0.6...1.0.7
[1.0.6]: https://github.com/nslogmeng/swift-service/compare/1.0.5...1.0.6
[1.0.5]: https://github.com/nslogmeng/swift-service/compare/1.0.4...1.0.5
[1.0.4]: https://github.com/nslogmeng/swift-service/compare/1.0.3...1.0.4
[1.0.3]: https://github.com/nslogmeng/swift-service/compare/1.0.2...1.0.3
[1.0.2]: https://github.com/nslogmeng/swift-service/compare/1.0.1...1.0.2
[1.0.1]: https://github.com/nslogmeng/swift-service/compare/1.0.0...1.0.1
[1.0.0]: https://github.com/nslogmeng/swift-service/releases/tag/1.0.0
