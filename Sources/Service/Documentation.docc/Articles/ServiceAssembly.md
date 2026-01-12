# Service Assembly

Service Assembly provides a standardized, modular way to organize service registrations, similar to Swinject's Assembly pattern.

> Localization: **English**  |  **[简体中文](https://nslogmeng.github.io/swift-service/zh-Hans/documentation/service/serviceassembly)**

## Why Service Assembly?

As your application grows, managing service registrations can become complex. Service Assembly helps you:

- **Organize registrations**: Group related services together
- **Improve reusability**: Share common service configurations across projects
- **Simplify testing**: Easily swap assemblies for different environments
- **Maintain clarity**: Keep registration logic separate from business logic

## Creating an Assembly

Define an assembly by conforming to the `ServiceAssembly` protocol:

```swift
struct DatabaseAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.register(DatabaseProtocol.self) {
            DatabaseService(connectionString: "sqlite://app.db")
        }
    }
}
```

## Assembling Services

### Single Assembly

Assemble a single assembly:

```swift
ServiceEnv.current.assemble(DatabaseAssembly())
```

### Multiple Assemblies

Assemble multiple assemblies at once:

```swift
ServiceEnv.current.assemble([
    DatabaseAssembly(),
    NetworkAssembly(),
    RepositoryAssembly()
])
```

Or using variadic arguments:

```swift
ServiceEnv.current.assemble(
    DatabaseAssembly(),
    NetworkAssembly(),
    RepositoryAssembly()
)
```

## Real-World Example

Here's how you might organize services in a real application:

```swift
// Database Assembly
struct DatabaseAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.register(DatabaseProtocol.self) {
            DatabaseService(connectionString: "sqlite://app.db")
        }
    }
}

// Network Assembly
struct NetworkAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.register(APIClientProtocol.self) {
            let logger = env.resolve(LoggerProtocol.self)
            return APIClient(baseURL: "https://api.example.com", logger: logger)
        }
    }
}

// Repository Assembly
struct RepositoryAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.register(UserRepositoryProtocol.self) {
            let database = env.resolve(DatabaseProtocol.self)
            let logger = env.resolve(LoggerProtocol.self)
            return UserRepository(database: database, logger: logger)
        }
    }
}

// Logger Assembly
struct LoggerAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.register(LoggerProtocol.self) {
            LoggerService(logLevel: .info)
        }
    }
}

// App initialization
@main
struct MyApp: App {
    init() {
        ServiceEnv.current.assemble(
            LoggerAssembly(),      // Register first (others depend on it)
            DatabaseAssembly(),
            NetworkAssembly(),
            RepositoryAssembly()
        )
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

## Environment-Specific Assemblies

You can create different assemblies for different environments:

```swift
// Production Assembly
struct ProductionDatabaseAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.register(DatabaseProtocol.self) {
            DatabaseService(connectionString: "prod://database")
        }
    }
}

// Development Assembly
struct DevelopmentDatabaseAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.register(DatabaseProtocol.self) {
            DatabaseService(connectionString: "dev://database")
        }
    }
}

// Test Assembly
struct TestDatabaseAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.register(DatabaseProtocol.self) {
            InMemoryDatabase()
        }
    }
}

// Use in your app
func setupServices() {
    let env = ServiceEnv.current
    
    if ProcessInfo.processInfo.environment["ENVIRONMENT"] == "test" {
        env.assemble(TestDatabaseAssembly())
    } else if ProcessInfo.processInfo.environment["ENVIRONMENT"] == "development" {
        env.assemble(DevelopmentDatabaseAssembly())
    } else {
        env.assemble(ProductionDatabaseAssembly())
    }
}
```

## MainActor Services in Assemblies

You can register MainActor services in assemblies, but remember that `assemble` must be called from `@MainActor` context:

```swift
struct ViewModelAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        // Register regular services
        env.register(APIClientProtocol.self) {
            APIClient(baseURL: "https://api.example.com")
        }
        
        // Register MainActor service
        env.registerMain(UserViewModel.self) {
            let apiClient = env.resolve(APIClientProtocol.self)
            return UserViewModel(apiClient: apiClient)
        }
    }
}

// In SwiftUI App (already on @MainActor)
@main
struct MyApp: App {
    init() {
        ServiceEnv.current.assemble(ViewModelAssembly())
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

## Why @MainActor?

Service Assembly is marked with `@MainActor` for thread safety. Service assembly typically occurs during application initialization, which is a very early stage of the application lifecycle. Assembly operations are strongly dependent on execution order and are usually performed in `main.swift` or SwiftUI App's `init` method, where the code is already running on the main actor. Constraining assembly operations to the main actor ensures thread safety and provides a predictable, sequential execution context for service registration.

### Calling from Non-MainActor Context

If you need to call `assemble` from a non-`@MainActor` context, use `await MainActor.run`:

```swift
await MainActor.run {
    ServiceEnv.current.assemble(DatabaseAssembly())
}
```

## Best Practices

1. **Order matters**: Register services in dependency order. Services that others depend on should be registered first.

2. **Group by domain**: Create assemblies that group related services (e.g., `DatabaseAssembly`, `NetworkAssembly`).

3. **Keep assemblies focused**: Each assembly should have a single responsibility.

4. **Use for reusability**: If you have common service configurations used across multiple projects, assemblies make it easy to share them.

## Next Steps

- Explore <doc:RealWorldExamples> for more assembly patterns
- Learn about <doc:ServiceEnvironments> for environment-based configurations
- Read <doc:UnderstandingService> for a deeper dive into Service's architecture
