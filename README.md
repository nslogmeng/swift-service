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

### 5. MainActor Services (UI Components)

For UI-related services that must run on the main actor (e.g., view models, UI controllers), swift-service provides dedicated MainActor-safe APIs.

**Background**: In Swift 6's strict concurrency model, `@MainActor` classes are thread-safe (all access is serialized on the main thread) but are NOT automatically `Sendable`. This means they cannot be used with the standard `register`/`resolve` APIs which require `Sendable` conformance.

```swift
// Define a MainActor service (does NOT need to conform to Sendable)
@MainActor
final class ViewModelService {
    var data: String = ""
    func loadData() { data = "loaded" }
}

// Register on main actor context
await MainActor.run {
    ServiceEnv.current.registerMain(ViewModelService.self) {
        ViewModelService()
    }
}

// Resolve using direct method
@MainActor
func setupUI() {
    let viewModel = ServiceEnv.current.resolveMain(ViewModelService.self)
    viewModel.loadData()
}

// Or use the @MainService property wrapper
@MainActor
class MyViewController {
    @MainService
    var viewModel: ViewModelService
}
```

### 6. Service Assembly (Standardized Registration)

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

// Register MainActor service (for UI components)
await MainActor.run {
    ServiceEnv.current.registerMain(ViewModelService.self) {
        ViewModelService()
    }
}

// Resolve MainActor service
@MainActor
func example() {
    let viewModel = ServiceEnv.current.resolveMain(ViewModelService.self)
}

// Reset cached services (keeps registered providers)
// Services will be recreated on next resolution
// This is async to ensure all caches (including MainActor) are cleared
await ServiceEnv.current.resetCaches()

// Reset everything (clears cache and removes all providers)
// All services must be re-registered after this
await ServiceEnv.current.resetAll()
```

### @Service

Property wrapper for injecting Sendable services.

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

### @MainService

Property wrapper for injecting MainActor-isolated services. Use this for UI components like view models and controllers that don't conform to `Sendable`.

```swift
@MainActor
class MyViewController {
    // Type inferred from property type
    @MainService
    var viewModel: ViewModelService

    // Explicit type specification
    @MainService(ViewModelService.self)
    var anotherViewModel: ViewModelService
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

## Circular Dependency Detection

Service automatically detects circular dependencies at runtime and provides clear error messages to help you identify and fix dependency cycles.

### How It Works

When resolving services, Service tracks the current resolution chain. If a service attempts to resolve itself (directly or indirectly), a circular dependency is detected and the program terminates with a descriptive error.

```swift
// Example of circular dependency:
// A depends on B, B depends on C, C depends on A

ServiceEnv.current.register(AService.self) {
    let b = ServiceEnv.current.resolve(BService.self)  // Resolves B
    return AService(b: b)
}

ServiceEnv.current.register(BService.self) {
    let c = ServiceEnv.current.resolve(CService.self)  // Resolves C
    return BService(c: c)
}

ServiceEnv.current.register(CService.self) {
    let a = ServiceEnv.current.resolve(AService.self)  // Cycle detected!
    return CService(a: a)
}
```

### Error Messages

When a circular dependency is detected, you'll see a clear error message showing the full dependency chain:

```
Circular dependency detected for service 'AService'.
Dependency chain: AService -> BService -> CService -> AService
Check your service registration to break the cycle.
```

### Resolution Depth Limit

To prevent stack overflow from excessively deep dependency chains, Service enforces a maximum resolution depth of 100. If exceeded:

```
Maximum resolution depth (100) exceeded.
Current chain: ServiceA -> ServiceB -> ... -> ServiceN
This may indicate a circular dependency or overly deep dependency graph.
```

### Breaking Circular Dependencies

Common strategies to break circular dependencies:

1. **Restructure your services**: Extract shared logic into a new service that both can depend on.
2. **Use lazy resolution**: Defer resolution until the service is actually needed.
3. **Use property injection**: Inject dependencies after construction instead of in the factory.

## Why Service?

Service is designed for modern Swift projects that value simplicity, safety, and flexibility.  
It provides a simple, intuitive API with no external dependencies while maintaining type safety and thread safety.

## License

This project is licensed under the MIT License. See the [LICENSE](./LICENSE) file for details.
