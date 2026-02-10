<div align="center">
  <img src="./images/logo.png" alt="Service Logo">
</div>

# Service

[![Swift Version Status](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fnslogmeng%2Fswift-service%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/nslogmeng/swift-service)
[![Platform Support Status](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fnslogmeng%2Fswift-service%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/nslogmeng/swift-service)
[![Build Status](https://github.com/nslogmeng/swift-service/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/nslogmeng/swift-service/actions/workflows/build.yml)
[![Test Status](https://github.com/nslogmeng/swift-service/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/nslogmeng/swift-service/actions/workflows/test.yml)
[![Documentation](https://img.shields.io/badge/Documentation-available-blue)](https://nslogmeng.github.io/swift-service/documentation/service/?utm_source=github&utm_medium=referral&utm_campaign=service-github&utm_content=readme-badge)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/nslogmeng/swift-service)

<div align="center">
    <strong>English</strong> | <a href="./README.zh-Hans.md"><strong>简体中文</strong></a>
</div>
<br/>

A lightweight dependency injection framework built for Swift 6 concurrency — with explicit Sendable and MainActor APIs, zero external dependencies, and TaskLocal-based environment isolation.

## Core Features

- **Concurrency-First Design** — Swift concurrency is a first-class citizen. Sendable and MainActor constraints are part of the API, enforced by the compiler at every call site — not hidden behind `@unchecked Sendable`.
- **Native MainActor Support** — Dedicated `registerMain()` / `@MainService` / `@MainProvider` for MainActor-isolated types. Aligned with Swift 6.2 Approachable Concurrency.
- **Zero Dependencies** — Built entirely on Swift standard library primitives (`Synchronization.Mutex`, `@TaskLocal`).
- **TaskLocal Environment Isolation** — Per-task environment switching for parallel-safe testing. No global state mutation needed.
- **Flexible Scopes** — Singleton, transient, graph, and custom named scopes for fine-grained lifecycle control.
- **Familiar Patterns** — register/resolve API inspired by Swinject. Property wrapper injection with modular Assembly support.

## Quick Start

### 1. Register Services

```swift
import Service

// Sendable services — safe across threads
ServiceEnv.current.register(DatabaseProtocol.self) {
    DatabaseService(connectionString: "sqlite://app.db")
}

// MainActor services — for UI components, no @unchecked Sendable needed
ServiceEnv.current.registerMain(UserViewModel.self) {
    UserViewModel()
}
```

### 2. Inject Dependencies

```swift
struct UserRepository {
    @Service var database: DatabaseProtocol

    func fetchUser(id: String) -> User? {
        return database.findUser(id: id)
    }
}

@MainActor
struct UserView: View {
    @MainService var viewModel: UserViewModel

    var body: some View {
        Text(viewModel.userName)
    }
}
```

### 3. Use Services

```swift
let repository = UserRepository()
let user = repository.fetchUser(id: "123")
// database is automatically injected, no manual passing needed!
```

### Test Environment Switching

```swift
await ServiceEnv.$current.withValue(.test) {
    ServiceEnv.current.register(DatabaseProtocol.self) {
        MockDatabase()
    }

    let repository = UserRepository()
    // All resolutions use test environment
}
```

## Service Scopes

Control how service instances are created and cached:

```swift
// Singleton (default) — same instance reused globally
env.register(DatabaseService.self) { DatabaseService() }

// Transient — new instance every time
env.register(RequestHandler.self, scope: .transient) { RequestHandler() }

// Graph — shared within the same resolution chain
env.register(UnitOfWork.self, scope: .graph) { UnitOfWork() }

// Custom — named scope, can be selectively cleared
env.register(SessionService.self, scope: .custom("user-session")) { SessionService() }
env.resetScope(.custom("user-session"))  // Clear only this scope
```

### Property Wrappers

Service provides four property wrappers in a 2x2 matrix:

|  | **Sendable** | **MainActor** |
|---|---|---|
| **Lazy + cached** | `@Service` | `@MainService` |
| **Scope-driven** | `@Provider` | `@MainProvider` |

- **`@Service` / `@MainService`**: Resolves once on first access, caches the result internally.
- **`@Provider` / `@MainProvider`**: Resolves on every access, caching behavior follows the registered scope.

```swift
@Provider var handler: RequestHandler   // transient → new instance each access
@Service var database: DatabaseProtocol // singleton → resolved once, cached
```

All four support optional types — returns `nil` instead of crashing when the service is not registered:

```swift
@Service var analytics: AnalyticsService?
@Provider var tracker: TrackingService?
```

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/nslogmeng/swift-service", .upToNextMajor(from: "1.0.0"))
],
targets: [
    .target(
        name: "MyProject",
        dependencies: [
            .product(name: "Service", package: "swift-service"),
        ]
    )
]
```

## Documentation

For comprehensive guides, tutorials, and API reference, see the [Service Documentation](https://nslogmeng.github.io/swift-service/documentation/service/?utm_source=github&utm_medium=referral&utm_campaign=service-github&utm_content=readme-docs).

## Why Service?

```swift
// Traditional way: manually pass every dependency
class UserService {
    init(database: DatabaseProtocol, logger: LoggerProtocol) { ... }
}
let service = UserService(database: db, logger: logger)

// Service way: automatic injection
class UserService {
    @Service var database: DatabaseProtocol
    @Service var logger: LoggerProtocol
}
let service = UserService()  // Dependencies automatically injected!
```

Service uses the familiar register/resolve patterns from traditional DI containers. The key difference: concurrency constraints are part of the API, not hidden behind `@unchecked Sendable`. When you register with `register()`, the service must be `Sendable`. When you register with `registerMain()`, it lives on the main actor. The compiler enforces this at every call site — catching threading mistakes at build time, not runtime.

## Acknowledgments

Service was inspired by the excellent work of [Swinject](https://github.com/Swinject/Swinject) and [swift-dependencies](https://github.com/pointfreeco/swift-dependencies).

## License

This project is licensed under the MIT License. See the [LICENSE](./LICENSE) file for details.
