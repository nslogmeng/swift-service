# ``Service``

##
![Service Logo](logo.png)

A lightweight, zero-dependency, type-safe dependency injection framework for Swift.

> Localization: **English**  |  **[简体中文](<doc:Service.zh-Hans>)**

## Overview

Service is a modern dependency injection framework designed for Swift applications. It leverages Swift's property wrappers, TaskLocal, and concurrency primitives to provide a simple, safe, and powerful way to manage dependencies in your application.

Use this library to manage your application's dependencies with built-in tools that address common needs:

- **Type-Safe Injection**
    
    Use property wrappers to inject services with compile-time type checking, so you don't have to manually manage dependencies.

- **Environment Support**
    
    Switch between different service configurations for production, development, and testing environments.

- **MainActor Support**
    
    Dedicated APIs for UI components and view models that work seamlessly with Swift's concurrency model.

- **Thread Safety**
    
    Safe for concurrent and async code with built-in thread safety guarantees.

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

- <doc:GettingStarted.zh-Hans>
- <doc:BasicUsage.zh-Hans>
- <doc:ServiceEnvironments.zh-Hans>

### Advanced Topics

- <doc:MainActorServices>
- <doc:ServiceAssembly>
- <doc:CircularDependencies>

- <doc:MainActorServices.zh-Hans>
- <doc:ServiceAssembly.zh-Hans>
- <doc:CircularDependencies.zh-Hans>

### Examples

- <doc:RealWorldExamples>

- <doc:RealWorldExamples.zh-Hans>

### Deep Dive

- <doc:UnderstandingService>
- <doc:ConcurrencyModel>

- <doc:UnderstandingService.zh-Hans>
- <doc:ConcurrencyModel.zh-Hans>
