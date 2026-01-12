# Service Environments

Service supports multiple environments, allowing you to configure different service implementations for production, development, and testing.

> Localization: **English**  |  **[简体中文](https://nslogmeng.github.io/swift-service/zh-Hans/documentation/service/serviceenvironments)**

## Predefined Environments

Service provides three predefined environments:

```swift
ServiceEnv.online  // Production environment
ServiceEnv.dev     // Development environment
ServiceEnv.test    // Testing environment
```

## Using Environments

### Default Environment

By default, Service uses the `online` environment:

```swift
// Uses online environment
ServiceEnv.current.register(DatabaseProtocol.self) {
    DatabaseService(connectionString: "prod://database")
}
```

### Switching Environments

Use `withValue` to temporarily switch to a different environment:

```swift
// Switch to dev environment for testing
await ServiceEnv.$current.withValue(.dev) {
    // All services resolved in this block use dev environment
    let userService = UserService()
    let result = userService.createUser(name: "Test User")
}
```

### Environment-Specific Registration

Each environment maintains its own service registry. Register services in the appropriate environment:

```swift
// Register production database
ServiceEnv.online.register(DatabaseProtocol.self) {
    DatabaseService(connectionString: "prod://database")
}

// Register development database
ServiceEnv.dev.register(DatabaseProtocol.self) {
    DatabaseService(connectionString: "dev://database")
}

// Register test database (in-memory)
ServiceEnv.test.register(DatabaseProtocol.self) {
    InMemoryDatabase()
}
```

## Real-World Example

Here's how you might set up different configurations for different environments:

```swift
// In your app initialization
func setupServices() {
    let env = ServiceEnv.current
    
    if ProcessInfo.processInfo.environment["ENVIRONMENT"] == "development" {
        env.register(APIClientProtocol.self) {
            APIClient(baseURL: "https://dev-api.example.com")
        }
    } else {
        env.register(APIClientProtocol.self) {
            APIClient(baseURL: "https://api.example.com")
        }
    }
}
```

## Custom Environments

Create custom environments for specific use cases:

```swift
let stagingEnv = ServiceEnv(name: "staging")

stagingEnv.register(DatabaseProtocol.self) {
    DatabaseService(connectionString: "staging://database")
}
```

## Testing with Environments

Environments are particularly useful in tests:

```swift
func testUserCreation() async throws {
    // Use test environment
    await ServiceEnv.$current.withValue(.test) {
        // Register mock services
        ServiceEnv.current.register(DatabaseProtocol.self) {
            MockDatabase()
        }
        
        // Test your code
        let userService = UserService()
        let user = userService.createUser(name: "Test")
        XCTAssertNotNil(user)
    }
}
```

## Thread Safety

Environments use `TaskLocal` storage, ensuring thread-safe access across async contexts. Each task maintains its own environment context, making it safe to use in concurrent code.
