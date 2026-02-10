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

Singleton 和 custom 作用域的服务使用双重检查锁定，确保在并发解析下也只创建一个实例：

```swift
env.register(DatabaseService.self, scope: .singleton) { DatabaseService() }

// 安全：并发解析返回同一实例
await withTaskGroup(of: DatabaseService.self) { group in
    for _ in 0..<10 {
        group.addTask {
            try ServiceEnv.current.resolve(DatabaseService.self)
        }
    }
}
```

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
- **环境切换**：通过 `TaskLocal` 存储实现线程安全
- **缓存管理**：通过内部锁实现线程安全

有关实现细节，请参阅 <doc:UnderstandingService>。

## 另请参阅

- <doc:MainActorServices>
- <doc:UnderstandingService>
- <doc:RealWorldExamples>
