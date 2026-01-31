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

## Service Lifecycle

By default, services are cached as singletons. The first time a service is resolved, it's created and cached. Subsequent resolutions return the same instance.

To clear cached services (while keeping registrations):

```swift
await ServiceEnv.current.resetCaches()
```

To completely reset the environment (clears cache and removes all registrations):

```swift
await ServiceEnv.current.resetAll()
```

## Next Steps

- Learn about <doc:ServiceEnvironments> for environment-based service configurations
- Explore <doc:MainActorServices> for UI-related services
- Check out <doc:ServiceAssembly> for organizing service registrations
