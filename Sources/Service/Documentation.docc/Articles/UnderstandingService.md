# Understanding Service

A deep dive into Service's architecture, design decisions, and how it works under the hood.

> Localization: **English**  |  **[简体中文](https://nslogmeng.github.io/swift-service/zh-Hans/documentation/service/understandingservice)**

## Architecture Overview

Service is built around three core concepts:

1. **ServiceEnv**: The service environment that manages registrations and resolutions
2. **ServiceStorage**: The storage layer for providers and cached instances
3. **Property Wrappers**: Convenient syntax for dependency injection

```
┌─────────────────────────────────────────────────────┐
│                    ServiceEnv                        │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │
│  │   .online   │  │    .dev     │  │    .test    │  │
│  │  (default)  │  │             │  │             │  │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  │
│         │                │                │         │
│         └────────────────┼────────────────┘         │
│                          │                          │
│              ┌───────────▼───────────┐              │
│              │    ServiceStorage     │              │
│              │  • providers (locked) │              │
│              │  • cache (locked)     │              │
│              │  • mainProviders      │              │
│              │  • mainCache          │              │
│              └───────────────────────┘              │
└─────────────────────────────────────────────────────┘
```

## Service Resolution Flow

When you call `resolve()`, this is what happens:

```
resolve(MyService.self)
         │
         ▼
┌─────────────────────┐
│  1. Check cache     │──── Found? ──▶ Return cached instance
└─────────────────────┘
         │ Not found
         ▼
┌─────────────────────┐
│  2. Get provider    │──── Not found? ──▶ Throw notRegistered
└─────────────────────┘
         │ Found
         ▼
┌─────────────────────┐
│  3. Check for cycle │──── In chain? ──▶ Throw circularDependency
└─────────────────────┘
         │ OK
         ▼
┌─────────────────────┐
│  4. Track in chain  │
└─────────────────────┘
         │
         ▼
┌─────────────────────┐
│  5. Call factory    │──── Throws? ──▶ Propagate error
└─────────────────────┘
         │ Success
         ▼
┌─────────────────────┐
│  6. Cache instance  │
└─────────────────────┘
         │
         ▼
    Return instance
```

## Design Decisions

### Why TaskLocal for Environment Context?

Service uses `@TaskLocal` to store the current environment:

```swift
public struct ServiceEnv: Sendable {
    @TaskLocal
    public static var current: ServiceEnv = .online
}
```

**Benefits:**
- **Async-safe**: Automatically maintained across `await` boundaries
- **Task-scoped**: Environment switches are isolated to the current task and its children
- **Thread-safe**: No additional synchronization needed
- **Inheritance**: Child tasks automatically inherit the parent's environment

**Trade-offs:**
- Cannot change environment from within a synchronous context without `withValue`
- Each task switch creates a small overhead

### Why Separate MainActor APIs?

Swift 6 requires `Sendable` for values crossing actor boundaries. However, `@MainActor` classes:
- Have mutable state (not automatically `Sendable`)
- Are thread-safe through actor isolation
- Cannot be safely passed to other actors

Service solves this with separate APIs:

| API | Use Case | Thread Safety |
|-----|----------|---------------|
| `register`/`resolve` | Sendable services | Mutex-based locking |
| `registerMain`/`resolveMain` | MainActor services | Actor isolation |

### Why @MainActor for ServiceAssembly?

```swift
@MainActor
public protocol ServiceAssembly {
    func assemble(env: ServiceEnv)
}
```

**Reasons:**
1. Assembly typically runs during app initialization (already on main actor)
2. Ensures sequential, predictable registration order
3. Simplifies mental model for developers
4. Allows registering both Sendable and MainActor services in one place

### Why fatalError in Property Wrappers?

Property wrappers use `fatalError` for missing non-optional services:

```swift
@propertyWrapper
public struct Service<S: Sendable>: @unchecked Sendable {
    private let storage: Locked<S?>
    private let env: ServiceEnv

    public var wrappedValue: S {
        // Lazy resolution on first access
        // Uses fatalError if service not registered
    }
}
```

**Rationale:**
- Missing services indicate **configuration errors**, not runtime conditions
- Fail-fast behavior catches issues during development
- Clear error messages help diagnose the problem

**For optional dependencies**, use the optional type syntax:

```swift
struct MyController {
    @Service var analytics: AnalyticsService?  // Returns nil if not registered
}
```

This provides graceful handling without fatalError.

### Why Singleton by Default?

Services are cached as singletons:

```swift
let service1 = try ServiceEnv.current.resolve(MyService.self)
let service2 = try ServiceEnv.current.resolve(MyService.self)
// service1 === service2 (same instance)
```

**Benefits:**
- Predictable behavior (same instance everywhere)
- Memory efficient (single instance per service)
- Matches common DI patterns

**When you need fresh instances:**
- Call `resetCaches()` to clear the cache
- Create a new `ServiceEnv` for isolated scope

## Internal Implementation

### Thread Safety

Service uses Swift's `Synchronization.Mutex` for thread-safe access:

```swift
@Locked private var providers: [String: Any] = [:]
@Locked private var cache: [String: Any] = [:]
```

The `@Locked` property wrapper ensures atomic read/write operations.

### Circular Dependency Detection

Service tracks the resolution chain using `TaskLocal`:

```swift
@TaskLocal
private static var resolutionChain: [String] = []
```

When resolving a service:
1. Check if the service type is already in the chain
2. If yes, throw `ServiceError.circularDependency`
3. If no, add to chain and proceed

This approach is:
- **Task-scoped**: Each async task has its own chain
- **Automatic cleanup**: Chain is restored after resolution completes
- **Zero overhead**: No tracking when not resolving

### ServiceKey Protocol

`ServiceKey` provides a convenient way to register services with default implementations:

```swift
public protocol ServiceKey {
    static var `default`: Self { get }
}

// Usage
struct MyService: ServiceKey {
    static var `default`: MyService { MyService() }
}

ServiceEnv.current.register(MyService.self)  // Uses default
```

**Design intent:**
- Reduces boilerplate for simple services
- Provides compile-time guarantee of default implementation
- Works with both value types and reference types

## Performance Characteristics

| Operation | Complexity | Notes |
|-----------|------------|-------|
| Registration | O(1) | Dictionary insertion |
| First resolution | O(1) + factory | Plus cycle detection |
| Cached resolution | O(1) | Dictionary lookup |
| Environment switch | O(1) | TaskLocal binding |
| Reset caches | O(n) | Clears all cached instances |

### Memory Considerations

- Each registered service stores one factory closure
- Each resolved service stores one cached instance
- Resolution chain tracking uses stack-allocated array
- Environment switching has minimal memory overhead

## Extension Points

### Custom Environments

```swift
let staging = ServiceEnv(name: "staging")
let featureFlag = ServiceEnv(name: "feature-x")
```

### ServiceAssembly for Modularity

```swift
struct NetworkAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.register(APIClient.self) { APIClient() }
        env.register(ImageLoader.self) { ImageLoader() }
    }
}

ServiceEnv.current.assemble(NetworkAssembly())
```

## See Also

- <doc:ConcurrencyModel>
- <doc:ServiceAssembly>
- <doc:ErrorHandling>
