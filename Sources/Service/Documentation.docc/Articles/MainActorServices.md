# MainActor Services

Service provides specialized APIs for working with `@MainActor`-isolated services, such as view models and UI controllers.

> Localization: **English**  |  **[简体中文](https://nslogmeng.github.io/swift-service/zh-Hans/documentation/service/mainactorservices)**

## Background: Why MainActor Services?

The standard `register`/`resolve` APIs are built for services that are shared across isolation domains. The factory is a nonisolated `@Sendable` closure that can run on any thread, and the service type must conform to `Sendable`. A service that is created and used on the main actor often cannot meet these requirements.

### The Problem

Consider a typical view model:

```swift
@MainActor
protocol UserViewModelProtocol {
    var userName: String { get }
}

@MainActor
final class UserViewModel: UserViewModelProtocol {
    var userName: String = ""
    var isLoading: Bool = false

    init() {
        // ... set up initial state
    }

    func loadUser() {
        isLoading = true
        // ... load user data
        isLoading = false
    }
}
```

This view model is `@MainActor`-isolated, meaning all access must happen on the main thread. A `@MainActor` class like this one is implicitly `Sendable`: a reference to it can cross isolation domains, because every access to its state goes through the main actor. Its initializer and members stay isolated, and that is where `register` stops working:

1. The initializer is main-actor-isolated. The `register` factory is nonisolated and synchronous, so it cannot call `UserViewModel()`.
2. The type a service is registered under is often not `Sendable`. `any UserViewModelProtocol` is not `Sendable`, because the protocol is `@MainActor` and does not inherit `Sendable`. A `@MainActor` class that inherits from a non-`Sendable` base class is not `Sendable` either.

### The Solution

Service provides dedicated `registerMain` and `resolveMain` methods (along with the `@MainService` and `@MainProvider` property wrappers). The factory is a `@MainActor` closure, and the instance is created, cached, and resolved only on the main actor. The factory can call main-actor-isolated initializers and resolve other main-actor services, and the service type does not need to conform to `Sendable`.

## Registering MainActor Services

### Using registerMain

Register `@MainActor` services using `registerMain`. Like `register`, you can specify a scope parameter:

```swift
@MainActor
final class UserViewModel {
    var userName: String = ""
    func loadUser() { /* ... */ }
}

// Register on main actor context (default: .singleton)
await MainActor.run {
    ServiceEnv.current.registerMain(UserViewModel.self) {
        UserViewModel()
    }
}

// Register with a specific scope
await MainActor.run {
    ServiceEnv.current.registerMain(UserViewModel.self, scope: .transient) {
        UserViewModel()
    }
}
```

### Direct Instance Registration

You can also register an existing instance:

```swift
await MainActor.run {
    let viewModel = UserViewModel()
    ServiceEnv.current.registerMain(viewModel)
}
```

## Resolving MainActor Services

### Using resolveMain

Resolve `@MainActor` services using `resolveMain` (must be called from `@MainActor` context):

```swift
@MainActor
func setupUI() {
    let viewModel = ServiceEnv.current.resolveMain(UserViewModel.self)
    viewModel.loadUser()
}
```

### Using @MainService Property Wrapper

The `@MainService` property wrapper provides convenient lazy injection for `@MainActor` services. Services are resolved on first access (not at initialization time), and the result is cached:

```swift
@MainActor
class UserViewController {
    @MainService
    var viewModel: UserViewModel

    func viewDidLoad() {
        viewModel.loadUser()
    }
}
```

### Optional MainService

For MainActor services that may not be registered, use optional types:

```swift
@MainActor
class UserViewController {
    @MainService var analytics: AnalyticsViewModel?  // Returns nil if not registered

    func trackEvent(_ event: String) {
        analytics?.track(event)  // Safe optional access
    }
}
```

### Using @MainProvider Property Wrapper

The `@MainProvider` property wrapper resolves the service on **every access**, delegating caching behavior to the service's registered scope. This is the MainActor equivalent of `@Provider`:

```swift
@MainActor
class DashboardController {
    @MainProvider var viewModel: DashboardViewModel  // Resolved on each access
}
```

Use `@MainProvider` when the service is registered with a non-singleton scope and you want the scope to control the instance lifecycle:

```swift
// Register as transient - fresh instance each time
ServiceEnv.current.registerMain(DashboardViewModel.self, scope: .transient) {
    DashboardViewModel()
}
```

`@MainProvider` also supports optional types:

```swift
@MainActor
class DashboardController {
    @MainProvider var analytics: AnalyticsViewModel?  // nil if not registered
}
```

**Choosing between @MainService and @MainProvider:**

| | `@MainService` | `@MainProvider` |
|---|---|---|
| Resolution | Lazy, on first access | On every access |
| Local caching | Always caches locally | No local cache; delegates to scope |
| Best for | Singleton services | Transient or custom-scoped services |

## Complete Example: SwiftUI App

Here's a complete example of using MainActor services in a SwiftUI app:

```swift
import SwiftUI
import Service

// Define the view model
@MainActor
final class UserViewModel: ObservableObject {
    @Published var userName: String = ""
    @Published var isLoading: Bool = false
    
    private let apiClient: APIClientProtocol
    
    init(apiClient: APIClientProtocol) {
        self.apiClient = apiClient
    }
    
    func loadUser() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let user = try await apiClient.fetchUser()
            userName = user.name
        } catch {
            print("Failed to load user: \(error)")
        }
    }
}

// Register services in App initialization
@main
struct MyApp: App {
    init() {
        // Register regular services
        ServiceEnv.current.register(APIClientProtocol.self) {
            APIClient(baseURL: "https://api.example.com")
        }
        
        // Register MainActor service
        ServiceEnv.current.registerMain(UserViewModel.self) {
            let apiClient = ServiceEnv.current.resolve(APIClientProtocol.self)
            return UserViewModel(apiClient: apiClient)
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// Use the service in a view
struct ContentView: View {
    @MainService
    var viewModel: UserViewModel
    
    var body: some View {
        VStack {
            if viewModel.isLoading {
                ProgressView()
            } else {
                Text(viewModel.userName)
            }
            
            Button("Load User") {
                Task {
                    await viewModel.loadUser()
                }
            }
        }
    }
}
```

## Mixing Sendable and MainActor Services

You can mix regular `Sendable` services with `@MainActor` services:

```swift
// Register Sendable service
ServiceEnv.current.register(APIClientProtocol.self) {
    APIClient(baseURL: "https://api.example.com")
}

// Register MainActor service that depends on Sendable service
await MainActor.run {
    ServiceEnv.current.registerMain(UserViewModel.self) {
        // Resolve Sendable service from MainActor context
        let apiClient = ServiceEnv.current.resolve(APIClientProtocol.self)
        return UserViewModel(apiClient: apiClient)
    }
}
```

## Important Notes

1. **Always call `registerMain` and `resolveMain` from `@MainActor` context**: These methods are marked with `@MainActor` and must be called from the main thread.

2. **Service caching**: MainActor services are cached just like regular services. The first resolution creates the instance, and subsequent resolutions return the same instance.

3. **Thread safety**: All access to MainActor services is automatically serialized on the main thread, ensuring thread safety.

4. **In SwiftUI apps**: You're typically already on the main actor in SwiftUI's `App` initializer and views, so you can call `registerMain` and `resolveMain` directly without `await MainActor.run`.

## Modules with Default MainActor Isolation

A module built with default MainActor isolation (`.defaultIsolation(MainActor.self)` in a package manifest, or the Default Actor Isolation build setting in Xcode) treats every declaration without an explicit isolation as `@MainActor`. New Xcode app targets enable this setting.

### MainActor Services

In such a module, `registerMain`, `resolveMain`, `@MainService`, `@MainProvider`, and `ServiceAssembly` work without annotations:

```swift
protocol Store {
    var name: String { get }
}

final class MemoryStore: Store {
    var name = "memory"
}

struct Screen {
    @MainService var store: any Store
}

ServiceEnv.current.registerMain((any Store).self) { MemoryStore() }
```

### Sendable Services

A service registered with `register` must opt out of the default isolation. Declare its protocol `nonisolated` and `Sendable`. Types that conform to such a protocol are inferred nonisolated:

```swift
nonisolated protocol Logger: Sendable {
    func log(_ message: String)
}

struct ConsoleLogger: Logger {
    let prefix: String

    init(prefix: String) {
        self.prefix = prefix
    }

    func log(_ message: String) {
        print("\(prefix): \(message)")
    }
}

ServiceEnv.current.register((any Logger).self) { ConsoleLogger(prefix: "app") }
```

Mark a concrete type `nonisolated` when you register it without a protocol:

```swift
nonisolated final class Cache: Sendable {
    let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
    }
}

ServiceEnv.current.register(Cache.self) { Cache(capacity: 100) }
```

Types that conform to `ServiceKey` need no annotation, because `ServiceKey` is nonisolated and inherits `Sendable`.

A protocol declared as `protocol Logger: Sendable`, without `nonisolated`, is still `@MainActor`. `register` accepts it, but its members and the initializers of its conforming types stay on the main actor.

### Common Compiler Errors

| Code | Compiler error | Fix |
|---|---|---|
| `protocol Logger` used with `register` or `@Service` | `type 'any Logger' does not conform to the 'Sendable' protocol` | Declare `nonisolated protocol Logger: Sendable`, or use `registerMain` |
| A type with an explicit `init`, created in a `register` factory | `call to main actor-isolated initializer ... in a synchronous nonisolated context` | Mark the type `nonisolated`, or use `registerMain` |
| A method of a `Sendable` service, called off the main actor | `main actor-isolated instance method ... cannot be called from outside of the actor` | Mark the protocol or the type `nonisolated` |
| `final class ViewModel: ServiceKey` with mutable stored properties | `stored property ... of 'Sendable'-conforming class 'ViewModel' is mutable` | Use `registerMain` with a factory. `ServiceKey` is for Sendable services |

## Next Steps

- Learn about <doc:ServiceAssembly> for organizing service registrations
- Explore <doc:MigratingFromSwinject> if you're migrating from Swinject
- Read <doc:ConcurrencyModel> for a deeper understanding of Service's concurrency model
