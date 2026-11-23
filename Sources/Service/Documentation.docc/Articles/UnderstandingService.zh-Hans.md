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
│              │  registry (加锁):     │              │
│              │    类型 → 条目        │              │
│              │    条目: 作用域、     │              │
│              │    工厂函数、槽位     │              │
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
│     (作用域、工厂函数、 │
│     缓存槽位)           │
└─────────────────────────┘
         │ 找到
         ▼
┌─────────────────────────┐
│  2. 读取缓存槽位        │──── 已有实例? ──▶ 直接返回
│     (singleton、custom) │
└─────────────────────────┘
         │ 槽位为空，或没有槽位
         ▼
┌─────────────────────────┐
│  3. 检查循环            │──── 在链中? ──▶ 抛出 circularDependency
└─────────────────────────┘
         │ 正常
         ▼
┌─────────────────────────┐
│  4. 跟踪到链中 +       │
│     创建 graph 缓存     │──── (如果是顶层 resolve)
│     (如果需要)          │
└─────────────────────────┘
         │
         ▼
┌─────────────────────────┐
│  5. 按作用域分派        │
└────────┬────────────────┘
         │
         ├── singleton → 检查缓存 → 命中: 返回 │ 未命中: 工厂 + 缓存
         ├── transient → 调用工厂 → 返回新实例
         ├── graph     → 检查 graph 缓存 → 命中: 返回 │ 未命中: 工厂 + 缓存
         └── custom    → 检查命名缓存 → 命中: 返回 │ 未命中: 工厂 + 缓存
```

### 作用域特定行为

| 作用域 | 缓存方式 | 存储位置 | 重置方式 |
|--------|---------|---------|---------|
| `.singleton` | 全局缓存，每个类型一个实例 | 该注册的缓存槽位 | `resetCaches()` 或 `resetScope(.singleton)` |
| `.transient` | 不缓存，每次创建新实例 | 不适用 | 不适用 |
| `.graph` | 在同一解析链内共享 | 解析链的 graph 缓存，按环境和类型存取 | 自动释放（顶层 resolve 完成时） |
| `.custom("name")` | 命名缓存，独立于其他作用域 | 该注册的缓存槽位 | `resetScope(.custom("name"))` |

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

`register` 保存的工厂函数可以在任意线程执行，创建出的实例跨隔离域共享。因此工厂函数必须是 nonisolated 的 `@Sendable` 闭包，服务类型必须是 `Sendable`。存在于 MainActor 上的服务往往满足不了这些要求：
- 它们的初始化器是 MainActor 隔离的，nonisolated 的工厂函数无法调用
- 注册它们所用的协议往往不是 `Sendable`，例如 `@MainActor` 协议
- 继承自非 `Sendable` 基类的 `@MainActor` 类不是 `Sendable`

除最后一种情况外，`@MainActor` 类隐式遵循 `Sendable`。留在 MainActor 上的是它的初始化器和成员。

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
public struct Service<S: Sendable>: Sendable {
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

所有共享状态都放在 `Locked` 类型的值里，即由锁保护的值。Apple 平台上的锁是 `OSAllocatedUnfairLock`，Linux 和 Android 上是 `Synchronization.Mutex`。Wasm 只有一个线程，不加锁。

```swift
private let registry = Locked<[ObjectIdentifier: Entry]>()
```

`Locked` 里的值只在 `withLock` 内修改，因此读取、修改和写回处于同一个临界区。

注册表为每个已注册的服务类型保存一个条目，以静态类型的标识符为键。条目保存这次注册的作用域和工厂函数。工厂函数要么是 Sendable 的，要么是 MainActor 的，所以一个类型只有一次注册，并且只属于一类。对于 singleton 和 custom 作用域，条目还保存一个类型为 `Locked<AnyCacheBox?>` 的缓存槽位。

### 按键的一次性创建

Singleton 或 custom 作用域的注册有一个自带锁的缓存槽位。解析按以下步骤进行：

1. 获取注册表锁，复制条目，然后释放注册表锁。
2. 获取槽位锁并读取槽位。槽位中已有实例时直接返回。
3. 否则开始解析跟踪，并再次获取槽位锁。槽位中此时已有实例时直接返回。没有实例时执行工厂函数，并把结果存入槽位。

第 2 步不执行工厂函数。它跳过循环检测，也不计入 `maxResolutionDepth`。如果当前线程已经在解析同一个注册，它正持有槽位锁。此时解析跳过第 2 步，由第 3 步报告循环。

工厂函数执行期间持有槽位锁。因此，每个缓存实例的工厂函数至多执行一次，同一服务的并发首次解析方会等待它完成。工厂函数执行期间从不持有注册表锁，所以慢的工厂函数只阻塞同一服务的解析方。

重置方法给受影响的条目换上新的空槽位，不获取槽位锁。已经持有旧槽位的解析会用旧槽位完成。之后的解析使用新的槽位。

存储在释放注册表锁之后，才释放旧槽位和其中缓存的实例。因此，服务的 `deinit` 可以使用它所在的环境。

重新注册同一类型会替换它的条目。作用域和类别都相同时，新条目沿用原槽位，所以已缓存的实例保留到下一次重置。否则，新条目从空槽位开始。

这一设计带来的保证和限制，请参阅 <doc:ConcurrencyModel>。

### 解析链

一条解析链是一次顶层 `resolve` 调用，加上它的工厂函数发起的各次解析。解析是同步的，所以一条链从第一步到最后一步都在同一个线程上执行。`ServiceContext` 把解析链绑定到这个线程。一条链包含：

- **步骤**：正在解析的各个注册。一个步骤由它所在的环境和服务类型标识。
- **Graph 缓存**：这条链的 graph 作用域实例。

返回缓存实例的解析不是链上的步骤。需要执行工厂函数的解析按以下步骤进行：

1. 链上已有这个注册，或者这个线程已经持有它的缓存槽位的锁时，抛出 `ServiceError.circularDependency`。
2. 链的长度达到 `ServiceEnv.maxResolutionDepth` 时，抛出 `ServiceError.maxDepthExceeded`。
3. 把这个注册加入链，执行工厂函数，然后把它从链上移除。

第一步返回时，解析链结束，它的 graph 作用域实例随之释放。

解析链属于线程，不属于任务：

- 工厂函数里启动的任务不属于这条链。它可以解析启动它的那个服务，它的解析是各自独立的链。
- 另一个任务在正在执行工厂函数的线程上发起的解析，会开始一条它自己的链，有自己的步骤和 graph 缓存。工厂函数内的嵌套 run loop 会造成这种情况。第一条链被打断，直到第二条链结束。如果该任务解析被打断的链正在创建的 singleton 或 custom 作用域服务，解析抛出 `circularDependency`：这个线程已经持有该缓存槽位的锁，解析无法等待同一线程上位于它下方的工厂函数。
- 一个环境的工厂函数可以从另一个环境解析同一类型。两者是不同的注册。

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
| 首次解析（singleton/custom） | O(1) + 工厂函数 | 加上循环检测；工厂函数在该注册的槽位锁内执行 |
| 缓存解析（singleton/custom） | O(1) | 按类型查找一次注册表，再读取槽位（两次无竞争加锁）；不做解析跟踪 |
| Transient 解析 | O(1) + 工厂函数 | 无缓存开销 |
| Graph 解析 | O(1) + 工厂函数 | 在解析链的 graph 缓存中查找 |
| 环境切换 | O(1) | TaskLocal 绑定 |
| 重置所有缓存 | O(n) | 给每个带缓存的注册换上新槽位 |
| 重置特定作用域 | O(n) | 按作用域过滤 |

### 内存考虑

- 每个注册的服务存储一个工厂闭包；singleton 和 custom 作用域另有一个缓存槽位
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
