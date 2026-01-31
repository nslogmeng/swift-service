# Error Handling

Learn how to handle errors when resolving services.

> Localization: **English**  |  **[简体中文](https://nslogmeng.github.io/swift-service/zh-Hans/documentation/service/errorhandling)**

## Overview

The Service framework uses Swift's native error handling to provide clear and actionable error messages when service resolution fails. The `resolve()` and `resolveMain()` methods use **typed throws** (`throws(ServiceError)`) to guarantee the error type at compile time, enabling exhaustive error handling with switch statements.

## ServiceError Types

The framework defines four error types:

### notRegistered

Thrown when attempting to resolve a service that has not been registered:

```swift
do {
    let service = try ServiceEnv.current.resolve(MyService.self)
} catch ServiceError.notRegistered(let serviceType) {
    print("Service '\(serviceType)' is not registered")
}
```

### circularDependency

Thrown when a circular dependency is detected during resolution:

```swift
do {
    let service = try ServiceEnv.current.resolve(ServiceA.self)
} catch ServiceError.circularDependency(let serviceType, let chain) {
    print("Circular dependency detected: \(chain.joined(separator: " -> "))")
}
```

### maxDepthExceeded

Thrown when the resolution depth limit is exceeded (default: 100):

```swift
do {
    let service = try ServiceEnv.current.resolve(DeeplyNestedService.self)
} catch ServiceError.maxDepthExceeded(let depth, let chain) {
    print("Resolution depth \(depth) exceeded")
}
```

### factoryFailed

Thrown when the factory function throws an error during service creation:

```swift
do {
    let service = try ServiceEnv.current.resolve(MyService.self)
} catch ServiceError.factoryFailed(let serviceType, let underlyingError) {
    print("Failed to create '\(serviceType)': \(underlyingError)")
}
```

**Note:** If the factory throws a `ServiceError`, it is propagated directly without being wrapped in `factoryFailed`. This allows you to throw specific `ServiceError` cases from factory functions when appropriate.

## Error Handling Patterns

### Direct Resolution with try

For programmatic service resolution, use `try` with error handling. Thanks to typed throws, you can use exhaustive switch statements:

```swift
func configureServices() throws(ServiceError) {
    let database = try ServiceEnv.current.resolve(DatabaseProtocol.self)
    let logger = try ServiceEnv.current.resolve(LoggerProtocol.self)
    // Use services...
}

// Or handle errors explicitly with exhaustive switch
do {
    let database = try ServiceEnv.current.resolve(DatabaseProtocol.self)
} catch {
    switch error {  // error is ServiceError, not any Error
    case .notRegistered(let type):
        print("Not registered: \(type)")
    case .circularDependency(_, let chain):
        print("Circular: \(chain)")
    case .maxDepthExceeded(let depth, _):
        print("Depth exceeded: \(depth)")
    case .factoryFailed(let type, let underlying):
        print("Factory failed for \(type): \(underlying)")
    }
}
```

### Property Wrapper Behavior

The `@Service` and `@MainService` property wrappers use lazy resolution and `fatalError` for non-optional types:

```swift
struct MyController {
    @Service var database: DatabaseProtocol  // fatalError if not registered on first access
}
```

**Why fatalError?** A missing required service indicates a configuration error that should be caught during development, not handled at runtime. Services are resolved lazily on first access, not at initialization time.

**For optional dependencies**, use the optional type syntax to avoid fatalError:

```swift
struct MyController {
    @Service var analytics: AnalyticsService?  // Returns nil if not registered
}
```

### Factory Functions

Factory functions support `throws`, allowing errors to propagate naturally to the caller:

```swift
ServiceEnv.current.register(UserRepository.self) {
    let database = try ServiceEnv.current.resolve(DatabaseProtocol.self)
    let logger = try ServiceEnv.current.resolve(LoggerProtocol.self)
    return UserRepository(database: database, logger: logger)
}
```

You can also throw custom errors or `ServiceError` from factory functions:

```swift
ServiceEnv.current.register(DatabaseService.self) {
    guard let connectionString = ProcessInfo.processInfo.environment["DB_URL"] else {
        throw ServiceError.notRegistered(serviceType: "DB_URL environment variable")
    }
    return DatabaseService(connectionString: connectionString)
}
```

When a factory throws:
- `ServiceError` is propagated directly to the caller
- Other errors are wrapped in `ServiceError.factoryFailed`

## Best Practices

### Register All Services Early

Register all services during app initialization to catch configuration errors early:

```swift
@main
struct MyApp: App {
    init() {
        ServiceEnv.current.assemble(
            DatabaseAssembly(),
            LoggerAssembly(),
            RepositoryAssembly()
        )
    }
}
```

For organizing registrations, see <doc:ServiceAssembly>.

### Use Property Wrappers for Required Dependencies

For services that must exist, use property wrappers:

```swift
struct UserController {
    @Service var userRepository: UserRepositoryProtocol
}
```

### Use Optional Types for Optional Dependencies

For services that may not be registered, use optional types in property wrappers:

```swift
struct MyController {
    @Service var analytics: AnalyticsProtocol?  // Returns nil if not registered

    func loadAnalytics() {
        analytics?.track("app_launched")  // Safe optional access
    }
}
```

Alternatively, use direct resolution with error handling:

```swift
func loadAnalytics() {
    do {
        let analytics = try ServiceEnv.current.resolve(AnalyticsProtocol.self)
        analytics.track("app_launched")
    } catch {
        // Analytics not configured, skip tracking
    }
}
```

### Validate Configuration in Tests

In tests, validate that all required services are registered:

```swift
@Test func testServiceConfiguration() throws {
    // Should not throw for properly configured services
    _ = try ServiceEnv.current.resolve(DatabaseProtocol.self)
    _ = try ServiceEnv.current.resolve(LoggerProtocol.self)
}
```

For testing strategies, see <doc:ServiceEnvironments>.

## Error Messages

ServiceError provides clear, descriptive error messages:

```
Service 'DatabaseProtocol' is not registered in ServiceEnv

Circular dependency detected for service 'ServiceA'.
Dependency chain: ServiceA -> ServiceB -> ServiceC -> ServiceA
Check your service registration to break the cycle.

Maximum resolution depth (100) exceeded.
Current chain: A -> B -> C -> ...
This may indicate a circular dependency or overly deep dependency graph.

Factory failed to create service 'MyService': Connection refused
```

## See Also

- ``ServiceError``
- <doc:CircularDependencies>
- <doc:BasicUsage>
