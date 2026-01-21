# 🔧 Improvements

## Enhanced Thread Safety for ServiceAssembly
Improved thread safety by marking `ServiceAssembly` protocol with `@MainActor` instead of `Sendable`. This ensures that service assembly operations are executed in a predictable, sequential context during application initialization.

**Why `@MainActor`?**
Service assembly typically occurs during application initialization, which is a very early stage of the application lifecycle. Assembly operations are strongly dependent on execution order and are usually performed in `main.swift` or SwiftUI App's `init` method, where the code is already running on the main actor. Constraining assembly operations to the main actor ensures thread safety and provides a predictable, sequential execution context for service registration.

**Migration Note:** If you're calling `assemble()` from a non-main actor context, wrap it with `await MainActor.run { }`:

```swift
// If not on the main actor, use:
await MainActor.run {
    ServiceEnv.current.assemble(MyAssembly())
}
```

In SwiftUI apps, you're typically already on the main actor, so no special handling is needed.

# 📚 Documentation

- Added comprehensive documentation explaining `@MainActor` usage for `ServiceAssembly`
- Enhanced README with detailed examples for calling `assemble()` from different contexts
- Updated API reference with thread safety notes and usage guidelines
- Fixed typo in README

# 🧪 Testing

- Updated tests to ensure proper `@MainActor` context handling
- Improved test coverage for service assembly in different execution contexts

---

**Full changelog:** [View commit history](https://github.com/nslogmeng/swift-service/compare/1.0.3...1.0.4)