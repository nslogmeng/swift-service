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

Services isolated to `@MainActor` are thread-safe but not `Sendable`. Use separate APIs for these services.

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

Singleton and custom-scoped services use double-check locking to ensure that only one instance is created even under concurrent resolution:

```swift
env.register(DatabaseService.self, scope: .singleton) { DatabaseService() }

// Safe: concurrent resolves return the same instance
await withTaskGroup(of: DatabaseService.self) { group in
    for _ in 0..<10 {
        group.addTask {
            try ServiceEnv.current.resolve(DatabaseService.self)
        }
    }
}
```

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
@Test func testServiceBehavior() async throws {
    await ServiceEnv.$current.withValue(.test) {
        // Test code uses isolated test environment
    }
}
```

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
- **Environment switching**: Thread-safe through `TaskLocal` storage
- **Cache management**: Thread-safe through internal locking

For implementation details, see <doc:UnderstandingService>.

## See Also

- <doc:MainActorServices>
- <doc:UnderstandingService>
- <doc:RealWorldExamples>
