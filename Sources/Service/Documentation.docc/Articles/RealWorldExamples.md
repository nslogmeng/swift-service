# Real-World Examples

Practical examples of using Service in real applications, from simple to complex scenarios.

> Localization: **English**  |  **[简体中文](https://nslogmeng.github.io/swift-service/zh-Hans/documentation/service/realworldexamples)**

## Example 1: Simple iOS App with Network and Database

A typical iOS app with network requests and local storage.

### Service Definitions

```swift
// Protocols
protocol APIClientProtocol {
    func fetchUsers() async throws -> [User]
    func createUser(_ user: User) async throws -> User
}

protocol DatabaseProtocol {
    func saveUsers(_ users: [User]) throws
    func loadUsers() throws -> [User]
}

protocol UserRepositoryProtocol {
    func getUsers() async throws -> [User]
    func addUser(_ user: User) async throws
}

// Implementations
class APIClient: APIClientProtocol {
    let baseURL: String
    
    init(baseURL: String) {
        self.baseURL = baseURL
    }
    
    func fetchUsers() async throws -> [User] {
        // Network request...
    }
    
    func createUser(_ user: User) async throws -> User {
        // Network request...
    }
}

class Database: DatabaseProtocol {
    let connectionString: String
    
    init(connectionString: String) {
        self.connectionString = connectionString
    }
    
    func saveUsers(_ users: [User]) throws {
        // Save to database...
    }
    
    func loadUsers() throws -> [User] {
        // Load from database...
    }
}

class UserRepository: UserRepositoryProtocol {
    let api: APIClientProtocol
    let database: DatabaseProtocol
    
    init(api: APIClientProtocol, database: DatabaseProtocol) {
        self.api = api
        self.database = database
    }
    
    func getUsers() async throws -> [User] {
        // Try database first, fallback to API
        if let users = try? database.loadUsers(), !users.isEmpty {
            return users
        }
        let users = try await api.fetchUsers()
        try database.saveUsers(users)
        return users
    }
    
    func addUser(_ user: User) async throws {
        let created = try await api.createUser(user)
        try database.saveUsers([created])
    }
}
```

### Service Registration

```swift
// In your App initialization
@main
struct MyApp: App {
    init() {
        // Register base services
        ServiceEnv.current.register(APIClientProtocol.self) {
            APIClient(baseURL: "https://api.example.com")
        }
        
        ServiceEnv.current.register(DatabaseProtocol.self) {
            Database(connectionString: "sqlite://app.db")
        }
        
        // Register repository that depends on other services
        ServiceEnv.current.register(UserRepositoryProtocol.self) {
            let api = ServiceEnv.current.resolve(APIClientProtocol.self)
            let database = ServiceEnv.current.resolve(DatabaseProtocol.self)
            return UserRepository(api: api, database: database)
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### Using Services in Views

```swift
struct UserListView: View {
    @Service
    var repository: UserRepositoryProtocol
    
    @State private var users: [User] = []
    @State private var isLoading = false
    
    var body: some View {
        List(users) { user in
            Text(user.name)
        }
        .task {
            await loadUsers()
        }
    }
    
    private func loadUsers() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            users = try await repository.getUsers()
        } catch {
            print("Failed to load users: \(error)")
        }
    }
}
```

## Example 2: SwiftUI App with View Models

A SwiftUI app using view models with MainActor services.

### View Model

```swift
@MainActor
final class UserListViewModel: ObservableObject {
    @Published var users: [User] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let repository: UserRepositoryProtocol
    
    init(repository: UserRepositoryProtocol) {
        self.repository = repository
    }
    
    func loadUsers() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            users = try await repository.getUsers()
        } catch {
            errorMessage = "Failed to load users: \(error.localizedDescription)"
        }
    }
    
    func addUser(_ user: User) async {
        do {
            try await repository.addUser(user)
            await loadUsers()  // Refresh list
        } catch {
            errorMessage = "Failed to add user: \(error.localizedDescription)"
        }
    }
}
```

### Service Registration

```swift
@main
struct MyApp: App {
    init() {
        // Register Sendable services
        ServiceEnv.current.register(APIClientProtocol.self) {
            APIClient(baseURL: "https://api.example.com")
        }
        
        ServiceEnv.current.register(DatabaseProtocol.self) {
            Database(connectionString: "sqlite://app.db")
        }
        
        ServiceEnv.current.register(UserRepositoryProtocol.self) {
            let api = ServiceEnv.current.resolve(APIClientProtocol.self)
            let database = ServiceEnv.current.resolve(DatabaseProtocol.self)
            return UserRepository(api: api, database: database)
        }
        
        // Register MainActor service
        ServiceEnv.current.registerMain(UserListViewModel.self) {
            let repository = ServiceEnv.current.resolve(UserRepositoryProtocol.self)
            return UserListViewModel(repository: repository)
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### Using View Model in View

```swift
struct UserListView: View {
    @MainService
    var viewModel: UserListViewModel
    
    var body: some View {
        NavigationView {
            List(viewModel.users) { user in
                Text(user.name)
            }
            .navigationTitle("Users")
            .toolbar {
                Button("Refresh") {
                    Task {
                        await viewModel.loadUsers()
                    }
                }
            }
            .task {
                await viewModel.loadUsers()
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
        }
    }
}
```

## Example 3: Using Service Assembly

Organizing services using assemblies for better structure.

### Assemblies

```swift
struct NetworkAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.register(APIClientProtocol.self) {
            let baseURL = ProcessInfo.processInfo.environment["API_BASE_URL"] 
                ?? "https://api.example.com"
            return APIClient(baseURL: baseURL)
        }
    }
}

struct DatabaseAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.register(DatabaseProtocol.self) {
            Database(connectionString: "sqlite://app.db")
        }
    }
}

struct RepositoryAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.register(UserRepositoryProtocol.self) {
            let api = env.resolve(APIClientProtocol.self)
            let database = env.resolve(DatabaseProtocol.self)
            return UserRepository(api: api, database: database)
        }
    }
}

struct ViewModelAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.registerMain(UserListViewModel.self) {
            let repository = env.resolve(UserRepositoryProtocol.self)
            return UserListViewModel(repository: repository)
        }
    }
}
```

### App Initialization

```swift
@main
struct MyApp: App {
    init() {
        ServiceEnv.current.assemble(
            NetworkAssembly(),
            DatabaseAssembly(),
            RepositoryAssembly(),
            ViewModelAssembly()
        )
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

## Example 4: Large-Scale App with Environment Switching

A real-world example showing how to maintain Assembly structure while switching environments in large projects.

### App Assembly Structure

```swift
struct AppAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.registerMain(AppContainer.self) { AppContainer() }

        env.register(Localization.self) { Localization() }
        env.register(ThemeManager.self) { ThemeManager() }

        env.registerMain(Router.self) { Router() }
        env.registerMain(Overlay.self) { Overlay() }
    }
}
```

### Production App Initialization

```swift
@main
struct MyApp: App {
    init() {
        ServiceEnv.current.assemble([
            AppAssembly()
            // ... other assemblies
        ])
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### Test Environment Setup

In tests, you can switch to the `.test` environment while keeping the exact same Assembly structure:

```swift
func testAppFlow() async throws {
    await ServiceEnv.$current.withValue(.test) {
        // Same assembly structure as production
        ServiceEnv.current.assemble([
            AppAssembly()
            // ... other assemblies
        ])

        // Run your test logic
        let container = ServiceEnv.current.resolveMain(AppContainer.self)
        // ... test assertions
    }
}
```

### Conditional Registration in Assembly

If you need environment-specific implementations, you can conditionally register services within the Assembly while maintaining structure:

```swift
struct AppAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.registerMain(AppContainer.self) { AppContainer() }

        // Conditionally register based on environment
        if env == .test {
            env.register(Localization.self) { MockLocalization() }
        } else {
            env.register(Localization.self) { Localization() }
        }
        
        // Keep the rest identical
        env.register(ThemeManager.self) { ThemeManager() }
        env.registerMain(Router.self) { Router() }
        env.registerMain(Overlay.self) { Overlay() }
    }
}
```

This approach provides:
- **Structure consistency**: Same Assembly structure across all environments
- **Flexibility**: Easy switching between environments at the outermost scope
- **Maintainability**: Changes to service registration are centralized in Assemblies
- **Testability**: Tests use the same structure as production, ensuring realistic scenarios

## Example 5: Testing with Different Environments

Using environments for testing with mock services.

### Mock Services

```swift
class MockAPIClient: APIClientProtocol {
    var users: [User] = []
    var shouldFail = false
    
    func fetchUsers() async throws -> [User] {
        if shouldFail {
            throw NSError(domain: "Test", code: 1)
        }
        return users
    }
    
    func createUser(_ user: User) async throws -> User {
        if shouldFail {
            throw NSError(domain: "Test", code: 1)
        }
        users.append(user)
        return user
    }
}

class MockDatabase: DatabaseProtocol {
    var users: [User] = []
    
    func saveUsers(_ users: [User]) throws {
        self.users = users
    }
    
    func loadUsers() throws -> [User] {
        return users
    }
}
```

### Test Setup

```swift
func testUserRepository() async throws {
    await ServiceEnv.$current.withValue(.test) {
        // Register mock services in test environment
        ServiceEnv.current.register(APIClientProtocol.self) {
            MockAPIClient()
        }
        
        ServiceEnv.current.register(DatabaseProtocol.self) {
            MockDatabase()
        }
        
        ServiceEnv.current.register(UserRepositoryProtocol.self) {
            let api = ServiceEnv.current.resolve(APIClientProtocol.self)
            let database = ServiceEnv.current.resolve(DatabaseProtocol.self)
            return UserRepository(api: api, database: database)
        }
        
        // Test your code
        let repository = ServiceEnv.current.resolve(UserRepositoryProtocol.self)
        let users = try await repository.getUsers()
        XCTAssertEqual(users.count, 0)
    }
}
```

## Example 6: Complex Dependency Graph

A more complex example with multiple interdependent services.

```swift
// Services
protocol LoggerProtocol {
    func log(_ message: String)
}

protocol CacheProtocol {
    func get<T>(_ key: String) -> T?
    func set<T>(_ value: T, forKey key: String)
}

protocol NetworkProtocol {
    func request<T>(_ endpoint: String) async throws -> T
}

protocol AnalyticsProtocol {
    func track(_ event: String)
}

// Implementations with dependencies
class Logger: LoggerProtocol {
    func log(_ message: String) {
        print("[\(Date())] \(message)")
    }
}

class Cache: CacheProtocol {
    let logger: LoggerProtocol
    
    init(logger: LoggerProtocol) {
        self.logger = logger
    }
    
    func get<T>(_ key: String) -> T? {
        logger.log("Cache get: \(key)")
        // Implementation...
        return nil
    }
    
    func set<T>(_ value: T, forKey key: String) {
        logger.log("Cache set: \(key)")
        // Implementation...
    }
}

class Network: NetworkProtocol {
    let logger: LoggerProtocol
    let cache: CacheProtocol
    
    init(logger: LoggerProtocol, cache: CacheProtocol) {
        self.logger = logger
        self.cache = cache
    }
    
    func request<T>(_ endpoint: String) async throws -> T {
        logger.log("Network request: \(endpoint)")
        // Check cache first...
        // Implementation...
        fatalError("Not implemented")
    }
}

class Analytics: AnalyticsProtocol {
    let logger: LoggerProtocol
    
    init(logger: LoggerProtocol) {
        self.logger = logger
    }
    
    func track(_ event: String) {
        logger.log("Analytics track: \(event)")
        // Implementation...
    }
}

// Registration order matters - register dependencies first
ServiceEnv.current.register(LoggerProtocol.self) {
    Logger()
}

ServiceEnv.current.register(CacheProtocol.self) {
    let logger = ServiceEnv.current.resolve(LoggerProtocol.self)
    return Cache(logger: logger)
}

ServiceEnv.current.register(NetworkProtocol.self) {
    let logger = ServiceEnv.current.resolve(LoggerProtocol.self)
    let cache = ServiceEnv.current.resolve(CacheProtocol.self)
    return Network(logger: logger, cache: cache)
}

ServiceEnv.current.register(AnalyticsProtocol.self) {
    let logger = ServiceEnv.current.resolve(LoggerProtocol.self)
    return Analytics(logger: logger)
}
```

## Best Practices from Examples

1. **Define protocols**: Use protocols for services to enable easy testing and swapping implementations.

2. **Register in dependency order**: Register services that others depend on first.

3. **Use assemblies for organization**: Group related services together for better maintainability.

4. **Leverage environments for testing**: Use different environments to swap implementations for testing.

5. **Maintain Assembly structure**: Keep the same Assembly structure across environments, switching only at the outermost scope for maximum flexibility and maintainability.

5. **Keep services focused**: Each service should have a single, well-defined responsibility.

## Next Steps

- Learn about <doc:ServiceAssembly> for organizing complex service graphs
- Explore <doc:ServiceEnvironments> for environment-based configurations
- Read <doc:UnderstandingService> for a deeper understanding of Service's architecture
