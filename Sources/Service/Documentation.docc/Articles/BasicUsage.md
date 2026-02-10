# Basic Usage

Learn the fundamental patterns for registering and using services with Service.

> Localization: **English**  |  **[简体中文](https://nslogmeng.github.io/swift-service/zh-Hans/documentation/service/basicusage)**

## Registering Services

Service provides multiple ways to register services, each suited for different scenarios.

### Factory Function Registration

The most common pattern is to register a service using a factory function:

```swift
// Register a protocol-based service
ServiceEnv.current.register(DatabaseProtocol.self) {
    DatabaseService(connectionString: "sqlite://app.db")
}

// Register a concrete type
ServiceEnv.current.register(LoggerService.self) {
    LoggerService(logLevel: .info)
}
```

You can also specify a **scope** to control the service's lifecycle:

```swift
// Transient: new instance every time
ServiceEnv.current.register(RequestHandler.self, scope: .transient) {
    RequestHandler()
}

// Custom scope: shared cache that can be independently invalidated
ServiceEnv.current.register(SessionService.self, scope: .custom("user-session")) {
    SessionService()
}
```

For details on all available scopes, see <doc:BasicUsage#Service-Lifecycle-and-Scopes>.

### Direct Instance Registration

For services that are already instantiated, you can register them directly:

```swift
let database = DatabaseService(connectionString: "sqlite://app.db")
ServiceEnv.current.register(database)
```

### ServiceKey Protocol

For services with default implementations, use the `ServiceKey` protocol. This reduces boilerplate when your service has a sensible default configuration:

```swift
struct DatabaseService: ServiceKey {
    let connectionString: String

    static var `default`: DatabaseService {
        DatabaseService(connectionString: "sqlite://app.db")
    }
}

// Register using the default implementation
ServiceEnv.current.register(DatabaseService.self)

// Or override with a custom factory
ServiceEnv.current.register(DatabaseService.self) {
    DatabaseService(connectionString: "postgresql://prod.db")
}
```

**When to use ServiceKey:**
- Services with a common default configuration
- Simple services that don't require complex initialization
- Reducing registration boilerplate in assemblies

For more details on the design of ServiceKey, see <doc:UnderstandingService>.

## Injecting Services

### Using @Service Property Wrapper

The `@Service` property wrapper provides lazy dependency injection. Services are resolved on first access (not at initialization time), and the result is cached for subsequent accesses:

```swift
struct UserRepository {
    @Service
    var database: DatabaseProtocol

    @Service
    var logger: LoggerProtocol

    func fetchUser(id: String) -> User? {
        logger.info("Fetching user: \(id)")
        return database.findUser(id: id)
    }
}
```

The environment is captured at initialization time, ensuring consistent behavior regardless of when the property is first accessed.

### Explicit Type Specification

When the property type might be ambiguous, explicitly specify the service type:

```swift
struct UserRepository {
    @Service(DatabaseProtocol.self)
    var database: DatabaseProtocol
}
```

### Optional Services

For services that may not be registered, use optional types. The property returns `nil` instead of causing a fatal error:

```swift
struct UserController {
    @Service var analytics: AnalyticsService?  // Returns nil if not registered

    func trackEvent(_ event: String) {
        analytics?.track(event)  // Safe optional access
    }
}
```

You can also use explicit type specification with optionals:

```swift
struct UserController {
    @Service(AnalyticsService.self)
    var analytics: AnalyticsService?
}
```

> Tip: All four property wrappers (`@Service`, `@MainService`, `@Provider`, `@MainProvider`) support optional types.

### Using @Provider Property Wrapper

The `@Provider` property wrapper resolves the service on **every access**, delegating caching behavior entirely to the service's registered scope. Unlike `@Service` which always caches locally, `@Provider` is ideal for transient or custom-scoped services:

```swift
// Register a transient service
ServiceEnv.current.register(RequestHandler.self, scope: .transient) {
    RequestHandler()
}

struct Controller {
    @Provider var handler: RequestHandler  // New instance on every access
}
```

`@Provider` also supports optional types:

```swift
struct Controller {
    @Provider var analytics: AnalyticsService?  // Returns nil if not registered
}
```

**When to use @Service vs @Provider:**

| | `@Service` / `@MainService` | `@Provider` / `@MainProvider` |
|---|---|---|
| Resolution | Lazy, on first access | On every access |
| Local caching | Always caches locally | No local cache; delegates to scope |
| Best for | Singleton services | Transient or custom-scoped services |

For MainActor-isolated equivalents, see `@MainProvider` in <doc:MainActorServices>.

### Manual Resolution

You can also resolve services manually using `try`:

```swift
let database = try ServiceEnv.current.resolve(DatabaseProtocol.self)
let logger = try ServiceEnv.current.resolve(LoggerProtocol.self)
```

For error handling details, see <doc:ErrorHandling>.

## Dependency Injection

Services can depend on other services. When registering a service, you can resolve its dependencies:

```swift
// Register base services
ServiceEnv.current.register(DatabaseProtocol.self) {
    DatabaseService()
}

ServiceEnv.current.register(LoggerProtocol.self) {
    LoggerService()
}

// Register a service that depends on other services
ServiceEnv.current.register(UserRepositoryProtocol.self) {
    let database = try ServiceEnv.current.resolve(DatabaseProtocol.self)
    let logger = try ServiceEnv.current.resolve(LoggerProtocol.self)
    return UserRepository(database: database, logger: logger)
}
```

## Service Lifecycle and Scopes

By default, services are registered with `.singleton` scope -- the first time a service is resolved, it's created and cached. Subsequent resolutions return the same instance.

Service supports four lifecycle scopes via ``ServiceScope``:

| Scope | Behavior |
|-------|----------|
| `.singleton` | Single instance cached globally (default) |
| `.transient` | New instance created on every resolution |
| `.graph` | Shared within the same resolution graph; fresh instance for each top-level `resolve()` call |
| `.custom("name")` | Named scope with independent cache, allowing targeted invalidation |

```swift
// Singleton (default) - same instance reused
env.register(DatabaseService.self) { DatabaseService() }

// Transient - new instance each time
env.register(RequestHandler.self, scope: .transient) { RequestHandler() }

// Graph - shared within one resolve chain
env.register(UnitOfWork.self, scope: .graph) { UnitOfWork() }

// Custom - named scope with independent cache
env.register(SessionService.self, scope: .custom("user-session")) { SessionService() }
```

### Resetting Services

To clear cached services (while keeping registrations):

```swift
ServiceEnv.current.resetCaches()
```

To clear only a specific scope (e.g., on user logout):

```swift
ServiceEnv.current.resetScope(.custom("user-session"))
```

To completely reset the environment (clears cache and removes all registrations):

```swift
ServiceEnv.current.resetAll()
```

For more details on resetting, see <doc:ServiceEnvironments>.

## Next Steps

- Learn about <doc:ServiceEnvironments> for environment-based service configurations
- Explore <doc:MainActorServices> for UI-related services
- Check out <doc:ServiceAssembly> for organizing service registrations
