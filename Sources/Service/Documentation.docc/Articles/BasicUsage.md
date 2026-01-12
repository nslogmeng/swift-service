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

For services with default implementations, use the `ServiceKey` protocol:

```swift
struct DatabaseService: ServiceKey {
    static var `default`: DatabaseService {
        DatabaseService(connectionString: "sqlite://app.db")
    }
}

// Register using the default implementation
ServiceEnv.current.register(DatabaseService.self)
```

## Injecting Services

### Using @Service Property Wrapper

The `@Service` property wrapper automatically resolves services when your type is initialized:

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

### Explicit Type Specification

When the property type might be ambiguous, explicitly specify the service type:

```swift
struct UserRepository {
    @Service(DatabaseProtocol.self)
    var database: DatabaseProtocol
}
```

### Manual Resolution

You can also resolve services manually:

```swift
let database = ServiceEnv.current.resolve(DatabaseProtocol.self)
let logger = ServiceEnv.current.resolve(LoggerProtocol.self)
```

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
    let database = ServiceEnv.current.resolve(DatabaseProtocol.self)
    let logger = ServiceEnv.current.resolve(LoggerProtocol.self)
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
