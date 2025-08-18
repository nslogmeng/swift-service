# Service

[![Swift Version](https://img.shields.io/badge/Swift-6.0-F16D39.svg?style=flat)](https://developer.apple.com/swift)
![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/nslogmeng/swift-service/.github%2Fworkflows%2Fswift.yml)
[![License](https://img.shields.io/badge/license-MIT-green)](./LICENSE)

A lightweight, zero-dependency, type-safe dependency injection framework for Swift.  
Inspired by [Swinject](https://github.com/Swinject/Swinject) and [swift-dependencies](https://github.com/pointfreeco/swift-dependencies), Service leverages modern Swift features for simple, robust DI.

## Features

- **Modern Swift**: Uses property wrappers, TaskLocal, and concurrency primitives.
- **Lightweight & Zero Dependency**: No third-party dependencies, minimal footprint.
- **Simple Usage**: Easy to register and inject services.
- **Customizable Scopes**: Singleton, graph, transient, and weak, with Swinject-style extensibility.
- **Type-safe**: Compile-time checked service registration and resolution.
- **Thread-safe**: Safe for concurrent and async code.
- **Environment Support**: Switch between production, development, and testing environments.

## Installation

in `Package.swift` add the following:

```swift
dependencies: [
    .package(url: "https://github.com/nslogmeng/swift-service", from: "0.1.0")
],
targets: [
    .target(
        name: "MyProject",
        dependencies: [
            .product(name: "Service", package: "swift-service"),
        ]
    )
    ...
]
```

## Quick Start

Register a service by conforming to `ServiceKey`:

```swift
struct UserRepository: ServiceKey {
    static func build(with context: ServiceContext) -> UserRepositoryProtocol {
        UserRepositoryImpl()
    }
}
```

Inject and use your service:

```swift
struct UserManager {
    @Service(UserRepository.self)
    var repository: UserRepositoryProtocol

    func createUser(name: String) {
        repository.create(name: name)
    }
}
```

## Advanced Usage

### 1. Custom Scopes

```swift
struct DatabaseConnection: ServiceKey {
    static var scope: Scope { .shared } // Singleton
    static func build(with context: ServiceContext) -> DatabaseConnectionProtocol {
        DatabaseConnectionImpl(url: "sqlite://app.db")
    }
}

struct SessionCache: ServiceKey {
    static var scope: Scope { .transient } // Always new
    static func build(with context: ServiceContext) -> SessionCacheProtocol {
        SessionCacheImpl()
    }
}
```

### 2. Lazy and Transient Injection

```swift
struct AnalyticsManager {
    @LazyService(MachineLearningService.self)
    var mlService: MLServiceProtocol

    func analyze(_ events: [Event]) {
        let result = mlService.analyze(events)
        // ...
    }
}

struct RequestHandler {
    @ServiceProvider(UUIDGenerator.self)
    var idGenerator: UUIDGeneratorProtocol

    func handle(_ request: Request) -> Response {
        let id = idGenerator.generate() // Always fresh
        // ...
    }
}
```

### 3. Environment Switching

```swift
await ServiceEnv.$current.withValue(.dev) {
    // All services resolved here use the dev environment
}
```

### 4. Dependency Graph Example

```swift
struct UserRepository: ServiceKey {
    static func build(with context: ServiceContext) -> UserRepositoryProtocol {
        let db = context.resolve(DatabaseService.self)
        let logger = context.resolve(LoggerService.self)
        return UserRepositoryImpl(database: db, logger: logger)
    }
}
```

### 5. ViewModel Injection (SwiftUI / MVVM)

```swift
final class UserViewModel: ObservableObject {
    @Service(UserRepository.self)
    var repository: UserRepositoryProtocol

    @LazyService(LoggerService.self)
    var logger: LoggerProtocol

    func loadUser(id: String) {
        logger.info("Loading user \(id)")
        let user = repository.fetch(id: id)
        // update UI...
    }
}
```

### 6. Networking and Caching

```swift
struct NetworkService: ServiceKey {
    static var scope: Scope { .shared }
    static func build(with context: ServiceContext) -> NetworkClientProtocol {
        NetworkClient(baseURL: "https://api.example.com")
    }
}

struct ImageCache: ServiceKey {
    static var scope: Scope { .weak }
    static func build(with context: ServiceContext) -> ImageCacheProtocol {
        ImageCacheImpl()
    }
}

struct ImageLoader {
    @Service(NetworkService.self)
    var network: NetworkClientProtocol

    @Service(ImageCache.self)
    var cache: ImageCacheProtocol

    func loadImage(url: String) -> Image? {
        if let cached = cache.get(url) { return cached }
        let image = network.downloadImage(url: url)
        cache.set(url, image)
        return image
    }
}
```

### 7. Feature Flag and A/B Testing

```swift
struct FeatureFlagService: ServiceKey {
    static var scope: Scope { .shared }
    static func build(with context: ServiceContext) -> FeatureFlagProtocol {
        FeatureFlagManager()
    }
}

struct HomeView {
    @Service(FeatureFlagService.self)
    var flags: FeatureFlagProtocol

    var showNewFeature: Bool {
        flags.isEnabled("new_home_feature")
    }
}
```

### 8. Local Storage and Preferences

```swift
struct PreferencesService: ServiceKey {
    static var scope: Scope { .shared }
    static func build(with context: ServiceContext) -> PreferencesProtocol {
        PreferencesImpl()
    }
}

struct SettingsViewModel {
    @Service(PreferencesService.self)
    var preferences: PreferencesProtocol

    func updateTheme(_ theme: Theme) {
        preferences.setTheme(theme)
    }
}
```

## Why Service?

Service is designed for modern Swift projects that value simplicity, safety, and flexibility.  
It provides Swinject-like custom scopes, but with a much simpler API and no external dependencies.
