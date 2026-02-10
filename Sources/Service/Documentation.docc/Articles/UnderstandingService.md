# Understanding Service

A deep dive into Service's architecture, design decisions, and how it works under the hood.

> Localization: **English**  |  **[简体中文](https://nslogmeng.github.io/swift-service/zh-Hans/documentation/service/understandingservice)**

## Architecture Overview

Service is built around five core concepts:

1. **ServiceEnv**: The service environment that manages registrations and resolutions
2. **ServiceStorage**: The storage layer for providers and cached instances
3. **ServiceScope**: Lifecycle management for service instances (singleton, transient, graph, custom)
4. **ServiceContext**: Resolution tracking for circular dependency detection and graph-scoped caching
5. **Property Wrappers**: Convenient syntax for dependency injection (`@Service`, `@MainService`, `@Provider`, `@MainProvider`)

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
│              │  • mainProviders      │              │
│              │  • caches (locked)    │              │
│              │    key: Type + Scope  │              │
│              └───────────────────────┘              │
└─────────────────────────────────────────────────────┘
```

### Property Wrapper Matrix

Service provides four property wrappers in a 2x2 matrix:

|  | **Sendable** | **MainActor** |
|---|---|---|
| **Lazy + cached** | `@Service` | `@MainService` |
| **Scope-driven** | `@Provider` | `@MainProvider` |

- **`@Service` / `@MainService`**: Resolves lazily on first access and caches the result internally. Subsequent accesses always return the same instance, regardless of the registered scope.
- **`@Provider` / `@MainProvider`**: Resolves on every access. Caching behavior is entirely determined by the service's registered scope (e.g., transient scope produces a new instance each time).

All four support optional types — returns `nil` instead of crashing when the service is not registered:

```swift
@Service var analytics: AnalyticsService?    // Lazy, cached, nil-safe
@Provider var handler: RequestHandler?       // Scope-driven, nil-safe
```

## Service Resolution Flow

When you call `resolve()`, the behavior depends on the service's registered scope:

```
resolve(MyService.self)
         │
         ▼
┌─────────────────────────┐
│  1. Get provider entry  │──── Not found? ──▶ Throw notRegistered
│     (includes scope)    │
└─────────────────────────┘
         │ Found
         ▼
┌─────────────────────────┐
│  2. Check for cycle     │──── In chain? ──▶ Throw circularDependency
└─────────────────────────┘
         │ OK
         ▼
┌─────────────────────────┐
│  3. Track in chain +    │
│     create graph cache  │──── (if top-level resolve)
│     if needed           │
└─────────────────────────┘
         │
         ▼
┌─────────────────────────┐
│  4. Dispatch by scope   │
└─────────────────────────┘
    │         │        │         │
    ▼         ▼        ▼         ▼
singleton  transient  graph    custom
    │         │        │         │
    ▼         ▼        ▼         ▼
 Check     Call     Check      Check
 cache     factory  graph      named
    │         │     cache      cache
    │         │        │         │
    ▼         ▼        ▼         ▼
  Found?   Return   Found?    Found?
  Yes→ret  new inst Yes→ret   Yes→ret
  No→call           No→call   No→call
  factory           factory   factory
  + cache           + cache   + cache
```

### Scope-Specific Behavior

| Scope | Caching | Cache Key | Reset |
|-------|---------|-----------|-------|
| `.singleton` | Global cache, one instance per type | Type + `.singleton` | `resetCaches()` or `resetScope(.singleton)` |
| `.transient` | No caching, new instance every time | N/A | N/A |
| `.graph` | Shared within one resolve chain | Type + `.graph` (in `GraphCacheBox`) | Automatic (released when top-level resolve completes) |
| `.custom("name")` | Named cache, independent of other scopes | Type + `.custom("name")` | `resetScope(.custom("name"))` |

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

When no scope is specified, services default to `.singleton`:

```swift
env.register(DatabaseService.self) { DatabaseService() }
// Equivalent to:
env.register(DatabaseService.self, scope: .singleton) { DatabaseService() }

let service1 = try ServiceEnv.current.resolve(DatabaseService.self)
let service2 = try ServiceEnv.current.resolve(DatabaseService.self)
// service1 === service2 (same instance)
```

**Benefits:**
- Predictable behavior (same instance everywhere)
- Memory efficient (single instance per service)
- Matches common DI patterns
- Backward compatible with prior versions

**When you need other lifecycles**, use explicit scopes:

```swift
// New instance every time
env.register(RequestHandler.self, scope: .transient) { RequestHandler() }

// Shared within one resolve chain, fresh across chains
env.register(UnitOfWork.self, scope: .graph) { UnitOfWork() }

// Named scope with targeted invalidation
env.register(SessionService.self, scope: .custom("user-session")) {
    SessionService()
}
env.resetScope(.custom("user-session"))  // Clear only this scope
```

## Internal Implementation

### Thread Safety

Service uses Swift's `Synchronization.Mutex` for thread-safe access:

```swift
@Locked private var caches: [CacheKey: CacheBox]
@Locked private var providers: [CacheKey: ProviderEntry]
@Locked private var mainProviders: [CacheKey: MainProviderEntry]
```

The `@Locked` property wrapper ensures atomic read/write operations. The `CacheKey` is a composite of the service type (`ObjectIdentifier`) and its scope, ensuring that services registered under different scopes have isolated caches.

### Circular Dependency Detection and Graph Caching

`ServiceContext` tracks the resolution chain and manages graph-scoped caching using `TaskLocal`:

```swift
enum ServiceContext {
    @TaskLocal static var resolutionStack: [String] = []
    @TaskLocal static var graphCacheBox: GraphCacheBox?
}
```

When resolving a service:
1. Check if the service type is already in the stack (circular dependency detection)
2. If yes, throw `ServiceError.circularDependency`
3. If no, add to stack and proceed
4. If this is a top-level resolve, create a new `GraphCacheBox` for graph-scoped services
5. Nested resolves within the same chain share the same `GraphCacheBox`

This approach is:
- **Task-scoped**: Each async task has its own resolution stack
- **Automatic cleanup**: Stack and graph cache are restored after resolution completes
- **Zero overhead**: No tracking when not resolving
- **Graph-aware**: Services with `.graph` scope share instances within the same resolution chain

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
| First resolution (singleton/custom) | O(1) + factory | Plus cycle detection, double-check caching |
| Cached resolution (singleton/custom) | O(1) | Dictionary lookup by composite key |
| Transient resolution | O(1) + factory | No caching overhead |
| Graph resolution | O(1) + factory | Lookup in task-local graph cache |
| Environment switch | O(1) | TaskLocal binding |
| Reset all caches | O(n) | Clears all cached instances |
| Reset specific scope | O(n) | Filters by scope |

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
