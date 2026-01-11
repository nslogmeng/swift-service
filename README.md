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
    <strong>English</strong> | <a href="./README.zh-Hans.md"><strong>简体中文</strong></a>
</div>
<br/>

A lightweight, zero-dependency, type-safe dependency injection framework for Swift.  
Inspired by [Swinject](https://github.com/Swinject/Swinject) and [swift-dependencies](https://github.com/pointfreeco/swift-dependencies), Service leverages modern Swift features for simple, robust DI.

## ✨ Features

- **🚀 Modern Swift**: Uses property wrappers, TaskLocal, and concurrency primitives
- **📦 Zero Dependency**: No third-party dependencies, minimal footprint
- **🎯 Type-safe**: Compile-time checked service registration and resolution
- **🔒 Thread-safe**: Safe for concurrent and async code
- **🌍 Environment Support**: Switch between production, development, and testing environments
- **🎨 MainActor Support**: Dedicated APIs for UI components and view models
- **🔍 Circular Dependency Detection**: Automatic detection with clear error messages

## 📦 Installation

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

## 🚀 Quick Start

### Register and Inject

```swift
import Service

// Register a service
ServiceEnv.current.register(DatabaseProtocol.self) {
    DatabaseService(connectionString: "sqlite://app.db")
}

// Use the @Service property wrapper
struct UserRepository {
    @Service
    var database: DatabaseProtocol
    
    func fetchUser(id: String) -> User? {
        return database.findUser(id: id)
    }
}
```

### MainActor Services (UI Components)

```swift
// Register MainActor service
await MainActor.run {
    ServiceEnv.current.registerMain(UserViewModel.self) {
        UserViewModel()
    }
}

// Use @MainService in your views
@MainActor
class UserViewController {
    @MainService
    var viewModel: UserViewModel
}
```

### Environment Switching

```swift
// Switch to test environment
await ServiceEnv.$current.withValue(.test) {
    // All services use test environment
    let service = ServiceEnv.current.resolve(MyService.self)
}
```

## 📚 Documentation

For comprehensive documentation, tutorials, and examples, see the [Service Documentation](https://swiftpackageindex.com/nslogmeng/swift-service/documentation/service).

### Topics

- **[Getting Started](https://swiftpackageindex.com/nslogmeng/swift-service/documentation/service/gettingstarted)** - Quick setup guide
- **[Basic Usage](https://swiftpackageindex.com/nslogmeng/swift-service/documentation/service/basicusage)** - Core patterns and examples
- **[MainActor Services](https://swiftpackageindex.com/nslogmeng/swift-service/documentation/service/mainactorservices)** - Working with UI components
- **[Service Assembly](https://swiftpackageindex.com/nslogmeng/swift-service/documentation/service/serviceassembly)** - Organizing service registrations
- **[Real-World Examples](https://swiftpackageindex.com/nslogmeng/swift-service/documentation/service/realworldexamples)** - Practical use cases
- **[Understanding Service](https://swiftpackageindex.com/nslogmeng/swift-service/documentation/service/understandingservice)** - Deep dive into architecture

## 💡 Why Service?

Service is designed for modern Swift projects that value:

- **Simplicity**: Clean, intuitive API that's easy to learn and use
- **Safety**: Type-safe and thread-safe by design
- **Flexibility**: Support for both Sendable and MainActor services
- **Zero Overhead**: No external dependencies, minimal runtime cost

Perfect for SwiftUI apps, server-side Swift, and any Swift project that needs dependency injection.

## 📄 License

This project is licensed under the MIT License. See the [LICENSE](./LICENSE) file for details.
