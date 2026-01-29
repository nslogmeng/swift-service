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

## Resetting Services

Service provides two methods to reset service state, which are essential for testing scenarios and environment management.

### resetCaches()

The `resetCaches()` method clears all cached service instances while preserving registered service providers. Services will be recreated on the next resolution using their registered factory functions.

```swift
// Register a service
ServiceEnv.current.register(String.self) {
    UUID().uuidString
}

// Resolve and cache the service
let service1 = try ServiceEnv.current.resolve(String.self)

// Clear cache - next resolution will create a new instance
await ServiceEnv.current.resetCaches()
let service2 = try ServiceEnv.current.resolve(String.self)
// service1 != service2 (new instance created)
```

**When to use:**
- Force services to be recreated without re-registering them
- Get fresh instances in testing scenarios
- Clear cached state while maintaining service registration

### resetAll()

The `resetAll()` method clears all cached service instances and removes all registered service providers. This completely resets the service environment to its initial state.

```swift
// Reset everything
await ServiceEnv.current.resetAll()

// Services must be re-registered before they can be resolved
ServiceEnv.current.register(DatabaseProtocol.self) {
    DatabaseService(connectionString: "sqlite://app.db")
}
```

**When to use:**
- Completely reset the service environment
- Start fresh in tests with a clean slate
- Remove all service registrations and instances

> Important: After calling `resetAll()`, all services must be re-registered before they can be resolved. Attempting to resolve a service that hasn't been re-registered will throw an error.

### Comparison

| Feature | `resetCaches()` | `resetAll()` |
|---------|----------------|--------------|
| Clears cached instances | ✅ | ✅ |
| Removes registered providers | ❌ | ✅ |
| Services need re-registration | ❌ | ✅ |
| Typical scenario | Testing with same setup | Clean test environment |

### Testing Best Practices

```swift
@Test func testServiceRecreation() async throws {
    let testEnv = ServiceEnv(name: "reset-test")
    try await ServiceEnv.$current.withValue(testEnv) {
        var creationCount = 0
        ServiceEnv.current.register(Int.self) {
            creationCount += 1
            return creationCount
        }

        let service1 = try ServiceEnv.current.resolve(Int.self)
        #expect(service1 == 1)

        // Clear cache for fresh instance
        await ServiceEnv.current.resetCaches()

        let service2 = try ServiceEnv.current.resolve(Int.self)
        #expect(service2 == 2) // New instance
    }
}
```

## Configuring Resolution Depth

Service provides a `maxResolutionDepth` setting to prevent stack overflow from excessively deep dependency graphs. The default value is 100, which should be sufficient for most applications.

### Customizing the Depth Limit

Use `withValue` to temporarily change the maximum resolution depth for specific contexts:

```swift
// Use a smaller depth for testing to catch issues early
ServiceEnv.$maxResolutionDepth.withValue(10) {
    let service = try ServiceEnv.current.resolve(MyService.self)
}

// Use a larger depth for complex dependency graphs
await ServiceEnv.$maxResolutionDepth.withValue(200) {
    let service = try ServiceEnv.current.resolve(ComplexService.self)
}
```

### When Depth is Exceeded

When the resolution depth exceeds the configured limit, a ``ServiceError/maxDepthExceeded(depth:chain:)`` error is thrown. This typically indicates:

- An unintentional circular dependency that wasn't detected
- An excessively deep dependency graph that might need refactoring
- A misconfigured depth limit for your use case

```swift
do {
    let service = try ServiceEnv.current.resolve(DeepService.self)
} catch ServiceError.maxDepthExceeded(let depth, let chain) {
    print("Resolution exceeded depth \(depth)")
    print("Chain: \(chain.joined(separator: " -> "))")
}
```

> Tip: In tests, consider using a smaller `maxResolutionDepth` value to catch potential issues early. A depth of 10-20 is often sufficient for well-designed dependency graphs.

## Thread Safety

Environments use `TaskLocal` storage, ensuring thread-safe access across async contexts. Each task maintains its own environment context, making it safe to use in concurrent code.

Both `resetCaches()` and `resetAll()` are thread-safe and properly handle concurrent access:
- Sendable services are cleared using thread-safe operations
- MainActor services are cleared on the main thread
- The async nature ensures all cleanup completes before the method returns

## See Also

- <doc:BasicUsage>
- <doc:ServiceAssembly>
- <doc:ErrorHandling>
