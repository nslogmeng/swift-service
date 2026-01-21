# 🌏 Chinese Localization

## Comprehensive Chinese Documentation
We're excited to announce full Chinese localization support! All documentation is now available in Simplified Chinese (简体中文), making Service more accessible to Chinese-speaking developers worldwide.

**What's included:**
- Complete Chinese translation of all documentation articles
- Localized README with Chinese examples and usage guides  
- Chinese documentation for Swift Package Index integration
- Bilingual support in all documentation topics with easy language switching

**Access Chinese documentation:**
- GitHub README: [README.zh-Hans.md](./README.zh-Hans.md)
- Swift Package Index: Chinese documentation is now available
- All articles include language toggle links for seamless navigation

# ✨ New Features

## MainActor Service Support
Service now provides dedicated APIs for MainActor-isolated services, making it easy to work with UI components and view models that don't conform to `Sendable`.

**Key features:**
- **MainActor service registration**: Register services bound to the main actor
  ```swift
  await MainActor.run {
      ServiceEnv.current.registerMain(ViewModelService.self) {
          ViewModelService()
      }
  }
  ```

- **MainActor service resolution**: Resolve MainActor services with `resolveMain`
  ```swift
  @MainActor
  func setupUI() {
      let viewModel = ServiceEnv.current.resolveMain(ViewModelService.self)
      viewModel.loadData()
  }
  ```

- **MainActor property wrapper**: Use `@MainService` for automatic injection
  ```swift
  @MainActor
  class ViewController {
      @MainService
      var viewModel: ViewModelService
  }
  ```

This feature is particularly useful in Swift 6's strict concurrency model, where `@MainActor` classes are thread-safe but not automatically `Sendable`.

## Automatic Circular Dependency Detection
Service now automatically detects circular dependencies during service resolution through the new `ServiceContext` system. When a circular dependency is detected (e.g., A → B → C → A), the program will terminate with a clear error message showing the full dependency chain.

**Example error message:**
```
Circular dependency detected for service 'AService'.
Dependency chain: AService -> BService -> CService -> AService
Check your service registration to break the cycle.
```

## Resolution Depth Protection
The new `ServiceContext` also prevents stack overflow from excessively deep dependency graphs by enforcing a maximum resolution depth (default: 100). If exceeded, a clear error message is provided to help identify the issue.

**Example error message:**
```
Maximum resolution depth (100) exceeded.
Current chain: ServiceA -> ServiceB -> ServiceC -> ...
This may indicate a circular dependency or overly deep dependency graph.
```

These features help catch dependency issues early during development and provide actionable feedback to resolve them.

## Enhanced Service Registration API
New convenience methods for easier service registration:

- **MainActor instance registration**: Register pre-created MainActor instances directly
  ```swift
  await MainActor.run {
      ServiceEnv.current.registerMain(myViewModelInstance)
  }
  ```

- **ServiceKey support**: Simplified registration using `ServiceKey` protocol for both Sendable and MainActor services
  ```swift
  ServiceEnv.current.register(MyService.self)  // Uses ServiceKey.default
  await MainActor.run {
      ServiceEnv.current.registerMain(MyViewModel.self)  // Uses ServiceKey.default
  }
  ```

# 🔧 Improvements

## Enhanced Thread Safety and Swift 6.2 Support
Service now requires Swift 6.2 and has been enhanced for better compatibility with the latest Swift concurrency features. These improvements ensure:

- **Better thread safety**: More reliable behavior in concurrent and async contexts
- **Improved type safety**: Better compile-time checking for potential concurrency issues
- **Enhanced compatibility**: Full support for Swift 6.2 concurrency features

**Migration Note:** If you're using Swift 6.0 or 6.1, you'll need to update to Swift 6.2 or later. Most projects using Swift 6.0+ should have a smooth upgrade path with minimal code changes.

# 🐛 Bug Fixes

- Fixed compatibility issues with different Swift compiler versions
- Improved error handling in service resolution

---

**Full changelog:** [View commit history](https://github.com/nslogmeng/swift-service/compare/1.0.4...1.0.5)