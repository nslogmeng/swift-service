# Concurrency Model

Learn how to use Service safely in concurrent and async contexts.

> Localization: **English**  |  **[简体中文](https://nslogmeng.github.io/swift-service/zh-Hans/documentation/service/concurrencymodel)**

## Prerequisites

This guide assumes familiarity with:
- Swift's `Sendable` protocol and data race safety
- The `@MainActor` attribute and actor isolation
- Swift's structured concurrency (`async`/`await`, `Task`)

For background on these concepts, see [Swift Concurrency](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/).

## Overview

Service provides two distinct API tracks for dependency injection based on thread-safety requirements, each with two property wrapper styles:

| Service Type | Registration | Resolution | Lazy + Cached | Scope-Driven |
|-------------|--------------|------------|---------------|--------------|
| Sendable | `register()` | `resolve()` | `@Service` | `@Provider` |
| MainActor | `registerMain()` | `resolveMain()` | `@MainService` | `@MainProvider` |

- **`@Service` / `@MainService`**: Resolves once on first access, caches internally. Best for stable dependencies.
- **`@Provider` / `@MainProvider`**: Resolves on every access; caching follows the registered scope. Best for transient or custom-scoped services.

## Sendable Services

Services conforming to `Sendable` can be safely shared across concurrent contexts.

### Registration and Resolution

```swift
// Define a Sendable service
struct DatabaseService: Sendable {
    let connectionString: String
}

// Register
ServiceEnv.current.register(DatabaseService.self) {
    DatabaseService(connectionString: "sqlite://app.db")
}

// Resolve from any context
let database = try ServiceEnv.current.resolve(DatabaseService.self)

// Use in async contexts
Task {
    let db = try ServiceEnv.current.resolve(DatabaseService.self)
    // Use db...
}
```

### Property Wrapper

```swift
struct UserRepository: Sendable {
    @Service var database: DatabaseService
}
```

## MainActor Services

Services that are created and used on the main actor have separate APIs. The factory runs on the main actor, and the service type does not need to conform to `Sendable`.

### Registration and Resolution

```swift
@MainActor
final class ViewModelService {
    var data: String = ""
}

// Must register from @MainActor context
@MainActor
func setupServices() {
    ServiceEnv.current.registerMain(ViewModelService.self) {
        ViewModelService()
    }
}

// Must resolve from @MainActor context
@MainActor
func setupUI() {
    let viewModel = try ServiceEnv.current.resolveMain(ViewModelService.self)
}
```

### Property Wrapper

```swift
@MainActor
class MyViewController {
    @MainService var viewModel: ViewModelService
}
```

> Important: Never call `resolveMain()` from a non-`@MainActor` context. The compiler will prevent this in strict concurrency mode.

## Environment Context with TaskLocal

Service uses `TaskLocal` to maintain environment context across async boundaries.

```swift
// Default: uses .online environment
let service1 = try ServiceEnv.current.resolve(MyService.self)

// Switch environment for this task
await ServiceEnv.$current.withValue(.dev) {
    let service2 = try ServiceEnv.current.resolve(MyService.self)  // Uses .dev

    // Child tasks inherit the environment
    Task {
        let service3 = try ServiceEnv.current.resolve(MyService.self)  // Also uses .dev
    }
}

// Back to .online
let service4 = try ServiceEnv.current.resolve(MyService.self)
```

## Concurrent Resolution

Service safely handles multiple concurrent resolutions. The behavior depends on the registered scope:

```swift
// Singleton: all tasks resolve the same cached instance
await withTaskGroup(of: MyService.self) { group in
    for _ in 0..<10 {
        group.addTask {
            try ServiceEnv.current.resolve(MyService.self)
        }
    }

    for await service in group {
        // All return the same instance (singleton)
    }
}

// Transient: each task gets a fresh instance
env.register(Worker.self, scope: .transient) { Worker() }
await withTaskGroup(of: Worker.self) { group in
    for _ in 0..<10 {
        group.addTask {
            try ServiceEnv.current.resolve(Worker.self)
        }
    }

    for await worker in group {
        // Each is a different instance
    }
}
```

## Scopes and Concurrency

Service scopes interact with concurrency in important ways:

### Singleton and Custom Scopes

For singleton and custom-scoped services, the factory runs at most once per cached instance. When several threads resolve the same service for the first time, one thread runs the factory. The other threads wait for it and receive the same instance. Resolving a different service is not blocked.

```swift
env.register(DatabaseService.self, scope: .singleton) { DatabaseService() }

// Safe: the factory runs once, and concurrent resolves return the same instance
await withTaskGroup(of: DatabaseService.self) { group in
    for _ in 0..<10 {
        group.addTask {
            try ServiceEnv.current.resolve(DatabaseService.self)
        }
    }
}
```

The semantics match `swift_once` and the lazy initialization of global variables:

- **A failed factory is retried.** If the factory throws, nothing is cached. The next resolution runs the factory again.
- **A reset does not wait for a running factory.** If `resetCaches()`, `resetScope(_:)`, or `resetAll()` is called while a factory is running, that resolution and the resolutions already waiting for it still return the instance it creates. The instance is not cached, and later resolutions create a new one.

The same limitations apply:

- **A factory must not block on another thread that resolves the same service.** The other thread waits for the factory to finish, so neither thread can continue. For example, the factory of a service that the main thread also resolves must not call `DispatchQueue.main.sync`.
- **A factory must not run another task on its own thread that resolves the same service.** Cycle detection follows one task. It does not cover a different task that runs on the same thread before the factory returns, for example a main-actor task that a nested run loop inside the factory executes. The result depends on how the service is registered:
    - With `registerMain`: that resolution throws ``ServiceError/circularDependency(serviceType:chain:)``. The factory runs once, and the resolution that runs it returns the instance.
    - With `register`: that resolution re-enters creation on the same thread, and the process crashes.
- **A dependency cycle that two threads enter at different services can deadlock.** Resolving a cycle from one thread always throws ``ServiceError/circularDependency(serviceType:chain:)``. If two threads resolve the same cycle for the first time at the same moment, each starting from a different service, each thread can hold one service while it waits for the other. See <doc:CircularDependencies>.

### Graph Scope

Graph scope uses `@TaskLocal` storage to share instances within a single resolution chain. Each top-level `resolve()` call creates a new graph context:

```swift
env.register(UnitOfWork.self, scope: .graph) { UnitOfWork() }

// resolve(ServiceA) starts a new graph
//   ├── resolve(UnitOfWork)  ← creates instance X
//   └── resolve(ServiceB)
//         └── resolve(UnitOfWork)  ← reuses instance X (same graph)
//
// resolve(ServiceA) again starts another graph
//   └── resolve(UnitOfWork)  ← creates instance Y (new graph)
```

Since graph caching is task-local, concurrent top-level resolves on different tasks naturally get independent graph caches with no synchronization overhead.

### @Provider with Transient Scope

When using `@Provider` with `.transient` scope, each access creates a new instance. Be mindful that in concurrent code, this means each access point gets its own instance:

```swift
env.register(RequestHandler.self, scope: .transient) { RequestHandler() }

struct Controller {
    @Provider var handler: RequestHandler  // New instance on each access
}
```

## Best Practices

### Use Sendable for Shared Services

```swift
struct DatabaseService: Sendable {
    let connectionString: String  // Immutable state is automatically Sendable
}
```

### Use MainActor for UI Services

```swift
@MainActor
final class ViewModelService {
    @Published var data: String = ""  // UI state on main thread
}
```

### Avoid Context Mixing

```swift
// ❌ Don't do this
func badExample() {
    let viewModel = try ServiceEnv.current.resolveMain(ViewModelService.self)  // Compiler error!
}

// ✅ Do this
@MainActor
func goodExample() {
    let viewModel = try ServiceEnv.current.resolveMain(ViewModelService.self)  // OK
}
```

### Use TaskLocal for Test Isolation

```swift
@Test func testServiceBehavior() {
    let env = ServiceEnv(name: "test")
    ServiceEnv.$current.withValue(env) {
        // Test code uses an isolated environment
    }
}
```

Create a new `ServiceEnv` in each test. Predefined environments are shared by the whole process; see <doc:ServiceEnvironments>.

## Common Patterns

### Sendable Service Used by MainActor Service

```swift
// Sendable service
struct APIClient: Sendable {
    func fetchData() async -> Data { /* ... */ }
}

// MainActor service using Sendable dependency
@MainActor
final class ViewModel {
    let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func loadData() async {
        let data = await api.fetchData()
        // Update UI state...
    }
}

// Registration
ServiceEnv.current.register(APIClient.self) { APIClient() }

await MainActor.run {
    ServiceEnv.current.registerMain(ViewModel.self) {
        let api = try ServiceEnv.current.resolve(APIClient.self)
        return ViewModel(api: api)
    }
}
```

## Thread Safety Guarantees

Service provides these thread-safety guarantees:

- **Registration**: Thread-safe through internal locking
- **Resolution**: Thread-safe through internal locking
- **Singleton and custom-scope creation**: The factory runs at most once per cached instance; concurrent resolvers of the same service wait
- **Environment switching**: Thread-safe through `TaskLocal` storage
- **Cache management**: Thread-safe through internal locking

For implementation details, see <doc:UnderstandingService>.

## See Also

- <doc:MainActorServices>
- <doc:UnderstandingService>
- <doc:MigratingFromSwinject>
