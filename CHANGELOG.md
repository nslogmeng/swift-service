# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Changelog tracks minor version releases only. Patch releases are folded into their parent minor version.

## [1.4.0]

Correct resolution under concurrency and in tasks, a faster resolution, and four breaking corrections to the registration, environment, and property wrapper API.

### Breaking Changes

- **Instance registration takes a label** — `register(_:)` and `registerMain(_:)` for an existing instance are now `register(instance:)` and `registerMain(instance:)`. Before, a service type passed without a factory, such as `registerMain(ViewModel.self)`, compiled and registered the metatype. Now it does not compile
- **`registerMain` for `ServiceKey` types is removed** — A type with a main-actor-isolated initializer cannot conform to `ServiceKey`. Replace `registerMain(X.self)` with `registerMain(X.self) { X.default }`
- **`ServiceEnv` equality compares identity** — Two values are equal if they share one registry. `ServiceEnv(name: "test") == .test` is now `false`. To branch on the name, compare `env.name`. The compiler does not report the affected call sites
- **An optional property wrapper is `nil` only for an unregistered service** — `@Service var x: Foo?` was `nil` for every resolution error. If `Foo` is registered and cannot be created, the property now stops the process with `fatalError`, as a non-optional property does. That is the case when its factory throws, when a service that its factory needs is not registered, and when there is a dependency cycle. To get `nil` for these, call `try? env.resolve(Foo.self)`

### Features

- **Default MainActor Isolation** — The MainActor Services guide covers modules built with `.defaultIsolation(MainActor.self)`, the setting of new Xcode app targets. A test target built with that setting covers the public API
- **Supported Swift Versions** — The package supports the latest Swift release and the two minor releases before it, currently Swift 6.2, 6.3, and 6.4. CI builds and tests all three on Linux and macOS
- **Benchmarks** — A benchmark package measures the resolution paths. Its README records a baseline

### Fixes

- **Tasks started in a factory** — A task that a factory or an initializer started got `circularDependency` when it later resolved that service, or a service further up the same resolution chain. With `@Service`, that was a `fatalError`. Such a task also kept the graph-scoped instances of that chain
- **Concurrent registration** — Concurrent `register` calls lost registrations
- **Factory runs once** — Concurrent first resolutions of a singleton or custom-scoped service ran the factory once for each caller. The factory now runs once, and the other callers wait for it
- **False circular dependency** — Two service types with the same short name, such as `A.Config` and `B.Config`, were reported as a cycle. So was a factory that resolved its own type from another environment
- **Crash during reset** — A cached instance whose `deinit` used its environment stopped the process during `resetCaches()`, `resetScope(_:)`, or `resetAll()`
- **Graph scope across environments** — A resolution chain that resolved a graph-scoped type from two environments got the instance of the first environment for both
- `Service` is `Sendable` without `@unchecked`

### Performance

Instructions per operation on an Apple M4 Max with Swift 6.4:

| Operation | 1.3.0 | 1.4.0 |
|---|--:|--:|
| Resolve a cached singleton | 16007 | 953 |
| Resolve a transient service | 16092 | 2796 |
| Resolve a graph-scoped service | 18078 | 5428 |
| Resolve a transient service with two cached dependencies | 42624 | 5031 |
| `@Service`, first access | 19824 | 3905 |
| `@Service`, later accesses | 248 | 148 |
| `@MainService`, later accesses | 766 | 132 |

### Behavior Changes

- A resolution that returns a cached instance runs no cycle check and does not count toward `maxResolutionDepth`
- For a type that is not registered, `notRegistered` is thrown before the cycle check and the depth check
- Registering a type again with another scope drops the instance that was cached for the previous scope. With the same scope, the cached instance stays until a reset
- Registering one type with both `register` and `registerMain` is a programming error and stops a debug build. In a release build, the later registration now replaces the earlier one
- If a reset runs while a factory is running, the resolutions that wait for that factory get its instance, and the instance is not cached
- A factory can run a nested run loop, which can run another task on the same thread. If that task resolves a singleton or custom-scoped service that the thread is creating, the resolution throws `circularDependency`. In 1.3.0 the factory ran a second time
- A factory must not wait for a task that it started if that task resolves the same service. Both then wait for each other. In 1.3.0 the task got `circularDependency`
- The package uses the thread-local storage of the platform's C library. Windows, which was not a supported platform, does not compile

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

[1.4.0]: https://github.com/nslogmeng/swift-service/compare/1.3.0...1.4.0
[1.3.0]: https://github.com/nslogmeng/swift-service/compare/1.2.0...1.3.0
[1.2.0]: https://github.com/nslogmeng/swift-service/compare/1.1.0...1.2.0
[1.1.0]: https://github.com/nslogmeng/swift-service/compare/1.0.0...1.1.0
[1.0.0]: https://github.com/nslogmeng/swift-service/releases/tag/1.0.0
