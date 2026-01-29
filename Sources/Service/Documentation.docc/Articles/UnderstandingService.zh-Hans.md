# 理解 Service

深入了解 Service 的架构、设计决策及其工作原理。

> Localization: **[English](https://nslogmeng.github.io/swift-service/documentation/service/understandingservice)**  |  **简体中文**

## 架构概览

Service 围绕三个核心概念构建：

1. **ServiceEnv**：管理注册和解析的服务环境
2. **ServiceStorage**：存储提供者和缓存实例的存储层
3. **属性包装器**：依赖注入的便捷语法

```
┌─────────────────────────────────────────────────────┐
│                    ServiceEnv                        │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │
│  │   .online   │  │    .dev     │  │    .test    │  │
│  │   (默认)    │  │             │  │             │  │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  │
│         │                │                │         │
│         └────────────────┼────────────────┘         │
│                          │                          │
│              ┌───────────▼───────────┐              │
│              │    ServiceStorage     │              │
│              │  • providers (加锁)   │              │
│              │  • cache (加锁)       │              │
│              │  • mainProviders      │              │
│              │  • mainCache          │              │
│              └───────────────────────┘              │
└─────────────────────────────────────────────────────┘
```

## 服务解析流程

当你调用 `resolve()` 时，会发生以下情况：

```
resolve(MyService.self)
         │
         ▼
┌─────────────────────┐
│  1. 检查缓存        │──── 找到? ──▶ 返回缓存实例
└─────────────────────┘
         │ 未找到
         ▼
┌─────────────────────┐
│  2. 获取提供者      │──── 未找到? ──▶ 抛出 notRegistered
└─────────────────────┘
         │ 找到
         ▼
┌─────────────────────┐
│  3. 检查循环        │──── 在链中? ──▶ 抛出 circularDependency
└─────────────────────┘
         │ 正常
         ▼
┌─────────────────────┐
│  4. 跟踪到链中      │
└─────────────────────┘
         │
         ▼
┌─────────────────────┐
│  5. 调用工厂函数    │──── 抛出错误? ──▶ 传播错误
└─────────────────────┘
         │ 成功
         ▼
┌─────────────────────┐
│  6. 缓存实例        │
└─────────────────────┘
         │
         ▼
    返回实例
```

## 设计决策

### 为什么使用 TaskLocal 管理环境上下文？

Service 使用 `@TaskLocal` 存储当前环境：

```swift
public struct ServiceEnv: Sendable {
    @TaskLocal
    public static var current: ServiceEnv = .online
}
```

**优点：**
- **异步安全**：跨 `await` 边界自动维护
- **任务作用域**：环境切换隔离到当前任务及其子任务
- **线程安全**：无需额外的同步
- **继承性**：子任务自动继承父任务的环境

**权衡：**
- 无法在同步上下文中更改环境，必须使用 `withValue`
- 每次任务切换会产生少量开销

### 为什么需要单独的 MainActor API？

Swift 6 要求跨 actor 边界传递的值必须是 `Sendable`。但是，`@MainActor` 类：
- 有可变状态（不会自动成为 `Sendable`）
- 通过 actor 隔离实现线程安全
- 无法安全地传递给其他 actor

Service 通过单独的 API 解决这个问题：

| API | 使用场景 | 线程安全 |
|-----|----------|---------|
| `register`/`resolve` | Sendable 服务 | 基于 Mutex 的锁定 |
| `registerMain`/`resolveMain` | MainActor 服务 | Actor 隔离 |

### 为什么 ServiceAssembly 使用 @MainActor？

```swift
@MainActor
public protocol ServiceAssembly {
    func assemble(env: ServiceEnv)
}
```

**原因：**
1. 组装通常在应用初始化期间运行（已经在主 actor 上）
2. 确保顺序、可预测的注册顺序
3. 简化开发者的心智模型
4. 允许在一处注册 Sendable 和 MainActor 服务

### 为什么属性包装器使用 fatalError？

属性包装器对缺失的服务使用 `fatalError`：

```swift
@propertyWrapper
public struct Service<S: Sendable>: Sendable {
    public init() {
        // 如果服务未注册则使用 fatalError
        self.wrappedValue = try! ServiceEnv.current.resolve(S.self)
    }
}
```

**理由：**
- 缺失的服务表示**配置错误**，而非运行时条件
- 快速失败行为在开发期间捕获问题
- 清晰的错误消息帮助诊断问题
- 对于可选依赖，使用手动 `resolve()` 配合错误处理

### 为什么默认使用单例？

服务作为单例缓存：

```swift
let service1 = try ServiceEnv.current.resolve(MyService.self)
let service2 = try ServiceEnv.current.resolve(MyService.self)
// service1 === service2（同一实例）
```

**优点：**
- 可预测的行为（处处相同的实例）
- 内存高效（每个服务单一实例）
- 符合常见的 DI 模式

**当你需要新实例时：**
- 调用 `resetCaches()` 清除缓存
- 创建新的 `ServiceEnv` 以获得隔离的作用域

## 内部实现

### 线程安全

Service 使用 Swift 的 `Synchronization.Mutex` 实现线程安全访问：

```swift
@Locked private var providers: [String: Any] = [:]
@Locked private var cache: [String: Any] = [:]
```

`@Locked` 属性包装器确保原子读写操作。

### 循环依赖检测

Service 使用 `TaskLocal` 跟踪解析链：

```swift
@TaskLocal
private static var resolutionChain: [String] = []
```

解析服务时：
1. 检查服务类型是否已在链中
2. 如果是，抛出 `ServiceError.circularDependency`
3. 如果否，添加到链中并继续

这种方法的特点：
- **任务作用域**：每个异步任务有自己的链
- **自动清理**：解析完成后链会恢复
- **零开销**：不解析时无跟踪

### ServiceKey 协议

`ServiceKey` 提供了一种便捷的方式来注册带有默认实现的服务：

```swift
public protocol ServiceKey {
    static var `default`: Self { get }
}

// 使用
struct MyService: ServiceKey {
    static var `default`: MyService { MyService() }
}

ServiceEnv.current.register(MyService.self)  // 使用默认实现
```

**设计意图：**
- 减少简单服务的样板代码
- 提供默认实现的编译时保证
- 适用于值类型和引用类型

## 性能特征

| 操作 | 复杂度 | 说明 |
|------|--------|------|
| 注册 | O(1) | 字典插入 |
| 首次解析 | O(1) + 工厂函数 | 加上循环检测 |
| 缓存解析 | O(1) | 字典查找 |
| 环境切换 | O(1) | TaskLocal 绑定 |
| 重置缓存 | O(n) | 清除所有缓存实例 |

### 内存考虑

- 每个注册的服务存储一个工厂闭包
- 每个解析的服务存储一个缓存实例
- 解析链跟踪使用栈分配的数组
- 环境切换的内存开销很小

## 扩展点

### 自定义环境

```swift
let staging = ServiceEnv(name: "staging")
let featureFlag = ServiceEnv(name: "feature-x")
```

### 使用 ServiceAssembly 实现模块化

```swift
struct NetworkAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.register(APIClient.self) { APIClient() }
        env.register(ImageLoader.self) { ImageLoader() }
    }
}

ServiceEnv.current.assemble(NetworkAssembly())
```

## 另请参阅

- <doc:ConcurrencyModel>
- <doc:ServiceAssembly>
- <doc:ErrorHandling>
