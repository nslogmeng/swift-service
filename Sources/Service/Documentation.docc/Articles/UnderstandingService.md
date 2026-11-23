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
│              │  registry (locked):   │              │
│              │    type → entry       │              │
│              │    entry: scope,      │              │
│              │    factory, slot      │              │
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
│     (scope, factory,    │
│     cache slot)         │
└─────────────────────────┘
         │ Found
         ▼
┌─────────────────────────┐
│  2. Read the cache slot │──── Holds an instance? ──▶ Return it
│     (singleton, custom) │
└─────────────────────────┘
         │ Empty, or no slot
         ▼
┌─────────────────────────┐
│  3. Check for cycle     │──── In chain? ──▶ Throw circularDependency
└─────────────────────────┘
         │ OK
         ▼
┌─────────────────────────┐
│  4. Track in chain +    │
│     create graph cache  │──── (if top-level resolve)
│     if needed           │
└─────────────────────────┘
         │
         ▼
┌─────────────────────────┐
│  5. Dispatch by scope   │
└────────┬────────────────┘
         │
         ├── singleton → check cache → hit: return │ miss: factory + cache
         ├── transient → call factory → return new instance
         ├── graph     → check graph cache → hit: return │ miss: factory + cache
         └── custom    → check named cache → hit: return │ miss: factory + cache
```

### Scope-Specific Behavior

| Scope | Caching | Stored In | Reset |
|-------|---------|-----------|-------|
| `.singleton` | Global cache, one instance per type | Cache slot of the registration | `resetCaches()` or `resetScope(.singleton)` |
| `.transient` | No caching, new instance every time | N/A | N/A |
| `.graph` | Shared within one resolve chain | Graph cache of the resolution chain, by environment and type | Automatic (released when top-level resolve completes) |
| `.custom("name")` | Named cache, independent of other scopes | Cache slot of the registration | `resetScope(.custom("name"))` |

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

`register` stores a factory that can run on any thread and an instance that is shared across isolation domains. The factory must be a nonisolated `@Sendable` closure, and the service type must be `Sendable`. Services that live on the main actor often cannot meet these requirements:
- Their initializers are main-actor-isolated, so a nonisolated factory cannot call them
- The protocols they are registered under are often not `Sendable`, for example a `@MainActor` protocol
- A `@MainActor` class that inherits from a non-`Sendable` base class is not `Sendable`

Apart from that last case, a `@MainActor` class is implicitly `Sendable`. Its initializer and members are what stay on the main actor.

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
public struct Service<S: Sendable>: Sendable {
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

All shared state is in values of type `Locked`, a value behind a lock. The lock is `OSAllocatedUnfairLock` on Apple platforms and `Synchronization.Mutex` on Linux and Android. Wasm runs on one thread and has no lock.

```swift
private let registry = Locked<[ObjectIdentifier: Entry]>()
```

A value in a `Locked` changes only inside `withLock`, so reading, changing, and writing back are one critical section.

The registry holds one entry for each registered service type, keyed by the identifier of the static type. An entry holds the scope and the factory of the registration. The factory is either a Sendable factory or a MainActor factory, so a type has one registration of one category. For singleton and custom scopes, an entry also holds a cache slot of type `Locked<AnyCacheBox?>`.

### Once-per-Key Creation

The cache slot of a singleton or custom-scoped registration has its own lock. A resolution takes these steps:

1. Take the registry lock, copy the entry, and release the registry lock.
2. Take the slot lock and read the slot. If the slot holds an instance, return it.
3. Otherwise, start resolution tracking and take the slot lock again. If the slot holds an instance now, return it. If not, run the factory and store the result in the slot.

Step 2 runs no factory. It skips cycle detection and does not count toward `maxResolutionDepth`. If the current thread is already resolving the same registration, it holds the slot lock. The resolution then skips step 2, and step 3 reports the cycle.

The slot lock is held while the factory runs. As a result, the factory runs at most once per cached instance, and concurrent first resolvers of the same service wait for it. The registry lock is never held while a factory runs, so a slow factory blocks only the resolvers of its own service.

Reset methods give the affected entries new, empty slots and do not take slot locks. A resolution that already holds an old slot finishes with that slot. Later resolutions use the new slot.

The storage releases an old slot, and the instance cached in it, after it has released the registry lock. The `deinit` of a service can therefore use its environment.

Registering a type again replaces its entry. If the scope and the category are the same, the new entry keeps the slot, so an instance that is already cached stays until a reset. Otherwise, the new entry starts with an empty slot.

For the guarantees and limitations that follow from this design, see <doc:ConcurrencyModel>.

### Resolution Chain

A resolution chain is one top-level `resolve` call and the resolutions that its factories start. Resolution is synchronous, so a chain runs on one thread from its first step to its last. `ServiceContext` binds the chain to that thread. A chain holds:

- **Steps**: the registrations that are being resolved. A step is identified by its environment and its service type.
- **Graph cache**: the graph-scoped instances of the chain.

A resolution that returns a cached instance is not a step of the chain. A resolution that has to run a factory takes these steps:

1. Throw `ServiceError.circularDependency` if the chain already contains the registration, or if the thread already holds the lock of its cache slot.
2. Throw `ServiceError.maxDepthExceeded` if the chain has reached `ServiceEnv.maxResolutionDepth`.
3. Add the registration to the chain, run the factory, and remove the registration again.

The chain ends when its first step returns. Its graph-scoped instances are released then.

The chain belongs to the thread, not to the task:

- A task that a factory starts is not part of the chain. It can resolve the service whose factory started it, and its resolutions are chains of their own.
- A resolution that another task runs on the thread of a running factory starts a chain of its own, with its own steps and its own graph cache. A nested run loop inside a factory does that. The first chain is interrupted until the second one ends. If the task resolves a singleton or custom-scoped service that an interrupted chain is creating, the resolution throws `circularDependency`: the thread already holds the lock of that cache slot, and the resolution cannot wait for a factory that runs below it on the same thread.
- A factory in one environment can resolve the same type from another environment. The two are different registrations.

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
| First resolution (singleton/custom) | O(1) + factory | Plus cycle detection; the factory runs under the registration's slot lock |
| Cached resolution (singleton/custom) | O(1) | One registry lookup by type, then slot read (two uncontended locks); no resolution tracking |
| Transient resolution | O(1) + factory | No caching overhead |
| Graph resolution | O(1) + factory | Lookup in the graph cache of the resolution chain |
| Environment switch | O(1) | TaskLocal binding |
| Reset all caches | O(n) | Gives every cached registration a new slot |
| Reset specific scope | O(n) | Filters by scope |

### Memory Considerations

- Each registered service stores one factory closure and, for singleton and custom scopes, one cache slot
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
