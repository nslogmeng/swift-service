<div align="center">
  <img src="./images/logo.png" alt="Service Logo">
</div>

# Service

[![GitHub License](https://img.shields.io/github/license/nslogmeng/swift-service)](./LICENSE)
[![Swift Version Status](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fnslogmeng%2Fswift-service%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/nslogmeng/swift-service)
[![Platform Support Status](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fnslogmeng%2Fswift-service%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/nslogmeng/swift-service)
[![Build Status](https://github.com/nslogmeng/swift-service/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/nslogmeng/swift-service/actions/workflows/build.yml)
[![Test Status](https://github.com/nslogmeng/swift-service/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/nslogmeng/swift-service/actions/workflows/test.yml)

<div align="center">
    English | <a href="./README_CN.md">简体中文</a>
</div>
<br/>

A lightweight, zero-dependency, type-safe dependency injection framework for Swift.  
Inspired by [Swinject](https://github.com/Swinject/Swinject) and [swift-dependencies](https://github.com/pointfreeco/swift-dependencies), Service leverages modern Swift features for simple, robust DI.

## Features

- **Modern Swift**: Uses property wrappers, TaskLocal, and concurrency primitives.
- **Lightweight & Zero Dependency**: No third-party dependencies, minimal footprint.
- **Simple Usage**: Easy to register and inject services.
- **Type-safe**: Compile-time checked service registration and resolution.
- **Thread-safe**: Safe for concurrent and async code.
- **Environment Support**: Switch between production, development, and testing environments.

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

## Quick Start

### 1. Register a Service

Register using a factory function:

```swift
ServiceEnv.current.register(DatabaseProtocol.self) {
    DatabaseService(connectionString: "sqlite://app.db")
}
```

Or register a service instance directly:

```swift
let database = DatabaseService(connectionString: "sqlite://app.db")
ServiceEnv.current.register(database)
```

Or use the `ServiceKey` protocol:

```swift
struct DatabaseService: ServiceKey {
    static var `default`: DatabaseService {
        DatabaseService(connectionString: "sqlite://app.db")
    }
}

// Register
ServiceEnv.current.register(DatabaseService.self)
```

### 2. Inject and Use

Use the `@Service` property wrapper to inject services:

```swift
struct UserManager {
    @Service
    var database: DatabaseProtocol
    
    @Service
    var logger: LoggerProtocol
    
    func createUser(name: String) {
        logger.info("Creating user: \(name)")
        // Use database...
    }
}
```

You can also explicitly specify the service type:

```swift
struct UserManager {
    @Service(DatabaseProtocol.self)
    var database: DatabaseProtocol
}
```

### 3. Environment Switching Example

Use different service configurations in different environments (production, development, testing):

```swift
// Switch to dev environment in tests
await ServiceEnv.$current.withValue(.dev) {
    // All services resolved in this block use dev environment
    let userService = UserService()
    let result = userService.createUser(name: "Test User")
}
```

### 4. Dependency Injection Example

Services can depend on other services:

```swift
// Register base services
ServiceEnv.current.register(DatabaseProtocol.self) {
    DatabaseService()
}

ServiceEnv.current.register(LoggerProtocol.self) {
    LoggerService()
}

// Register a service that depends on other services
ServiceEnv.current.register(UserRepositoryProtocol.self) {
    let database = ServiceEnv.current.resolve(DatabaseProtocol.self)
    let logger = ServiceEnv.current.resolve(LoggerProtocol.self)
    return UserRepository(database: database, logger: logger)
}
```

### 5. Service Assembly (Standardized Registration)

For better organization and reusability, use `ServiceAssembly` to group related service registrations:

```swift
// Define an assembly
struct DatabaseAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.register(DatabaseProtocol.self) {
            DatabaseService(connectionString: "sqlite://app.db")
        }
    }
}

struct NetworkAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.register(NetworkServiceProtocol.self) {
            let logger = env.resolve(LoggerProtocol.self)
            return NetworkService(baseURL: "https://api.example.com", logger: logger)
        }
    }
}

// Assemble assemblies (must be called from @MainActor context)
// In SwiftUI apps, this is usually already on the main actor
ServiceEnv.current.assemble(DatabaseAssembly())

// Or assemble multiple assemblies at once
ServiceEnv.current.assemble([
    DatabaseAssembly(),
    NetworkAssembly(),
    RepositoryAssembly()
])
```

**Note:** `ServiceAssembly` and its `assemble` methods are marked with `@MainActor` for thread safety. In SwiftUI apps, you're typically already on the main actor, so no special handling is needed. In other contexts, use `await MainActor.run { }` to call `assemble`.

This provides a standardized, modular way to organize service registrations, similar to Swinject's Assembly pattern.

## API Reference

### ServiceEnv

Service environment that manages service registration, resolution, and lifecycle.

```swift
// Predefined environments
ServiceEnv.online  // Production environment
ServiceEnv.test    // Testing environment
ServiceEnv.dev     // Development environment

// Create custom environment
let testEnv = ServiceEnv(name: "test")

// Switch environment
await ServiceEnv.$current.withValue(.dev) {
    // Use dev environment
}

// Register service with factory
ServiceEnv.current.register(MyService.self) {
    MyService()
}

// Register service instance directly
let service = MyService()
ServiceEnv.current.register(service)

// Resolve service
let service = ServiceEnv.current.resolve(MyService.self)

// Reset cached services (keeps registered providers)
// Services will be recreated on next resolution
ServiceEnv.current.resetCaches()

// Reset everything (clears cache and removes all providers)
// All services must be re-registered after this
ServiceEnv.current.resetAll()
```

### @Service

Property wrapper for injecting services.

```swift
struct MyController {
    // Type inferred from property type
    @Service
    var myService: MyService
    
    // Explicit type specification
    @Service(MyService.self)
    var anotherService: MyService
}
```

### ServiceKey

Protocol for defining default service implementations.

```swift
struct MyService: ServiceKey {
    static var `default`: MyService {
        MyService()
    }
}
```

### ServiceAssembly

Protocol for organizing service registrations in a modular, reusable way.

**Why `@MainActor`?**
Service assembly typically occurs during application initialization, which is a very early stage of the application lifecycle. Assembly operations are strongly dependent on execution order and are usually performed in `main.swift` or SwiftUI App's `init` method, where the code is already running on the main actor. Constraining assembly operations to the main actor ensures thread safety and provides a predictable, sequential execution context for service registration.

**Note:** `ServiceAssembly` is marked with `@MainActor` for thread safety. The `assemble` methods must be called from the main actor context.

```swift
struct MyAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.register(MyService.self) {
            MyService()
        }
    }
}

// Assemble a single assembly (must be on @MainActor)
ServiceEnv.current.assemble(MyAssembly())

// Assemble multiple assemblies
ServiceEnv.current.assemble([
    DatabaseAssembly(),
    NetworkAssembly()
])

// Or using variadic arguments
ServiceEnv.current.assemble(
    DatabaseAssembly(),
    NetworkAssembly()
)

// If not on the main actor, use:
await MainActor.run {
    ServiceEnv.current.assemble(MyAssembly())
}
```

## Why Service?

Service is designed for modern Swift projects that value simplicity, safety, and flexibility.  
It provides a simple, intuitive API with no external dependencies while maintaining type safety and thread safety.

## License

This project is licensed under the MIT License. See the [LICENSE](./LICENSE) file for details.
