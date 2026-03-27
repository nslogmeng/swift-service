# Migrating from Swinject

A step-by-step guide to migrating your dependency injection from Swinject to Service.

> Localization: **English**  |  **[简体中文](https://nslogmeng.github.io/swift-service/zh-Hans/documentation/service/migratingfromswinject)**

## Why Migrate?

Service is designed from the ground up for modern Swift:

- **Swift 6 Concurrency Safety** — Sendable and MainActor constraints are part of the API, with compile-time enforcement instead of runtime crashes
- **Zero Dependencies** — No external packages; built entirely on Swift standard library primitives
- **Native Property Wrappers** — `@Service`, `@MainService`, `@Provider`, `@MainProvider` for declarative injection without boilerplate
- **TaskLocal Environment Isolation** — Tests run in parallel without polluting each other; no need to manage container lifetimes manually

## Concept Mapping

| Swinject | Service | Notes |
|----------|---------|-------|
| `Container` | `ServiceEnv` | TaskLocal-based, no need to pass around |
| `container.register` | `env.register` / `env.registerMain` | Separate tracks for Sendable and MainActor services |
| `container.resolve` | `@Service` / `try env.resolve` | Property wrapper or manual typed throws |
| `Assembly` + `Assembler` | `ServiceAssembly` + `env.assemble()` | Simplified, no separate Assembler type |
| `.container` scope | `.singleton` scope | Same behavior, default in both frameworks |
| `.transient` scope | `.transient` scope | Identical behavior |
| `.graph` scope | `.graph` scope | Identical behavior |
| `.weak` scope | — | No direct equivalent; consider `.custom` scope |
| `container.synchronize()` | Built-in | Thread safety via Mutex and MainActor isolation |
| `name:` parameter | Protocol / type differentiation | Use distinct protocols instead of string names |

## Container → ServiceEnv

In Swinject, you create and manage a `Container` instance, passing it around or storing it as a global singleton:

```swift
// Swinject
let container = Container()
container.register(DatabaseProtocol.self) { _ in DatabaseService() }

// Must pass container to where it's needed
let database = container.resolve(DatabaseProtocol.self)!
```

In Service, `ServiceEnv` uses Swift's `@TaskLocal` mechanism. The current environment is always accessible via `ServiceEnv.current` without passing it explicitly:

```swift
// Service
ServiceEnv.current.register(DatabaseProtocol.self) {
    DatabaseService()
}

// Accessible anywhere in the same task
let database = try ServiceEnv.current.resolve(DatabaseProtocol.self)
```

> Tip: `ServiceEnv.current` automatically propagates through `async`/`await` boundaries and into child tasks — no manual plumbing required.

## Registration

### Factory Registration

The most common registration pattern. Note that Service's factory closure does not take a resolver parameter:

```swift
// Swinject
container.register(DatabaseProtocol.self) { _ in
    DatabaseService(connectionString: "sqlite://app.db")
}

// Service
ServiceEnv.current.register(DatabaseProtocol.self) {
    DatabaseService(connectionString: "sqlite://app.db")
}
```

### Registration with Dependencies

Swinject passes a `Resolver` into the factory closure; Service uses `ServiceEnv.current` directly and leverages typed throws instead of force-unwrapping:

```swift
// Swinject
container.register(UserRepositoryProtocol.self) { r in
    let database = r.resolve(DatabaseProtocol.self)!
    let logger = r.resolve(LoggerProtocol.self)!
    return UserRepository(database: database, logger: logger)
}

// Service
ServiceEnv.current.register(UserRepositoryProtocol.self) {
    let database = try ServiceEnv.current.resolve(DatabaseProtocol.self)
    let logger = try ServiceEnv.current.resolve(LoggerProtocol.self)
    return UserRepository(database: database, logger: logger)
}
```

### Direct Instance Registration

```swift
// Swinject
let database = DatabaseService()
container.register(DatabaseProtocol.self) { _ in database }

// Service
let database = DatabaseService()
ServiceEnv.current.register(database)
```

### MainActor Services

Swinject has no built-in concept of actor isolation. Service provides dedicated APIs for MainActor-bound types (e.g., view models):

```swift
// Service only — no Swinject equivalent
ServiceEnv.current.registerMain(UserViewModel.self) {
    let api = try ServiceEnv.current.resolve(APIClientProtocol.self)
    return UserViewModel(apiClient: api)
}
```

For details, see <doc:MainActorServices>.

## Resolution

### Manual Resolution

Swinject returns an optional that is typically force-unwrapped. Service uses typed throws for safer error handling:

```swift
// Swinject
let database = container.resolve(DatabaseProtocol.self)!

// Service
let database = try ServiceEnv.current.resolve(DatabaseProtocol.self)
```

### Property Wrapper Injection

Swinject has no built-in property wrappers. Service provides four, eliminating the need for manual resolution in most cases:

```swift
// Service — lazy, cached injection
struct UserRepository {
    @Service var database: DatabaseProtocol
    @Service var logger: LoggerProtocol
}

// Just use it — services resolve on first access
let repo = UserRepository()
repo.database.query("SELECT ...")
```

For optional dependencies that may not be registered:

```swift
struct UserController {
    @Service var analytics: AnalyticsService?  // Returns nil if not registered
}
```

For MainActor-isolated services:

```swift
@MainActor
final class ProfileViewController: UIViewController {
    @MainService var viewModel: ProfileViewModel
}
```

For a complete comparison of `@Service` vs `@Provider`, see <doc:BasicUsage>.

## Scopes

Swinject configures scopes via method chaining; Service uses the `scope` parameter at registration time:

| Swinject | Service | Behavior |
|----------|---------|----------|
| `.transient` | `.transient` | New instance every resolution |
| `.graph` | `.graph` | Shared within the same resolution chain |
| `.container` | `.singleton` | Single cached instance (default in both) |
| `.weak` | — | No direct equivalent |
| — | `.custom("name")` | Named scope with independent cache |

```swift
// Swinject
container.register(RequestHandler.self) { _ in RequestHandler() }
    .inObjectScope(.transient)

// Service
ServiceEnv.current.register(RequestHandler.self, scope: .transient) {
    RequestHandler()
}
```

Custom scopes can be independently invalidated:

```swift
ServiceEnv.current.register(SessionService.self, scope: .custom("user-session")) {
    SessionService()
}

// On user logout, clear only session-scoped services
ServiceEnv.current.resetScope(.custom("user-session"))
```

For details, see <doc:BasicUsage#Service-Lifecycle-and-Scopes>.

## Assembly

Swinject uses `Assembly` protocol with `Assembler` to manage assembly lifecycle. Service simplifies this with `ServiceAssembly` and direct `assemble()` calls:

```swift
// Swinject
class NetworkAssembly: Assembly {
    func assemble(container: Container) {
        container.register(APIClientProtocol.self) { _ in
            APIClient()
        }
    }
}

let assembler = Assembler([
    NetworkAssembly(),
    RepositoryAssembly()
])
let resolver = assembler.resolver

// Service
struct NetworkAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.register(APIClientProtocol.self) {
            APIClient()
        }
    }
}

ServiceEnv.current.assemble(
    NetworkAssembly(),
    RepositoryAssembly()
)
```

Key differences:
- No separate `Assembler` type — call `assemble()` directly on `ServiceEnv`
- `ServiceAssembly` receives `ServiceEnv` instead of `Container`
- Assemblies can use both `register` and `registerMain` for MainActor services

For details, see <doc:ServiceAssembly>.

## Concurrency Safety

Swinject requires manual synchronization for thread safety:

```swift
// Swinject — must explicitly synchronize
let container = Container()
let threadSafeResolver = container.synchronize()
```

Service provides built-in concurrency safety with no extra steps:

```swift
// Service — thread-safe by design
// Sendable services use Mutex-based synchronization
ServiceEnv.current.register(DatabaseProtocol.self) { DatabaseService() }

// MainActor services use actor isolation
ServiceEnv.current.registerMain(UserViewModel.self) { UserViewModel() }
```

The compiler enforces correct usage: Sendable services go through `register`/`resolve`, MainActor services through `registerMain`/`resolveMain`. Using the wrong track is a compile-time error, not a runtime crash.

For details, see <doc:ConcurrencyModel>.

## Testing

Swinject tests typically create a new container per test. Service leverages TaskLocal for environment isolation:

```swift
// Swinject
class UserServiceTests: XCTestCase {
    var container: Container!

    override func setUp() {
        container = Container()
        container.register(DatabaseProtocol.self) { _ in MockDatabase() }
        container.register(UserServiceProtocol.self) { r in
            UserService(database: r.resolve(DatabaseProtocol.self)!)
        }
    }

    func testFetchUser() {
        let service = container.resolve(UserServiceProtocol.self)!
        // ...
    }
}

// Service
final class UserServiceTests: XCTestCase {
    func testFetchUser() async throws {
        let testEnv = ServiceEnv.test
        testEnv.resetAll()

        await ServiceEnv.$current.withValue(testEnv) {
            ServiceEnv.current.register(DatabaseProtocol.self) { MockDatabase() }
            ServiceEnv.current.register(UserServiceProtocol.self) {
                let db = try ServiceEnv.current.resolve(DatabaseProtocol.self)
                return UserService(database: db)
            }

            let service = try ServiceEnv.current.resolve(UserServiceProtocol.self)
            // ...
        }
    }
}
```

Benefits of TaskLocal-based testing:
- Each test function can use its own environment
- Tests can run in parallel without shared state conflicts
- No need for `setUp`/`tearDown` container lifecycle management

For details, see <doc:ServiceEnvironments>.

## Migration Checklist

Use this checklist to track your migration progress:

1. Replace `import Swinject` with `import Service`
2. Replace `Container()` creation with `ServiceEnv.current`
3. Update factory registration — remove the resolver parameter (`r`/`_`) from closures
4. Replace `r.resolve(T.self)!` with `try ServiceEnv.current.resolve(T.self)` in factories
5. Migrate object scopes: `.container` → `.singleton` (default), `.transient` → `.transient`, `.graph` → `.graph`
6. Replace `Assembly` with `ServiceAssembly`, remove `Assembler` usage
7. Add `@Service` / `@MainService` property wrappers to replace manual resolution at call sites
8. Use `registerMain` / `@MainService` for MainActor-bound services (view models, UI controllers)
9. Replace test `setUp` container creation with `ServiceEnv.$current.withValue(.test)`
10. Remove `container.synchronize()` calls — thread safety is built-in
11. Remove Swinject from your `Package.swift` or Podfile dependencies

## Next Steps

- <doc:BasicUsage> for a comprehensive guide to registration and injection patterns
- <doc:MainActorServices> for working with UI-bound services
- <doc:ServiceAssembly> for organizing registrations into modules
- <doc:ServiceEnvironments> for environment-based configuration and testing
