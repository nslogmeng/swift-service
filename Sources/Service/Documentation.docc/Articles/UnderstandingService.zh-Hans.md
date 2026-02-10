# 理解 Service

深入了解 Service 的架构、设计决策及其工作原理。

> Localization: **[English](https://nslogmeng.github.io/swift-service/documentation/service/understandingservice)**  |  **简体中文**

## 架构概览

Service 围绕五个核心概念构建：

1. **ServiceEnv**：管理注册和解析的服务环境
2. **ServiceStorage**：存储提供者和缓存实例的存储层
3. **ServiceScope**：服务实例的生命周期管理（singleton、transient、graph、custom）
4. **ServiceContext**：解析跟踪，用于循环依赖检测和 graph 作用域缓存
5. **属性包装器**：依赖注入的便捷语法（`@Service`、`@MainService`、`@Provider`、`@MainProvider`）

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
│              │  • mainProviders      │              │
│              │  • caches (加锁)      │              │
│              │    key: Type + Scope  │              │
│              └───────────────────────┘              │
└─────────────────────────────────────────────────────┘
```

### 属性包装器矩阵

Service 提供四个属性包装器，形成 2x2 矩阵：

|  | **Sendable** | **MainActor** |
|---|---|---|
| **懒加载 + 缓存** | `@Service` | `@MainService` |
| **作用域驱动** | `@Provider` | `@MainProvider` |

- **`@Service` / `@MainService`**：首次访问时懒加载解析，并在内部缓存结果。后续访问始终返回同一实例，不受注册作用域的影响。
- **`@Provider` / `@MainProvider`**：每次访问时解析。缓存行为完全由服务注册的作用域决定（例如，transient 作用域每次都会生成新实例）。

四个属性包装器都支持可选类型 — 当服务未注册时返回 `nil` 而非崩溃：

```swift
@Service var analytics: AnalyticsService?    // 懒加载，缓存，nil 安全
@Provider var handler: RequestHandler?       // 作用域驱动，nil 安全
```

## 服务解析流程

当你调用 `resolve()` 时，行为取决于服务注册的作用域：

```
resolve(MyService.self)
         │
         ▼
┌─────────────────────────┐
│  1. 获取提供者条目      │──── 未找到? ──▶ 抛出 notRegistered
│     (包含作用域)        │
└─────────────────────────┘
         │ 找到
         ▼
┌─────────────────────────┐
│  2. 检查循环            │──── 在链中? ──▶ 抛出 circularDependency
└─────────────────────────┘
         │ 正常
         ▼
┌─────────────────────────┐
│  3. 跟踪到链中 +       │
│     创建 graph 缓存     │──── (如果是顶层 resolve)
│     (如果需要)          │
└─────────────────────────┘
         │
         ▼
┌─────────────────────────┐
│  4. 按作用域分派        │
└─────────────────────────┘
    │         │        │         │
    ▼         ▼        ▼         ▼
singleton  transient  graph    custom
    │         │        │         │
    ▼         ▼        ▼         ▼
  检查       调用     检查      检查
  缓存     工厂函数  graph    命名
    │         │      缓存      缓存
    │         │        │         │
    ▼         ▼        ▼         ▼
  找到?     返回     找到?     找到?
  是→返回   新实例   是→返回   是→返回
  否→调用            否→调用   否→调用
  工厂函数           工厂函数  工厂函数
  + 缓存             + 缓存   + 缓存
```

### 作用域特定行为

| 作用域 | 缓存方式 | 缓存键 | 重置方式 |
|--------|---------|--------|---------|
| `.singleton` | 全局缓存，每个类型一个实例 | Type + `.singleton` | `resetCaches()` 或 `resetScope(.singleton)` |
| `.transient` | 不缓存，每次创建新实例 | 不适用 | 不适用 |
| `.graph` | 在同一解析链内共享 | Type + `.graph`（在 `GraphCacheBox` 中） | 自动释放（顶层 resolve 完成时） |
| `.custom("name")` | 命名缓存，独立于其他作用域 | Type + `.custom("name")` | `resetScope(.custom("name"))` |

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

属性包装器对缺失的非可选服务使用 `fatalError`：

```swift
@propertyWrapper
public struct Service<S: Sendable>: @unchecked Sendable {
    private let storage: Locked<S?>
    private let env: ServiceEnv

    public var wrappedValue: S {
        // 首次访问时懒加载解析
        // 如果服务未注册则使用 fatalError
    }
}
```

**理由：**
- 缺失的服务表示**配置错误**，而非运行时条件
- 快速失败行为在开发期间捕获问题
- 清晰的错误消息帮助诊断问题

**对于可选依赖**，使用可选类型语法：

```swift
struct MyController {
    @Service var analytics: AnalyticsService?  // 未注册时返回 nil
}
```

这提供了优雅的处理方式，不会触发 fatalError。

### 为什么默认使用单例？

当未指定作用域时，服务默认使用 `.singleton`：

```swift
env.register(DatabaseService.self) { DatabaseService() }
// 等价于：
env.register(DatabaseService.self, scope: .singleton) { DatabaseService() }

let service1 = try ServiceEnv.current.resolve(DatabaseService.self)
let service2 = try ServiceEnv.current.resolve(DatabaseService.self)
// service1 === service2（同一实例）
```

**优点：**
- 可预测的行为（处处相同的实例）
- 内存高效（每个服务单一实例）
- 符合常见的 DI 模式
- 与先前版本向后兼容

**当你需要其他生命周期时**，使用显式作用域：

```swift
// 每次获取新实例
env.register(RequestHandler.self, scope: .transient) { RequestHandler() }

// 在同一解析链内共享，跨链获取新实例
env.register(UnitOfWork.self, scope: .graph) { UnitOfWork() }

// 命名作用域，支持定向失效
env.register(SessionService.self, scope: .custom("user-session")) {
    SessionService()
}
env.resetScope(.custom("user-session"))  // 仅清除此作用域
```

## 内部实现

### 线程安全

Service 使用 Swift 的 `Synchronization.Mutex` 实现线程安全访问：

```swift
@Locked private var caches: [CacheKey: CacheBox]
@Locked private var providers: [CacheKey: ProviderEntry]
@Locked private var mainProviders: [CacheKey: MainProviderEntry]
```

`@Locked` 属性包装器确保原子读写操作。`CacheKey` 是服务类型（`ObjectIdentifier`）和其作用域的复合键，确保在不同作用域下注册的服务拥有隔离的缓存。

### 循环依赖检测和 Graph 缓存

`ServiceContext` 使用 `TaskLocal` 跟踪解析链并管理 graph 作用域缓存：

```swift
enum ServiceContext {
    @TaskLocal static var resolutionStack: [String] = []
    @TaskLocal static var graphCacheBox: GraphCacheBox?
}
```

解析服务时：
1. 检查服务类型是否已在栈中（循环依赖检测）
2. 如果是，抛出 `ServiceError.circularDependency`
3. 如果否，添加到栈中并继续
4. 如果是顶层 resolve，创建新的 `GraphCacheBox` 用于 graph 作用域的服务
5. 同一链中的嵌套 resolve 共享同一个 `GraphCacheBox`

这种方法的特点：
- **任务作用域**：每个异步任务有自己的解析栈
- **自动清理**：解析完成后栈和 graph 缓存会恢复
- **零开销**：不解析时无跟踪
- **Graph 感知**：使用 `.graph` 作用域的服务在同一解析链内共享实例

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
| 首次解析（singleton/custom） | O(1) + 工厂函数 | 加上循环检测、双重检查缓存 |
| 缓存解析（singleton/custom） | O(1) | 按复合键查找字典 |
| Transient 解析 | O(1) + 工厂函数 | 无缓存开销 |
| Graph 解析 | O(1) + 工厂函数 | 在任务本地 graph 缓存中查找 |
| 环境切换 | O(1) | TaskLocal 绑定 |
| 重置所有缓存 | O(n) | 清除所有缓存实例 |
| 重置特定作用域 | O(n) | 按作用域过滤 |

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
