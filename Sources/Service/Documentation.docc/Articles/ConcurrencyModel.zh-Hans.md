# 并发模型

Service 设计为与 Swift 的并发模型无缝协作，在并发上下文中提供安全高效的依赖注入。

> Localization: **[English](<doc:ConcurrencyModel>)**  |  **简体中文**

## Swift 并发基础

Swift 6 引入了严格的并发检查，要求类型明确标记为 `Sendable` 才能安全地在并发上下文之间共享。Service 尊重这些要求，同时为 `Sendable` 和 `@MainActor` 隔离的服务提供便捷的 API。

## Sendable 服务

遵循 `Sendable` 的服务可以安全地在并发上下文之间共享。这些是 Service 中的默认服务。

### 注册

```swift
// 服务必须遵循 Sendable
struct DatabaseService: Sendable {
    let connectionString: String
}

// 注册为 Sendable 服务
ServiceEnv.current.register(DatabaseService.self) {
    DatabaseService(connectionString: "sqlite://app.db")
}
```

### 解析

```swift
// 可以从任何上下文解析
let database = ServiceEnv.current.resolve(DatabaseService.self)

// 可以在异步上下文中使用
Task {
    let database = ServiceEnv.current.resolve(DatabaseService.self)
    // 使用 database...
}
```

### 属性包装器

```swift
struct UserRepository: Sendable {
    @Service
    var database: DatabaseService  // 自动解析
}
```

## MainActor 服务

`@MainActor` 隔离的服务是线程安全的（所有访问都在主线程上序列化），但**不会**自动成为 `Sendable`。Service 为这些服务提供单独的 API。

### 为什么不是 Sendable？

在 Swift 6 中，`@MainActor` 类不会自动成为 `Sendable`，因为：

1. 它们有可变状态
2. 它们隔离到特定的 actor（主 actor）
3. 跨 actor 通信需要显式的 `Sendable` 遵循

但是，它们仍然是线程安全的，因为所有访问都在主线程上序列化。

### 注册

```swift
@MainActor
final class ViewModelService {
    var data: String = ""
}

// 必须从 @MainActor 上下文注册
await MainActor.run {
    ServiceEnv.current.registerMain(ViewModelService.self) {
        ViewModelService()
    }
}
```

### 解析

```swift
// 必须从 @MainActor 上下文解析
@MainActor
func setupUI() {
    let viewModel = ServiceEnv.current.resolveMain(ViewModelService.self)
    viewModel.loadData()
}
```

### 属性包装器

```swift
@MainActor
class MyViewController {
    @MainService
    var viewModel: ViewModelService  // 自动解析
}
```

## TaskLocal 和环境上下文

Service 使用 `TaskLocal` 来跨异步边界维护环境上下文：

```swift
@TaskLocal
public static var current: ServiceEnv = .online
```

### 工作原理

1. **任务作用域**：每个异步任务维护自己的环境上下文
2. **继承**：子任务继承父任务的环境
3. **隔离**：环境切换隔离到当前任务

### 示例

```swift
// 默认环境
let service1 = ServiceEnv.current.resolve(MyService.self)  // 使用 .online

// 为此任务切换环境
await ServiceEnv.$current.withValue(.dev) {
    let service2 = ServiceEnv.current.resolve(MyService.self)  // 使用 .dev
    
    // 子任务继承环境
    Task {
        let service3 = ServiceEnv.current.resolve(MyService.self)  // 使用 .dev
    }
}

// 回到默认环境
let service4 = ServiceEnv.current.resolve(MyService.self)  // 使用 .online
```

## 线程安全

Service 通过以下方式确保线程安全：

### 内部锁定

Service 使用内部锁来保护共享状态：

```swift
class ServiceStorage {
    private let lock = Lock()
    private var providers: [String: Any] = [:]
    private var cache: [String: Any] = [:]
    
    func register<Service: Sendable>(...) {
        lock.lock()
        defer { lock.unlock() }
        // 注册服务...
    }
}
```

### Sendable 要求

所有与 `Sendable` 服务一起工作的公共 API 都需要 `Sendable` 遵循：

```swift
public func register<Service: Sendable>(
    _ type: Service.Type,
    factory: @escaping @Sendable () -> Service
)
```

### MainActor 隔离

MainActor 服务隔离到主 actor，确保线程安全：

```swift
@MainActor
public func registerMain<Service>(
    _ type: Service.Type,
    factory: @escaping @MainActor () -> Service
)
```

## 并发解析

Service 支持服务的并发解析：

```swift
// 多个并发解析
await withTaskGroup(of: MyService.self) { group in
    for _ in 0..<10 {
        group.addTask {
            ServiceEnv.current.resolve(MyService.self)
        }
    }
    
    // 所有任务解析同一个缓存的实例
    for await service in group {
        // 使用 service...
    }
}
```

## 最佳实践

### 1. 对并发服务使用 Sendable

如果你的服务需要在并发上下文之间使用，使其成为 `Sendable`：

```swift
struct DatabaseService: Sendable {
    // 不可变或线程安全的状态
    let connectionString: String
}
```

### 2. 对 UI 服务使用 MainActor

对于 UI 相关服务，使用 `@MainActor`：

```swift
@MainActor
final class ViewModelService {
    // 必须在主线程上的 UI 状态
    @Published var data: String = ""
}
```

### 3. 避免混合上下文

不要尝试从非 `@MainActor` 上下文使用 `@MainActor` 服务：

```swift
// ❌ 不要这样做
func badExample() {
    let viewModel = ServiceEnv.current.resolveMain(ViewModelService.self)  // 错误！
}

// ✅ 这样做
@MainActor
func goodExample() {
    let viewModel = ServiceEnv.current.resolveMain(ViewModelService.self)  // 正确
}
```

### 4. 使用 TaskLocal 进行环境切换

在测试中使用 `TaskLocal` 进行环境切换：

```swift
func testExample() async {
    await ServiceEnv.$current.withValue(.test) {
        // 测试代码使用测试环境
    }
}
```

## 常见模式

### 模式 1：带有 MainActor 依赖的 Sendable 服务

```swift
// Sendable 服务
struct APIClient: Sendable {
    func fetchData() async -> Data { /* ... */ }
}

// 使用 Sendable 服务的 MainActor 服务
@MainActor
final class ViewModel {
    let api: APIClient
    
    init(api: APIClient) {
        self.api = api
    }
    
    func loadData() async {
        let data = await api.fetchData()  // 正确 - 异步调用
        // 更新 UI 状态...
    }
}

// 注册
ServiceEnv.current.register(APIClient.self) {
    APIClient()
}

await MainActor.run {
    ServiceEnv.current.registerMain(ViewModel.self) {
        let api = ServiceEnv.current.resolve(APIClient.self)
        return ViewModel(api: api)
    }
}
```

### 模式 2：多个环境

```swift
// 在不同环境中注册
ServiceEnv.online.register(APIClient.self) {
    APIClient(baseURL: "https://api.example.com")
}

ServiceEnv.dev.register(APIClient.self) {
    APIClient(baseURL: "https://dev-api.example.com")
}

// 在代码中使用
await ServiceEnv.$current.withValue(.dev) {
    let client = ServiceEnv.current.resolve(APIClient.self)  // 使用 dev
}
```

## 性能考虑

### 缓存

Service 缓存解析的实例，这对于并发访问是安全的：

- **线程安全缓存**：受内部锁保护
- **单例行为**：并发解析返回同一个实例
- **内存权衡**：缓存的实例消耗内存

### 锁争用

Service 使用粗粒度锁定，这很简单但可能导致争用：

- **低争用**：典型用例的争用最小
- **简单设计**：更容易推理和维护
- **未来优化**：如果需要，可以用细粒度锁定进行优化

## 下一步

- 阅读 <doc:MainActorServices.zh-Hans> 了解更多关于 MainActor 服务的详细信息
- 探索 <doc:UnderstandingService.zh-Hans> 了解架构详细信息
- 查看 <doc:RealWorldExamples.zh-Hans> 获取实用模式
