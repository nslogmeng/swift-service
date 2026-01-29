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

A lightweight, zero-dependency, type-safe dependency injection framework designed for modern Swift projects.

Elegant dependency injection through `@Service` property wrapper with familiar register/resolve patterns. Built for Swift 6 concurrency with TaskLocal-based environment isolation. Get started in minutes.

## ✨ Core Features

- **🚀 Modern Swift**: Uses property wrappers, TaskLocal, and concurrency primitives, fully leverages modern Swift features
- **🎯 Simple API, Ready to Use**: Use `@Service` property wrapper, no manual dependency passing needed, cleaner code
- **📦 Zero Dependencies, Lightweight**: No third-party dependencies, adds no burden to your project, perfect for any Swift project
- **🔒 Type-Safe, Compile-Time Checked**: Leverages Swift's type system to catch errors at compile time
- **⚡ Thread-Safe, Concurrency-Friendly**: Built-in thread safety guarantees, perfect support for Swift 6 concurrency model
- **🌍 Environment Isolation, Test-Friendly**: Task-level environment switching based on TaskLocal, easily swap dependencies in tests
- **🎨 MainActor Support**: Dedicated `@MainService` API for SwiftUI view models and UI components
- **🔍 Automatic Circular Dependency Detection**: Runtime detection of circular dependencies with clear error messages
- **🧩 Modular Assembly**: Organize service registrations through ServiceAssembly pattern for clearer code structure

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

Get started with Service in just three steps:

### 1. Register Services

```swift
import Service

// Register a service (supports both protocols and concrete types)
ServiceEnv.current.register(DatabaseProtocol.self) {
    DatabaseService(connectionString: "sqlite://app.db")
}
```

### 2. Inject Dependencies

Use the `@Service` property wrapper to automatically resolve dependencies:

```swift
struct UserRepository {
    @Service
    var database: DatabaseProtocol
    
    func fetchUser(id: String) -> User? {
        return database.findUser(id: id)
    }
}
```

### 3. Use Services

```swift
let repository = UserRepository()
let user = repository.fetchUser(id: "123")
// database is automatically injected, no manual passing needed!
```

### 🎨 SwiftUI View Model Support

```swift
// Register MainActor service
ServiceEnv.current.registerMain(UserViewModel.self) {
    UserViewModel()
}

// Use @MainService in your views
struct UserView: View {
    @MainService
    var viewModel: UserViewModel
    
    var body: some View {
        Text(viewModel.userName)
    }
}
```

### 🧪 Test Environment Switching

```swift
// Switch to test environment in tests
await ServiceEnv.$current.withValue(.test) {
    // Register mock services for testing
    ServiceEnv.current.register(DatabaseProtocol.self) {
        MockDatabase()
    }
    
    // All service resolutions use test environment
    let repository = UserRepository()
    // Test with mock database...
}
```

## 📚 Documentation

For comprehensive documentation, tutorials, and examples, see the [Service Documentation](https://nslogmeng.github.io/swift-service/documentation/service/?utm_source=github&utm_medium=referral&utm_campaign=service-github&utm_content=readme-docs).

### Topics

#### Essentials

- **[Getting Started](https://nslogmeng.github.io/swift-service/documentation/service/gettingstarted/?utm_source=github&utm_medium=referral&utm_campaign=service-github&utm_content=readme-docs)** - Quick setup guide
- **[Basic Usage](https://nslogmeng.github.io/swift-service/documentation/service/basicusage/?utm_source=github&utm_medium=referral&utm_campaign=service-github&utm_content=readme-docs)** - Core patterns and examples
- **[Service Environments](https://nslogmeng.github.io/swift-service/documentation/service/serviceenvironments/?utm_source=github&utm_medium=referral&utm_campaign=service-github&utm_content=readme-docs)** - Managing different service configurations

#### Advanced Topics

- **[MainActor Services](https://nslogmeng.github.io/swift-service/documentation/service/mainactorservices/?utm_source=github&utm_medium=referral&utm_campaign=service-github&utm_content=readme-docs)** - Working with UI components
- **[Service Assembly](https://nslogmeng.github.io/swift-service/documentation/service/serviceassembly/?utm_source=github&utm_medium=referral&utm_campaign=service-github&utm_content=readme-docs)** - Organizing service registrations
- **[Error Handling](https://nslogmeng.github.io/swift-service/documentation/service/errorhandling/?utm_source=github&utm_medium=referral&utm_campaign=service-github&utm_content=readme-docs)** - Handling service resolution errors
- **[Circular Dependencies](https://nslogmeng.github.io/swift-service/documentation/service/circulardependencies/?utm_source=github&utm_medium=referral&utm_campaign=service-github&utm_content=readme-docs)** - Understanding and avoiding circular dependencies

#### Examples

- **[Real-World Examples](https://nslogmeng.github.io/swift-service/documentation/service/realworldexamples/?utm_source=github&utm_medium=referral&utm_campaign=service-github&utm_content=readme-docs)** - Practical use cases

#### Deep Dive

- **[Understanding Service](https://nslogmeng.github.io/swift-service/documentation/service/understandingservice/?utm_source=github&utm_medium=referral&utm_campaign=service-github&utm_content=readme-docs)** - Deep dive into architecture
- **[Concurrency Model](https://nslogmeng.github.io/swift-service/documentation/service/concurrencymodel/?utm_source=github&utm_medium=referral&utm_campaign=service-github&utm_content=readme-docs)** - Understanding Service's concurrency model

## 💡 Why Service?

### 🎯 Extremely Easy to Learn

If you're familiar with traditional dependency injection patterns (like Swinject), Service will feel very familiar. With property wrappers, you don't even need to manually pass dependencies:

```swift
// Traditional way: need to manually pass dependencies
class UserService {
    init(database: DatabaseProtocol, logger: LoggerProtocol) { ... }
}
let service = UserService(database: db, logger: logger)

// Service way: automatic injection, cleaner code
class UserService {
    @Service var database: DatabaseProtocol
    @Service var logger: LoggerProtocol
}
let service = UserService()  // Dependencies automatically injected!
```

### 🚀 Built for Modern Swift

- **Swift 6 Concurrency Model**: Perfect support for `Sendable` and `@MainActor`, with dedicated APIs for UI services
- **TaskLocal Environment Isolation**: Task-based environment switching, no need to modify global state in tests
- **Property Wrappers**: Leverages modern Swift features for elegant dependency injection

### 🛡️ Safe and Reliable

- **Compile-Time Type Checking**: Leverages Swift's type system to catch errors at compile time
- **Thread Safety Guarantees**: Built-in locking mechanism, supports concurrent access
- **Circular Dependency Detection**: Automatic runtime detection and reporting of circular dependencies

### 📦 Lightweight, Zero Burden

- **Zero Dependencies**: No third-party dependencies, won't add complexity to your project
- **Minimal Runtime Cost**: Efficient implementation with minimal impact on app performance
- **Wide Applicability**: Perfect for SwiftUI apps, server-side Swift, command-line tools, and any Swift project

### 🧩 Flexible and Powerful

- **Multiple Registration Methods**: Supports factory functions, direct instances, and ServiceKey protocol
- **Modular Assembly**: Organize service registrations through ServiceAssembly for clearer code structure
- **Environment Isolation**: Production, development, and test environments are completely isolated

## 🙏 Acknowledgments

Service was inspired by the excellent work of [Swinject](https://github.com/Swinject/Swinject) and [swift-dependencies](https://github.com/pointfreeco/swift-dependencies).

## 📄 License

This project is licensed under the MIT License. See the [LICENSE](./LICENSE) file for details.
