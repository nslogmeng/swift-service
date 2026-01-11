# MainActor Services

Service provides specialized APIs for working with `@MainActor`-isolated services, such as view models and UI controllers.

> Localization: **English**  |  **[简体中文](<doc:MainActorServices.zh-Hans>)**

## Background: Why MainActor Services?

In Swift 6's strict concurrency model, `@MainActor` classes are thread-safe (all access is serialized on the main thread) but are **not** automatically `Sendable`. This means they cannot be used with the standard `register`/`resolve` APIs which require `Sendable` conformance.

### The Problem

Consider a typical view model:

```swift
@MainActor
final class UserViewModel {
    var userName: String = ""
    var isLoading: Bool = false
    
    func loadUser() {
        isLoading = true
        // ... load user data
        isLoading = false
    }
}
```

This view model is `@MainActor`-isolated, meaning all access must happen on the main thread. However, it doesn't conform to `Sendable` because:

1. It has mutable state (`userName`, `isLoading`)
2. `@MainActor` classes are not automatically `Sendable` in Swift 6
3. The standard `register`/`resolve` APIs require `Sendable` conformance

### The Solution

Service provides dedicated `registerMain` and `resolveMain` methods (along with the `@MainService` property wrapper) that work with `@MainActor`-isolated services without requiring `Sendable` conformance.

## Registering MainActor Services

### Using registerMain

Register `@MainActor` services using `registerMain`:

```swift
@MainActor
final class UserViewModel {
    var userName: String = ""
    func loadUser() { /* ... */ }
}

// Register on main actor context
await MainActor.run {
    ServiceEnv.current.registerMain(UserViewModel.self) {
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

### Using ServiceKey

For services with default implementations:

```swift
@MainActor
final class UserViewModel: ServiceKey {
    var userName: String = ""
    
    static var `default`: UserViewModel {
        UserViewModel()
    }
}

await MainActor.run {
    ServiceEnv.current.registerMain(UserViewModel.self)
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

The `@MainService` property wrapper provides convenient injection for `@MainActor` services:

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

## Next Steps

- Learn about <doc:ServiceAssembly> for organizing service registrations
- Explore <doc:RealWorldExamples> for more practical examples
- Read <doc:ConcurrencyModel> for a deeper understanding of Service's concurrency model
