# ✨ New Features

## ServiceAssembly Protocol
Introduce `ServiceAssembly` protocol for modular, reusable service registration, similar to Swinject's Assembly pattern.

**Usage example:**
```swift
struct DatabaseAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.register(DatabaseProtocol.self) {
            DatabaseService(connectionString: "sqlite://app.db")
        }
    }
}

// Assemble a single assembly
ServiceEnv.current.assemble(DatabaseAssembly())

// Assemble multiple assemblies
ServiceEnv.current.assemble([
    DatabaseAssembly(),
    NetworkAssembly(),
    RepositoryAssembly()
])
```

# 📚 Documentation

- Updated README with ServiceAssembly usage examples
- Enhanced API reference documentation

# 🔧 Improvements

- Refactored import statements in `Lock.swift` for better readability
- Improved test coverage

---

**Full changelog:** [View commit history](https://github.com/nslogmeng/swift-service/compare/1.0.1...1.0.2)