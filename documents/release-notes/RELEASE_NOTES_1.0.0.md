# Service 1.0.0

🎉 First stable release of Service - a lightweight, zero-dependency, type-safe dependency injection framework for modern Swift.

## ✨ Features

- **Modern Swift**: Built with property wrappers, TaskLocal, and Swift 6 concurrency
- **Zero Dependencies**: No external dependencies, minimal footprint
- **Type-Safe**: Compile-time checked service registration and resolution
- **Thread-Safe**: Full support for Swift 6's strict concurrency model
- **Simple API**: Intuitive registration and injection APIs

## 🚀 Quick Start

```swift
// Register a service
ServiceEnv.current.register(DatabaseProtocol.self) {
    DatabaseService()
}

// Inject and use
struct UserController {
    @Service
    var database: DatabaseProtocol
}
```

## 📦 Installation

```swift
dependencies: [
    .package(url: "https://github.com/nslogmeng/swift-service", from: "1.0.0")
]
```

## 🎯 Platform Support

- iOS 18.0+
- macOS 15.0+
- watchOS 11.0+
- tvOS 18.0+
- visionOS 2.0+

## 📋 Requirements

- Swift 6.0+
- Swift Language Mode v6

## 📚 Documentation

- [README (English)](./README.md)
- [README (中文)](./README_CN.md)

## 🔗 Links

- [GitHub Repository](https://github.com/nslogmeng/swift-service)
- [Report Issues](https://github.com/nslogmeng/swift-service/issues)

---

**Full Changelog**: This is the first stable release. See the [README](./README.md) for complete documentation.
