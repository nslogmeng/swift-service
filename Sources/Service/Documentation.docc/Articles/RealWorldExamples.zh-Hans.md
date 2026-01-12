# 实际示例

在实际应用中使用 Service 的实用示例，从简单到复杂的场景。

> Localization: **[English](https://nslogmeng.github.io/swift-service/documentation/service/realworldexamples)**  |  **简体中文**

## 示例 1：带有网络和数据库的简单 iOS 应用

一个典型的带有网络请求和本地存储的 iOS 应用。

### 服务定义

```swift
// 协议
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

// 实现
class APIClient: APIClientProtocol {
    let baseURL: String
    
    init(baseURL: String) {
        self.baseURL = baseURL
    }
    
    func fetchUsers() async throws -> [User] {
        // 网络请求...
    }
    
    func createUser(_ user: User) async throws -> User {
        // 网络请求...
    }
}

class Database: DatabaseProtocol {
    let connectionString: String
    
    init(connectionString: String) {
        self.connectionString = connectionString
    }
    
    func saveUsers(_ users: [User]) throws {
        // 保存到数据库...
    }
    
    func loadUsers() throws -> [User] {
        // 从数据库加载...
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
        // 先尝试数据库，回退到 API
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

### 服务注册

```swift
// 在你的 App 初始化中
@main
struct MyApp: App {
    init() {
        // 注册基础服务
        ServiceEnv.current.register(APIClientProtocol.self) {
            APIClient(baseURL: "https://api.example.com")
        }
        
        ServiceEnv.current.register(DatabaseProtocol.self) {
            Database(connectionString: "sqlite://app.db")
        }
        
        // 注册依赖其他服务的仓库
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

### 在视图中使用服务

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

## 示例 2：使用视图模型的 SwiftUI 应用

一个使用视图模型的 SwiftUI 应用，使用 MainActor 服务。

### 视图模型

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
            await loadUsers()  // 刷新列表
        } catch {
            errorMessage = "Failed to add user: \(error.localizedDescription)"
        }
    }
}
```

### 服务注册

```swift
@main
struct MyApp: App {
    init() {
        // 注册 Sendable 服务
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
        
        // 注册 MainActor 服务
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

### 在视图中使用视图模型

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

## 示例 3：使用 Service Assembly

使用装配组织服务以获得更好的结构。

### 装配

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

### 应用初始化

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

## 示例 4：使用不同环境进行测试

使用环境进行测试，使用模拟服务。

### 模拟服务

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

### 测试设置

```swift
func testUserRepository() async throws {
    await ServiceEnv.$current.withValue(.test) {
        // 在测试环境中注册模拟服务
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
        
        // 测试你的代码
        let repository = ServiceEnv.current.resolve(UserRepositoryProtocol.self)
        let users = try await repository.getUsers()
        XCTAssertEqual(users.count, 0)
    }
}
```

## 示例 5：复杂的依赖图

一个更复杂的示例，包含多个相互依赖的服务。

```swift
// 服务
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

// 带依赖的实现
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
        // 实现...
        return nil
    }
    
    func set<T>(_ value: T, forKey key: String) {
        logger.log("Cache set: \(key)")
        // 实现...
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
        // 先检查缓存...
        // 实现...
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
        // 实现...
    }
}

// 注册顺序很重要 - 先注册依赖
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

## 示例中的最佳实践

1. **定义协议**：为服务使用协议，以便轻松测试和交换实现。

2. **按依赖顺序注册**：先注册其他服务依赖的服务。

3. **使用装配进行组织**：将相关服务分组以获得更好的可维护性。

4. **利用环境进行测试**：使用不同环境来交换实现以进行测试。

5. **保持服务专注**：每个服务应该有一个单一、明确定义的职责。

## 下一步

- 学习 <doc:ServiceAssembly.zh-Hans> 了解如何组织复杂的服务图
- 探索 <doc:ServiceEnvironments.zh-Hans> 了解基于环境的配置
- 阅读 <doc:UnderstandingService.zh-Hans> 深入了解 Service 的架构
