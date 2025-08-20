# Service

[![Swift Version](https://img.shields.io/badge/Swift-6.0-F16D39.svg?style=flat)](https://developer.apple.com/swift)
![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/nslogmeng/swift-service/.github%2Fworkflows%2Fswift.yml)
[![GitHub License](https://img.shields.io/github/license/nslogmeng/swift-service)](./LICENSE)

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

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/nslogmeng/swift-service", from: "0.1.2")
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

## Quick Start

### 1. Register a Service

```swift
struct UserRepositoryKey: ServiceKey {
    static func build(with context: ServiceContext) -> UserRepositoryProtocol {
        UserRepositoryImpl()
    }
}
```

### 2. Inject and Use

```swift
struct UserManager {
    @Service(UserRepositoryKey.self)
    var repository: UserRepositoryProtocol

    func createUser(name: String) {
        repository.create(name: name)
    }
}
```

### 3. Custom Scope Example

```swift
struct DatabaseConnectionKey: ServiceKey {
    static var scope: Scope { .shared }
    static func build(with context: ServiceContext) -> DatabaseConnectionProtocol {
        DatabaseConnectionImpl(url: "sqlite://app.db")
    }
}
```

### 4. Environment Switching

```swift
await ServiceEnv.$current.withValue(.dev) {
    // All services resolved here use the dev environment
}
```

## Why Service?

Service is designed for modern Swift projects that value simplicity, safety, and flexibility.  
It provides Swinject-like custom scopes, but with a much simpler API and no external dependencies.
