# Concurrency Model

Service is designed to work seamlessly with Swift's concurrency model, providing safe and efficient dependency injection in concurrent contexts.

> Localization: **English**  |  **[简体中文](<doc:ConcurrencyModel.zh-Hans>)**

## Swift Concurrency Basics

Swift 6 introduces strict concurrency checking, requiring types to be explicitly marked as `Sendable` to be safely shared across concurrent contexts. Service respects these requirements while providing convenient APIs for both `Sendable` and `@MainActor`-isolated services.

## Sendable Services

Services that conform to `Sendable` can be safely shared across concurrent contexts. These are the default services in Service.

### Registration

```swift
// Service must conform to Sendable
struct DatabaseService: Sendable {
    let connectionString: String
}

// Register as Sendable service
ServiceEnv.current.register(DatabaseService.self) {
    DatabaseService(connectionString: "sqlite://app.db")
}
```

### Resolution

```swift
// Can be resolved from any context
let database = ServiceEnv.current.resolve(DatabaseService.self)

// Can be used in async contexts
Task {
    let database = ServiceEnv.current.resolve(DatabaseService.self)
    // Use database...
}
```

### Property Wrapper

```swift
struct UserRepository: Sendable {
    @Service
    var database: DatabaseService  // Automatically resolved
}
```

## MainActor Services

Services that are `@MainActor`-isolated are thread-safe (all access is serialized on the main thread) but are **not** automatically `Sendable`. Service provides separate APIs for these services.

### Why Not Sendable?

In Swift 6, `@MainActor` classes are not automatically `Sendable` because:

1. They have mutable state
2. They're isolated to a specific actor (main actor)
3. Cross-actor communication requires explicit `Sendable` conformance

However, they're still thread-safe because all access is serialized on the main thread.

### Registration

```swift
@MainActor
final class ViewModelService {
    var data: String = ""
}

// Must register from @MainActor context
await MainActor.run {
    ServiceEnv.current.registerMain(ViewModelService.self) {
        ViewModelService()
    }
}
```

### Resolution

```swift
// Must resolve from @MainActor context
@MainActor
func setupUI() {
    let viewModel = ServiceEnv.current.resolveMain(ViewModelService.self)
    viewModel.loadData()
}
```

### Property Wrapper

```swift
@MainActor
class MyViewController {
    @MainService
    var viewModel: ViewModelService  // Automatically resolved
}
```

## TaskLocal and Environment Context

Service uses `TaskLocal` to maintain environment context across async boundaries:

```swift
@TaskLocal
public static var current: ServiceEnv = .online
```

### How It Works

1. **Task-scoped**: Each async task maintains its own environment context
2. **Inheritance**: Child tasks inherit the parent's environment
3. **Isolation**: Environment switches are isolated to the current task

### Example

```swift
// Default environment
let service1 = ServiceEnv.current.resolve(MyService.self)  // Uses .online

// Switch environment for this task
await ServiceEnv.$current.withValue(.dev) {
    let service2 = ServiceEnv.current.resolve(MyService.self)  // Uses .dev
    
    // Child task inherits environment
    Task {
        let service3 = ServiceEnv.current.resolve(MyService.self)  // Uses .dev
    }
}

// Back to default environment
let service4 = ServiceEnv.current.resolve(MyService.self)  // Uses .online
```

## Thread Safety

Service ensures thread safety through:

### Internal Locking

Service uses internal locks to protect shared state:

```swift
class ServiceStorage {
    private let lock = Lock()
    private var providers: [String: Any] = [:]
    private var cache: [String: Any] = [:]
    
    func register<Service: Sendable>(...) {
        lock.lock()
        defer { lock.unlock() }
        // Register service...
    }
}
```

### Sendable Requirements

All public APIs that work with `Sendable` services require `Sendable` conformance:

```swift
public func register<Service: Sendable>(
    _ type: Service.Type,
    factory: @escaping @Sendable () -> Service
)
```

### MainActor Isolation

MainActor services are isolated to the main actor, ensuring thread safety:

```swift
@MainActor
public func registerMain<Service>(
    _ type: Service.Type,
    factory: @escaping @MainActor () -> Service
)
```

## Concurrent Resolution

Service supports concurrent resolution of services:

```swift
// Multiple concurrent resolutions
await withTaskGroup(of: MyService.self) { group in
    for _ in 0..<10 {
        group.addTask {
            ServiceEnv.current.resolve(MyService.self)
        }
    }
    
    // All tasks resolve the same cached instance
    for await service in group {
        // Use service...
    }
}
```

## Best Practices

### 1. Use Sendable for Concurrent Services

If your service needs to be used across concurrent contexts, make it `Sendable`:

```swift
struct DatabaseService: Sendable {
    // Immutable or thread-safe state
    let connectionString: String
}
```

### 2. Use MainActor for UI Services

For UI-related services, use `@MainActor`:

```swift
@MainActor
final class ViewModelService {
    // UI state that must be on main thread
    @Published var data: String = ""
}
```

### 3. Avoid Mixing Contexts

Don't try to use `@MainActor` services from non-`@MainActor` contexts:

```swift
// ❌ Don't do this
func badExample() {
    let viewModel = ServiceEnv.current.resolveMain(ViewModelService.self)  // Error!
}

// ✅ Do this
@MainActor
func goodExample() {
    let viewModel = ServiceEnv.current.resolveMain(ViewModelService.self)  // OK
}
```

### 4. Use TaskLocal for Environment Switching

Use `TaskLocal` for environment switching in tests:

```swift
func testExample() async {
    await ServiceEnv.$current.withValue(.test) {
        // Test code uses test environment
    }
}
```

## Common Patterns

### Pattern 1: Sendable Service with MainActor Dependency

```swift
// Sendable service
struct APIClient: Sendable {
    func fetchData() async -> Data { /* ... */ }
}

// MainActor service that uses Sendable service
@MainActor
final class ViewModel {
    let api: APIClient
    
    init(api: APIClient) {
        self.api = api
    }
    
    func loadData() async {
        let data = await api.fetchData()  // OK - async call
        // Update UI state...
    }
}

// Registration
ServiceEnv.current.register(APIClient.self) {
    APIClient()
}

await MainActor.run {
    ServiceEnv.current.registerMain(ViewModel.self) {
        let api = ServiceEnv.current.resolve(APIClient.self)
        return ViewModel(api: api)
    }
}
```

### Pattern 2: Multiple Environments

```swift
// Register in different environments
ServiceEnv.online.register(APIClient.self) {
    APIClient(baseURL: "https://api.example.com")
}

ServiceEnv.dev.register(APIClient.self) {
    APIClient(baseURL: "https://dev-api.example.com")
}

// Use in code
await ServiceEnv.$current.withValue(.dev) {
    let client = ServiceEnv.current.resolve(APIClient.self)  // Uses dev
}
```

## Performance Considerations

### Caching

Service caches resolved instances, which is safe for concurrent access:

- **Thread-safe cache**: Protected by internal locks
- **Singleton behavior**: Same instance returned for concurrent resolutions
- **Memory trade-off**: Cached instances consume memory

### Lock Contention

Service uses coarse-grained locking, which is simple but may cause contention:

- **Low contention**: Typical use cases have minimal contention
- **Simple design**: Easier to reason about and maintain
- **Future optimization**: Could be optimized with fine-grained locking if needed

## Next Steps

- Read <doc:MainActorServices> for more details on MainActor services
- Explore <doc:UnderstandingService> for architecture details
- Check out <doc:RealWorldExamples> for practical patterns
