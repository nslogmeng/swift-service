# 并发模型

学习如何在并发和异步上下文中安全使用 Service。

> Localization: **[English](https://nslogmeng.github.io/swift-service/documentation/service/concurrencymodel)**  |  **简体中文**

## 前置知识

本指南假设你熟悉以下概念：
- Swift 的 `Sendable` 协议和数据竞争安全
- `@MainActor` 属性和 actor 隔离
- Swift 的结构化并发（`async`/`await`、`Task`）

有关这些概念的背景知识，请参阅 [Swift 并发](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/)。

## 概述

Service 根据线程安全要求提供两套不同的依赖注入 API，每套有两种属性包装器风格：

| 服务类型 | 注册 | 解析 | 懒加载 + 缓存 | 作用域驱动 |
|---------|------|------|--------------|-----------|
| Sendable | `register()` | `resolve()` | `@Service` | `@Provider` |
| MainActor | `registerMain()` | `resolveMain()` | `@MainService` | `@MainProvider` |

- **`@Service` / `@MainService`**：首次访问时解析一次，在内部缓存。适合稳定的依赖。
- **`@Provider` / `@MainProvider`**：每次访问都解析；缓存行为遵循注册的作用域。适合 transient 或 custom 作用域的服务。

## Sendable 服务

遵循 `Sendable` 的服务可以安全地在并发上下文之间共享。

### 注册和解析

```swift
// 定义一个 Sendable 服务
struct DatabaseService: Sendable {
    let connectionString: String
}

// 注册
ServiceEnv.current.register(DatabaseService.self) {
    DatabaseService(connectionString: "sqlite://app.db")
}

// 从任何上下文解析
let database = try ServiceEnv.current.resolve(DatabaseService.self)

// 在异步上下文中使用
Task {
    let db = try ServiceEnv.current.resolve(DatabaseService.self)
    // 使用 db...
}
```

### 属性包装器

```swift
struct UserRepository: Sendable {
    @Service var database: DatabaseService
}
```

## MainActor 服务

隔离到 `@MainActor` 的服务是线程安全的，但不是 `Sendable`。需要使用单独的 API。

### 注册和解析

```swift
@MainActor
final class ViewModelService {
    var data: String = ""
}

// 必须从 @MainActor 上下文注册
@MainActor
func setupServices() {
    ServiceEnv.current.registerMain(ViewModelService.self) {
        ViewModelService()
    }
}

// 必须从 @MainActor 上下文解析
@MainActor
func setupUI() {
    let viewModel = try ServiceEnv.current.resolveMain(ViewModelService.self)
}
```

### 属性包装器

```swift
@MainActor
class MyViewController {
    @MainService var viewModel: ViewModelService
}
```

> Important: 永远不要从非 `@MainActor` 上下文调用 `resolveMain()`。在严格并发模式下，编译器会阻止这种情况。

## 使用 TaskLocal 管理环境上下文

Service 使用 `TaskLocal` 来跨异步边界维护环境上下文。

```swift
// 默认：使用 .online 环境
let service1 = try ServiceEnv.current.resolve(MyService.self)

// 为此任务切换环境
await ServiceEnv.$current.withValue(.dev) {
    let service2 = try ServiceEnv.current.resolve(MyService.self)  // 使用 .dev

    // 子任务继承环境
    Task {
        let service3 = try ServiceEnv.current.resolve(MyService.self)  // 也使用 .dev
    }
}

// 回到 .online
let service4 = try ServiceEnv.current.resolve(MyService.self)
```

## 并发解析

Service 安全地处理多个并发解析。行为取决于注册的作用域：

```swift
// Singleton：所有任务解析同一个缓存实例
await withTaskGroup(of: MyService.self) { group in
    for _ in 0..<10 {
        group.addTask {
            try ServiceEnv.current.resolve(MyService.self)
        }
    }

    for await service in group {
        // 全部返回同一实例 (singleton)
    }
}

// Transient：每个任务获取新实例
env.register(Worker.self, scope: .transient) { Worker() }
await withTaskGroup(of: Worker.self) { group in
    for _ in 0..<10 {
        group.addTask {
            try ServiceEnv.current.resolve(Worker.self)
        }
    }

    for await worker in group {
        // 每个都是不同的实例
    }
}
```

## 作用域与并发

服务作用域与并发交互的重要方式：

### Singleton 和 Custom 作用域

对于 singleton 和 custom 作用域的服务，每个缓存实例的工厂函数至多执行一次。多个线程同时首次解析同一个服务时，只有一个线程执行工厂函数。其他线程等待它完成，并拿到同一个实例。解析其他服务不会被阻塞。

```swift
env.register(DatabaseService.self, scope: .singleton) { DatabaseService() }

// 安全：工厂函数只执行一次，并发解析返回同一实例
await withTaskGroup(of: DatabaseService.self) { group in
    for _ in 0..<10 {
        group.addTask {
            try ServiceEnv.current.resolve(DatabaseService.self)
        }
    }
}
```

这一语义与 `swift_once` 以及全局变量的惰性初始化一致：

- **工厂函数失败后会重试。** 工厂函数抛出错误时不缓存任何内容。下一次解析会重新执行工厂函数。
- **重置不等待执行中的工厂函数。** 工厂函数执行期间调用 `resetCaches()`、`resetScope(_:)` 或 `resetAll()` 时，这次解析以及已经在等待它的解析，仍然返回它创建的实例。该实例不进入缓存，之后的解析会创建新实例。

它也有相同的限制：

- **工厂函数不能阻塞等待另一个会解析同一服务的线程。** 那个线程在等待工厂函数完成，两个线程都无法继续。例如，如果主线程也会解析某个服务，这个服务的工厂函数就不能调用 `DispatchQueue.main.sync`。
- **工厂函数不能在自己的线程上运行另一个会解析同一服务的任务。** 循环检测跟随单个任务。它不覆盖在工厂函数返回前运行在同一线程上的其他任务，例如工厂函数内的嵌套 run loop 执行的 MainActor 任务。这样的解析会在同一线程上重入创建过程，进程会崩溃。
- **两个线程从不同的服务进入同一个依赖循环时，可能死锁。** 在单个线程上解析依赖循环，始终抛出 ``ServiceError/circularDependency(serviceType:chain:)``。如果两个线程同时首次解析同一个依赖循环，并且各自从循环中不同的服务开始，每个线程可能各持有一个服务并等待对方。参见 <doc:CircularDependencies>。

### Graph 作用域

Graph 作用域使用 `@TaskLocal` 存储在单个解析链内共享实例。每次顶层 `resolve()` 调用创建一个新的 graph 上下文：

```swift
env.register(UnitOfWork.self, scope: .graph) { UnitOfWork() }

// resolve(ServiceA) 开始一个新 graph
//   ├── resolve(UnitOfWork)  ← 创建实例 X
//   └── resolve(ServiceB)
//         └── resolve(UnitOfWork)  ← 复用实例 X（同一 graph）
//
// 再次 resolve(ServiceA) 开始另一个 graph
//   └── resolve(UnitOfWork)  ← 创建实例 Y（新 graph）
```

由于 graph 缓存是 task-local 的，不同任务上的并发顶层解析自然获得独立的 graph 缓存，无需额外的同步开销。

### @Provider 与 Transient 作用域

使用 `@Provider` 配合 `.transient` 作用域时，每次访问都创建新实例。在并发代码中，这意味着每个访问点获得自己的实例：

```swift
env.register(RequestHandler.self, scope: .transient) { RequestHandler() }

struct Controller {
    @Provider var handler: RequestHandler  // 每次访问获取新实例
}
```

## 最佳实践

### 对共享服务使用 Sendable

```swift
struct DatabaseService: Sendable {
    let connectionString: String  // 不可变状态自动是 Sendable
}
```

### 对 UI 服务使用 MainActor

```swift
@MainActor
final class ViewModelService {
    @Published var data: String = ""  // 主线程上的 UI 状态
}
```

### 避免上下文混用

```swift
// ❌ 不要这样做
func badExample() {
    let viewModel = try ServiceEnv.current.resolveMain(ViewModelService.self)  // 编译错误！
}

// ✅ 这样做
@MainActor
func goodExample() {
    let viewModel = try ServiceEnv.current.resolveMain(ViewModelService.self)  // 正确
}
```

### 使用 TaskLocal 进行测试隔离

```swift
@Test func testServiceBehavior() async throws {
    await ServiceEnv.$current.withValue(.test) {
        // 测试代码使用隔离的测试环境
    }
}
```

## 常见模式

### MainActor 服务使用 Sendable 服务

```swift
// Sendable 服务
struct APIClient: Sendable {
    func fetchData() async -> Data { /* ... */ }
}

// 使用 Sendable 依赖的 MainActor 服务
@MainActor
final class ViewModel {
    let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func loadData() async {
        let data = await api.fetchData()
        // 更新 UI 状态...
    }
}

// 注册
ServiceEnv.current.register(APIClient.self) { APIClient() }

await MainActor.run {
    ServiceEnv.current.registerMain(ViewModel.self) {
        let api = try ServiceEnv.current.resolve(APIClient.self)
        return ViewModel(api: api)
    }
}
```

## 线程安全保证

Service 提供以下线程安全保证：

- **注册**：通过内部锁实现线程安全
- **解析**：通过内部锁实现线程安全
- **Singleton 和 custom 作用域的创建**：每个缓存实例的工厂函数至多执行一次；同一服务的并发解析方会等待
- **环境切换**：通过 `TaskLocal` 存储实现线程安全
- **缓存管理**：通过内部锁实现线程安全

有关实现细节，请参阅 <doc:UnderstandingService>。

## 另请参阅

- <doc:MainActorServices>
- <doc:UnderstandingService>
- <doc:MigratingFromSwinject>
