# Getting Started

Get up and running with Service in minutes.

> Localization: **English**  |  **[简体中文](<doc:GettingStarted.zh-Hans>)**

## Installation

Add Service to your `Package.swift`:

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

### Step 1: Register a Service

Register your services using a factory function:

```swift
import Service

// Register a database service
ServiceEnv.current.register(DatabaseProtocol.self) {
    DatabaseService(connectionString: "sqlite://app.db")
}
```

### Step 2: Inject and Use

Use the `@Service` property wrapper to inject services:

```swift
struct UserManager {
    @Service
    var database: DatabaseProtocol
    
    func createUser(name: String) {
        // Use the injected database service
        database.saveUser(name: name)
    }
}
```

That's it! You're ready to use Service in your application.

## Next Steps

- Learn about <doc:BasicUsage> for more registration patterns
- Explore <doc:ServiceEnvironments> for environment-based configurations
- Check out <doc:RealWorldExamples> for practical examples
