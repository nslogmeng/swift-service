# ``Service``

##
![Service Logo](logo.png)

A lightweight, zero-dependency, type-safe dependency injection framework for Swift.

> Localization: **English**  |  **[简体中文](https://nslogmeng.github.io/swift-service/zh-Hans/documentation/service/)**

## Overview

Service is a modern dependency injection framework designed for Swift applications. It leverages Swift's property wrappers, TaskLocal, and concurrency primitives to provide a simple, safe, and powerful way to manage dependencies in your application.

Use this library to manage your application's dependencies with built-in tools that address common needs:

- **Concurrency-Native API**

    Two API tracks designed for Swift 6's concurrency model: `register`/`resolve` for Sendable services, `registerMain`/`resolveMain` for MainActor-isolated services. The compiler enforces correct usage.

- **Flexible Scopes**

    Singleton, transient, graph, and custom named scopes give you fine-grained control over service instance lifecycle.

- **Four Property Wrappers**

    `@Service` and `@MainService` for lazy cached injection; `@Provider` and `@MainProvider` for scope-driven resolution. All support optional types for graceful nil handling.

- **Environment Isolation**

    TaskLocal-based environment switching for production, development, and testing — tests can run in parallel without polluting each other.

- **Zero Dependencies**

    No external dependencies, minimal footprint, perfect for any Swift project.

## Usage

Start using Service in three simple steps:

```swift
import Service

// 1. Register a service
ServiceEnv.current.register(DatabaseProtocol.self) {
    DatabaseService(connectionString: "sqlite://app.db")
}

// 2. Inject using property wrapper
struct UserRepository {
    @Service
    var database: DatabaseProtocol
    
    func fetchUser(id: String) -> User? {
        return database.findUser(id: id)
    }
}

// 3. Use in your code
let repository = UserRepository()
let user = repository.fetchUser(id: "123")
```

## Links

- [GitHub Repository](https://github.com/nslogmeng/swift-service)
- [Installation Instructions](https://github.com/nslogmeng/swift-service#-installation)

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:BasicUsage>
- <doc:ServiceEnvironments>

### Advanced Topics

- <doc:MainActorServices>
- <doc:ServiceAssembly>
- <doc:ErrorHandling>
- <doc:CircularDependencies>

### Examples

- <doc:RealWorldExamples>

### Deep Dive

- <doc:Vision>
- <doc:UnderstandingService>
- <doc:ConcurrencyModel>
