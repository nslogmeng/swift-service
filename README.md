# Service

[![Swift Version](https://img.shields.io/badge/Swift-6.0-F16D39.svg?style=flat)](https://developer.apple.com/swift)
[![GitHub License](https://img.shields.io/github/license/nslogmeng/swift-service)](./LICENSE)
![Build Status](https://github.com/nslogmeng/swift-service/actions/workflows/build.yml/badge.svg?branch=main)
![Test Status](https://github.com/nslogmeng/swift-service/actions/workflows/test.yml/badge.svg?branch=main)

[English](./README.md) | [中文](./README_CN.md)

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
    let database = ServiceEnv.current[DatabaseProtocol.self]
    let logger = ServiceEnv.current[LoggerProtocol.self]
    return UserRepository(database: database, logger: logger)
}
```

## API Reference

### ServiceEnv

Service environment that manages service registration, resolution, and lifecycle.

```swift
// Predefined environments
ServiceEnv.online  // Production environment
ServiceEnv.dev     // Development environment
ServiceEnv.inhouse // Internal testing environment

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
let service = ServiceEnv.current[MyService.self]

// Reset all cached services
ServiceEnv.current.reset()
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

## Why Service?

Service is designed for modern Swift projects that value simplicity, safety, and flexibility.  
It provides a simple, intuitive API with no external dependencies while maintaining type safety and thread safety.

## License

This project is licensed under the MIT License. See the [LICENSE](./LICENSE) file for details.
