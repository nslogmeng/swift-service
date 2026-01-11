# Understanding Service

A deep dive into Service's architecture, design decisions, and how it works under the hood.

> Localization: **English**  |  **[简体中文](<doc:UnderstandingService.zh-Hans>)**

## Core Concepts

### Service Environment

Service uses the concept of a "service environment" to manage service registrations and resolutions. Each environment maintains its own isolated registry, allowing you to have different service configurations for different contexts (production, development, testing).

```swift
public struct ServiceEnv: Sendable {
    @TaskLocal
    public static var current: ServiceEnv = .online
    
    public let name: String
    let storage = ServiceStorage()
}
```

### TaskLocal Storage

Service uses Swift's `TaskLocal` property wrapper to maintain environment context across async boundaries. This ensures that:

1. Each async task maintains its own environment context
2. Environment switches are scoped to the current task
3. Thread-safe access across concurrent contexts

```swift
// Switch environment for this task
await ServiceEnv.$current.withValue(.dev) {
    // All service resolutions in this block use .dev environment
    let service = ServiceEnv.current.resolve(MyService.self)
}
```

### Service Storage

Each environment has its own `ServiceStorage` instance that manages:

- **Service providers**: Factory functions that create service instances
- **Service cache**: Cached instances for singleton behavior
- **Resolution tracking**: Tracks the current resolution chain for cycle detection

## Service Resolution Flow

When you resolve a service, here's what happens:

1. **Check cache**: If the service has been resolved before and cached, return the cached instance
2. **Get provider**: Look up the factory function for this service type
3. **Track resolution**: Add this service to the resolution chain (for cycle detection)
4. **Create instance**: Call the factory function to create the service
5. **Cache instance**: Store the instance in the cache for future resolutions
6. **Return instance**: Return the newly created (or cached) instance

### Resolution Tracking

Service tracks the resolution chain to detect circular dependencies:

```swift
// When resolving AService:
// 1. Add AService to chain: [AService]
// 2. Factory function resolves BService
// 3. Add BService to chain: [AService, BService]
// 4. Factory function resolves CService
// 5. Add CService to chain: [AService, BService, CService]
// 6. Factory function tries to resolve AService
// 7. AService is already in chain - CYCLE DETECTED!
```

## Concurrency Model

Service is designed to be thread-safe and work seamlessly with Swift's concurrency model.

### Sendable Services

Regular services must conform to `Sendable`, ensuring they can be safely shared across concurrent contexts:

```swift
extension ServiceEnv {
    public func register<Service: Sendable>(
        _ type: Service.Type,
        factory: @escaping @Sendable () -> Service
    ) {
        storage.register(type, factory: factory)
    }
}
```

### MainActor Services

For `@MainActor`-isolated services (like view models), Service provides separate APIs that don't require `Sendable`:

```swift
@MainActor
extension ServiceEnv {
    public func registerMain<Service>(
        _ type: Service.Type,
        factory: @escaping @MainActor () -> Service
    ) {
        storage.registerMain(type, factory: factory)
    }
}
```

### Thread Safety

- **Service registration**: Thread-safe through internal locking
- **Service resolution**: Thread-safe through internal locking
- **Environment switching**: Thread-safe through `TaskLocal` storage
- **Cache management**: Thread-safe through internal locking

## Service Lifecycle

### Singleton Behavior

By default, services are cached as singletons:

```swift
// First resolution creates and caches the instance
let service1 = ServiceEnv.current.resolve(MyService.self)

// Subsequent resolutions return the cached instance
let service2 = ServiceEnv.current.resolve(MyService.self)
// service1 === service2 (same instance)
```

### Cache Management

You can clear the cache to force services to be recreated:

```swift
// Clear cache - services will be recreated on next resolution
await ServiceEnv.current.resetCaches()

// Now this creates a new instance
let service3 = ServiceEnv.current.resolve(MyService.self)
// service1 !== service3 (different instance)
```

### Complete Reset

You can also reset everything, including registrations:

```swift
// Reset everything - cache and registrations
await ServiceEnv.current.resetAll()

// Services must be re-registered before they can be resolved
ServiceEnv.current.register(MyService.self) {
    MyService()
}
```

## Property Wrappers

Service provides property wrappers for convenient dependency injection:

### @Service

The `@Service` property wrapper resolves services eagerly when the property is initialized:

```swift
@propertyWrapper
public struct Service<S: Sendable>: Sendable {
    public let wrappedValue: S
    
    public init() {
        self.wrappedValue = ServiceEnv.current.resolve(S.self)
    }
}
```

### @MainService

The `@MainService` property wrapper works similarly but for `@MainActor` services:

```swift
@MainActor
@propertyWrapper
public struct MainService<S> {
    public let wrappedValue: S
    
    public init() {
        self.wrappedValue = ServiceEnv.current.resolveMain(S.self)
    }
}
```

## Design Decisions

### Why TaskLocal?

`TaskLocal` provides the perfect mechanism for environment scoping:

- **Async-safe**: Works seamlessly across async boundaries
- **Task-scoped**: Environment switches are automatically scoped to the current task
- **Thread-safe**: No additional synchronization needed

### Why Separate MainActor APIs?

Swift 6's strict concurrency model requires `Sendable` for cross-actor communication. However, `@MainActor` classes are thread-safe but not automatically `Sendable`. Separate APIs allow Service to work with both:

- **Sendable services**: Use standard `register`/`resolve` APIs
- **MainActor services**: Use `registerMain`/`resolveMain` APIs

### Why @MainActor for Assembly?

Service Assembly is marked with `@MainActor` because:

1. Assembly typically happens during app initialization (already on main actor)
2. Ensures thread-safe, sequential execution of registrations
3. Provides predictable execution context

### Why Fatal Errors?

Service uses `fatalError` when services are not registered because:

1. **Fail-fast**: Catch configuration errors early
2. **Type safety**: Compile-time checking isn't always possible
3. **Clear errors**: Provides descriptive error messages

## Performance Considerations

### Caching

Service caches resolved instances to avoid repeated creation:

- **Memory**: Cached instances consume memory
- **Performance**: Subsequent resolutions are O(1) lookups
- **Trade-off**: Balance between memory and performance

### Resolution Tracking

Cycle detection adds overhead to resolution:

- **Memory**: Resolution chain tracking
- **Performance**: Minimal overhead for cycle detection
- **Benefit**: Prevents infinite loops and stack overflow

### Locking

Service uses internal locks for thread safety:

- **Coarse-grained**: Simple locking strategy
- **Performance**: Minimal contention in typical use cases
- **Trade-off**: Simplicity over fine-grained locking

## Extension Points

Service is designed to be extensible:

### Custom Environments

Create custom environments for specific use cases:

```swift
let stagingEnv = ServiceEnv(name: "staging")
```

### ServiceKey Protocol

Provide default implementations through `ServiceKey`:

```swift
struct MyService: ServiceKey {
    static var `default`: MyService {
        MyService()
    }
}
```

### ServiceAssembly Protocol

Organize registrations through assemblies:

```swift
struct MyAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        // Register services...
    }
}
```

## Best Practices

1. **Use protocols**: Define service protocols for flexibility and testability
2. **Register in order**: Register dependencies before dependents
3. **Use assemblies**: Organize registrations for maintainability
4. **Leverage environments**: Use different environments for different contexts
5. **Clear caches in tests**: Use `resetCaches()` to ensure fresh instances in tests

## Next Steps

- Read <doc:ConcurrencyModel> for more details on Service's concurrency design
- Explore <doc:RealWorldExamples> for practical usage patterns
- Check out the API documentation for detailed method descriptions
