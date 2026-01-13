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

## Environment Switching with Assembly Structure

One of the key benefits of Service environments is the ability to switch environments while maintaining the same Assembly structure. This is particularly valuable in large projects where you want to keep service registration organized and consistent across different contexts.

### Switching Environments at the Outermost Scope

In tests, you can switch to a `.test` environment at the outermost scope and keep the same Assembly structure:

```swift
await ServiceEnv.$current.withValue(.test) {
    ServiceEnv.current.assemble([
        AppAssembly()
        // ... other assemblies
    ])

    // Run your test logic inside the .test environment
}
```

This approach ensures that:
- The same Assembly structure is used across all environments
- Service registration logic remains consistent and maintainable
- Environment-specific behavior is isolated to the environment switch
- Test setup is clean and straightforward

### Conditional Registration in Assemblies

Inside an Assembly, you can conditionally register services based on the environment while keeping the overall structure identical:

```swift
struct AppAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        if env == .test {
            env.register(Localization.self) { MockLocalization() }
        } else {
            env.register(Localization.self) { Localization() }
        }

        // Keep the rest identical across all environments
        env.register(ThemeManager.self) { ThemeManager() }
    }
}
```

This pattern is especially useful in large projects where:
- You want to maintain a consistent service registration structure
- Only a few services need environment-specific implementations
- The majority of services remain the same across environments
- You need to easily switch between production and test configurations

## Thread Safety

Environments use `TaskLocal` storage, ensuring thread-safe access across async contexts. Each task maintains its own environment context, making it safe to use in concurrent code.
