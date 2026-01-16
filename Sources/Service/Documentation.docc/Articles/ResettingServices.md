# Resetting Services

Service provides two methods to reset service state: `resetCaches()` and `resetAll()`. These methods are essential for testing scenarios and when you need to clear service instances or completely reset the service environment.

> Localization: **English**  |  **[简体中文](https://nslogmeng.github.io/swift-service/zh-Hans/documentation/service/resettingservices)**

## Overview

Both `resetCaches()` and `resetAll()` are async methods that ensure proper cleanup of both Sendable and MainActor services. The key difference is:

- **`resetCaches()`**: Clears cached service instances but keeps registered providers
- **`resetAll()`**: Clears both cached instances and registered providers

## resetCaches()

The `resetCaches()` method clears all cached service instances (both Sendable and MainActor services) while preserving registered service providers. This means services will be recreated on the next resolution using their registered factory functions.

### When to Use

Use `resetCaches()` when you want to:
- Force services to be recreated without re-registering them
- Get fresh instances in testing scenarios
- Clear cached state while maintaining service registration

### Example

```swift
// Register a service
ServiceEnv.current.register(String.self) {
    UUID().uuidString
}

// Resolve and cache the service
let service1 = ServiceEnv.current.resolve(String.self)
print(service1) // e.g., "550e8400-e29b-41d4-a716-446655440000"

// Clear cache - next resolution will create a new instance
await ServiceEnv.current.resetCaches()
let service2 = ServiceEnv.current.resolve(String.self)
print(service2) // Different UUID: "6ba7b810-9dad-11d1-80b4-00c04fd430c8"

// service1 != service2 (new instance created)
```

### Testing Example

```swift
func testServiceRecreation() async {
    // Register a service that tracks creation count
    var creationCount = 0
    ServiceEnv.current.register(CounterService.self) {
        creationCount += 1
        return CounterService(id: creationCount)
    }
    
    // First resolution creates and caches the service
    let service1 = ServiceEnv.current.resolve(CounterService.self)
    XCTAssertEqual(service1.id, 1)
    
    // Second resolution returns cached instance
    let service2 = ServiceEnv.current.resolve(CounterService.self)
    XCTAssertEqual(service2.id, 1) // Same instance
    
    // Clear cache
    await ServiceEnv.current.resetCaches()
    
    // Third resolution creates a new instance
    let service3 = ServiceEnv.current.resolve(CounterService.self)
    XCTAssertEqual(service3.id, 2) // New instance
}
```

## resetAll()

The `resetAll()` method clears all cached service instances and removes all registered service providers (both Sendable and MainActor services). This completely resets the service environment to its initial state.

### When to Use

Use `resetAll()` when you want to:
- Completely reset the service environment
- Start fresh in tests with a clean slate
- Remove all service registrations and instances

### Important Note

After calling `resetAll()`, all services must be re-registered before they can be resolved. Attempting to resolve a service that hasn't been re-registered will cause a fatal error.

### Example

```swift
// Register services
ServiceEnv.current.register(DatabaseProtocol.self) {
    DatabaseService(connectionString: "sqlite://app.db")
}

ServiceEnv.current.register(APIClientProtocol.self) {
    APIClient(baseURL: "https://api.example.com")
}

// Use services
let db = ServiceEnv.current.resolve(DatabaseProtocol.self)
let api = ServiceEnv.current.resolve(APIClientProtocol.self)

// Reset everything
await ServiceEnv.current.resetAll()

// Services must be re-registered
ServiceEnv.current.register(DatabaseProtocol.self) {
    DatabaseService(connectionString: "sqlite://app.db")
}

// Now services can be resolved again
let newDb = ServiceEnv.current.resolve(DatabaseProtocol.self)
```

### Testing Example

```swift
func testCleanEnvironment() async {
    // Register services in first test
    ServiceEnv.current.register(MockDatabase.self) {
        MockDatabase()
    }
    
    let db1 = ServiceEnv.current.resolve(MockDatabase.self)
    XCTAssertNotNil(db1)
    
    // Completely reset for next test
    await ServiceEnv.current.resetAll()
    
    // Previous registration is gone
    // Need to re-register for this test
    ServiceEnv.current.register(MockDatabase.self) {
        MockDatabase()
    }
    
    let db2 = ServiceEnv.current.resolve(MockDatabase.self)
    XCTAssertNotNil(db2)
    // db2 is a completely new instance
}
```

## Comparison

| Feature | `resetCaches()` | `resetAll()` |
|---------|----------------|--------------|
| Clears cached instances | ✅ | ✅ |
| Removes registered providers | ❌ | ✅ |
| Services need re-registration | ❌ | ✅ |
| Use case | Get fresh instances | Complete reset |
| Typical scenario | Testing with same setup | Clean test environment |

## MainActor Services

Both methods properly handle MainActor services:

```swift
@MainActor
func testMainActorServiceReset() async {
    // Register MainActor service
    ServiceEnv.current.registerMain(ViewModelService.self) {
        ViewModelService()
    }
    
    let viewModel1 = ServiceEnv.current.resolveMain(ViewModelService.self)
    
    // Clear cache - works for MainActor services too
    await ServiceEnv.current.resetCaches()
    
    let viewModel2 = ServiceEnv.current.resolveMain(ViewModelService.self)
    // viewModel2 is a new instance
}
```

## Best Practices

1. **Use `resetCaches()` in tests** when you want fresh instances but keep the same service setup
2. **Use `resetAll()` in tests** when you need a completely clean environment between test cases
3. **Always await** these methods since they're async
4. **Re-register services** after `resetAll()` before resolving them
5. **Use in `setUp()` or `tearDown()`** methods in test classes to ensure clean state

## Thread Safety

Both methods are thread-safe and properly handle concurrent access:
- Sendable services are cleared using thread-safe operations
- MainActor services are cleared on the main thread
- The async nature ensures all cleanup completes before the method returns
