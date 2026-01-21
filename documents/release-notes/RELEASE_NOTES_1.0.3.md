# ✨ New Features

## Service Lifecycle Management
Introduce `resetCaches()` and `resetAll()` methods to `ServiceEnv` for better control over service lifecycle and testing scenarios.

**`resetCaches()`** - Clears all cached service instances while keeping registered providers intact. Services will be recreated on the next resolution using their factory functions. Perfect for testing scenarios where you need fresh instances.

```swift
// Register a service
ServiceEnv.current.register(String.self) {
    UUID().uuidString
}

let service1 = ServiceEnv.current.resolve(String.self)

// Clear cache - next resolution will create a new instance
ServiceEnv.current.resetCaches()
let service2 = ServiceEnv.current.resolve(String.self)
// service1 != service2 (new instance created)
```

**`resetAll()`** - Completely resets the service environment by clearing both cached instances and all registered providers. All services must be re-registered after calling this method.

```swift
// Register services
ServiceEnv.current.register(DatabaseProtocol.self) {
    DatabaseService()
}

// Reset everything
ServiceEnv.current.resetAll()

// Services must be re-registered
ServiceEnv.current.register(DatabaseProtocol.self) {
    DatabaseService()
}
```

## Variadic Arguments for ServiceAssembly
Added support for variadic arguments in the `assemble()` method, providing more flexible assembly syntax.

```swift
// Now you can use variadic arguments
ServiceEnv.current.assemble(
    DatabaseAssembly(),
    NetworkAssembly(),
    RepositoryAssembly()
)
```

# 🔧 Improvements

- Replaced subscript access with explicit `resolve()` method in `ServiceEnv` for improved API clarity and consistency
- Enhanced documentation with comprehensive examples for new lifecycle management methods

# 📚 Documentation

- Updated README with `resetCaches()` and `resetAll()` usage examples
- Added variadic arguments example for `ServiceAssembly.assemble()`
- Improved API reference documentation

---

**Full changelog:** [View commit history](https://github.com/nslogmeng/swift-service/compare/1.0.2...1.0.3)

