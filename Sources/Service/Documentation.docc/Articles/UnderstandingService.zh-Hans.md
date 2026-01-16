# 理解 Service

深入了解 Service 的架构、设计决策及其工作原理。

> Localization: **[English](https://nslogmeng.github.io/swift-service/documentation/service/understandingservice)**  |  **简体中文**

## 核心概念

### 服务环境

Service 使用"服务环境"的概念来管理服务注册和解析。每个环境维护自己的隔离注册表，允许你在不同上下文（生产、开发、测试）中拥有不同的服务配置。

```swift
public struct ServiceEnv: Sendable {
    @TaskLocal
    public static var current: ServiceEnv = .online
    
    public let name: String
    let storage = ServiceStorage()
}
```

### TaskLocal 存储

Service 使用 Swift 的 `TaskLocal` 属性包装器来跨异步边界维护环境上下文。这确保了：

1. 每个异步任务维护自己的环境上下文
2. 环境切换作用域为当前任务
3. 跨并发上下文的线程安全访问

```swift
// 为此任务切换环境
await ServiceEnv.$current.withValue(.dev) {
    // 此块中的所有服务解析都使用 .dev 环境
    let service = ServiceEnv.current.resolve(MyService.self)
}
```

### 服务存储

每个环境都有自己的 `ServiceStorage` 实例，管理：

- **服务提供者**：创建服务实例的工厂函数
- **服务缓存**：用于单例行为的缓存实例
- **解析跟踪**：跟踪当前解析链以进行循环检测

## 服务解析流程

当你解析服务时，会发生以下情况：

1. **检查缓存**：如果服务之前已解析并缓存，返回缓存的实例
2. **获取提供者**：查找此服务类型的工厂函数
3. **跟踪解析**：将此服务添加到解析链（用于循环检测）
4. **创建实例**：调用工厂函数创建服务
5. **缓存实例**：将实例存储在缓存中以供后续解析
6. **返回实例**：返回新创建的（或缓存的）实例

### 解析跟踪

Service 跟踪解析链以检测循环依赖：

```swift
// 当解析 AService 时：
// 1. 将 AService 添加到链：[AService]
// 2. 工厂函数解析 BService
// 3. 将 BService 添加到链：[AService, BService]
// 4. 工厂函数解析 CService
// 5. 将 CService 添加到链：[AService, BService, CService]
// 6. 工厂函数尝试解析 AService
// 7. AService 已在链中 - 检测到循环！
```

## 并发模型

Service 设计为线程安全，并与 Swift 的并发模型无缝协作。

### Sendable 服务

常规服务必须遵循 `Sendable`，确保它们可以安全地在并发上下文之间共享：

```swift
extension ServiceEnv {
    public func register<Service: Sendable>(
        _ type: Service.Type,
        factory: @escaping @Sendable () -> Service
    ) {
        storage.register(type, factory: factory)
    }
}
```

### MainActor 服务

对于 `@MainActor` 隔离的服务（如视图模型），Service 提供不要求 `Sendable` 的单独 API：

```swift
@MainActor
extension ServiceEnv {
    public func registerMain<Service>(
        _ type: Service.Type,
        factory: @escaping @MainActor () -> Service
    ) {
        storage.registerMain(type, factory: factory)
    }
}
```

### 线程安全

- **服务注册**：通过内部锁实现线程安全
- **服务解析**：通过内部锁实现线程安全
- **环境切换**：通过 `TaskLocal` 存储实现线程安全
- **缓存管理**：通过内部锁定实现线程安全

## 服务生命周期

### 单例行为

默认情况下，服务作为单例缓存：

```swift
// 首次解析创建并缓存实例
let service1 = ServiceEnv.current.resolve(MyService.self)

// 后续解析返回缓存的实例
let service2 = ServiceEnv.current.resolve(MyService.self)
// service1 === service2（同一实例）
```

### 缓存管理

你可以清除缓存以强制重新创建服务：

```swift
// 清除缓存 - 服务将在下次解析时重新创建
await ServiceEnv.current.resetCaches()

// 现在这会创建一个新实例
let service3 = ServiceEnv.current.resolve(MyService.self)
// service1 !== service3（不同实例）
```

### 完全重置

你也可以重置所有内容，包括注册：

```swift
// 重置所有内容 - 缓存和注册
await ServiceEnv.current.resetAll()

// 服务必须重新注册才能解析
ServiceEnv.current.register(MyService.self) {
    MyService()
}
```

## 属性包装器

Service 提供属性包装器以方便依赖注入：

### @Service

`@Service` 属性包装器在属性初始化时立即解析服务：

```swift
@propertyWrapper
public struct Service<S: Sendable>: Sendable {
    public let wrappedValue: S
    
    public init() {
        self.wrappedValue = ServiceEnv.current.resolve(S.self)
    }
}
```

### @MainService

`@MainService` 属性包装器类似，但用于 `@MainActor` 服务：

```swift
@MainActor
@propertyWrapper
public struct MainService<S> {
    public let wrappedValue: S
    
    public init() {
        self.wrappedValue = ServiceEnv.current.resolveMain(S.self)
    }
}
```

## 设计决策

### 为什么使用 TaskLocal？

`TaskLocal` 为环境作用域提供了完美的机制：

- **异步安全**：跨异步边界无缝工作
- **任务作用域**：环境切换自动作用域为当前任务
- **线程安全**：无需额外的同步

### 为什么需要单独的 MainActor API？

Swift 6 的严格并发模型要求跨 actor 通信需要 `Sendable`。但是，`@MainActor` 类是线程安全的，但不会自动成为 `Sendable`。单独的 API 允许 Service 与两者一起工作：

- **Sendable 服务**：使用标准的 `register`/`resolve` API
- **MainActor 服务**：使用 `registerMain`/`resolveMain` API

### 为什么 `ServiceAssembly` 使用 @MainActor？

`ServiceAssembly` 被标记为 `@MainActor`，因为：

1. Service Assembly 通常发生在应用初始化期间（已经在主 actor 上）
2. 确保线程安全、顺序执行注册
3. 提供可预测的执行上下文

### 为什么使用致命错误？

Service 在服务未注册时使用 `fatalError`，因为：

1. **快速失败**：尽早捕获配置错误
2. **类型安全**：编译时检查并不总是可能的
3. **清晰的错误**：提供描述性错误消息

## 性能考虑

### 缓存

Service 缓存解析的实例以避免重复创建：

- **内存**：缓存的实例消耗内存
- **性能**：后续解析是 O(1) 查找
- **权衡**：内存和性能之间的平衡

### 解析跟踪

循环检测增加了解析的开销：

- **内存**：解析链跟踪
- **性能**：循环检测的开销最小
- **好处**：防止无限循环和栈溢出

### 锁定

Service 使用内部锁来实现线程安全：

- **粗粒度**：简单的锁定策略
- **性能**：在典型用例中争用最小
- **权衡**：简单性优于细粒度锁定

## 扩展点

Service 设计为可扩展：

### 自定义环境

为特定用例创建自定义环境：

```swift
let stagingEnv = ServiceEnv(name: "staging")
```

### ServiceKey 协议

通过 `ServiceKey` 提供默认实现：

```swift
struct MyService: ServiceKey {
    static var `default`: MyService {
        MyService()
    }
}
```

### `ServiceAssembly` 协议

通过 `ServiceAssembly` 组织注册：

```swift
struct MyAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        // 注册服务...
    }
}
```

## 最佳实践

1. **使用协议**：定义服务协议以实现灵活性和可测试性
2. **按顺序注册**：在依赖项之前注册依赖
3. **使用 ServiceAssembly**：组织注册以提高可维护性
4. **利用环境**：在不同上下文使用不同环境
5. **在测试中清除缓存**：使用 `resetCaches()` 确保测试中的新实例

## 下一步

- 阅读 <doc:ConcurrencyModel> 了解更多关于 Service 并发设计的详细信息
- 探索 <doc:RealWorldExamples> 获取实用使用模式
- 查看 API 文档以获取详细的方法描述
