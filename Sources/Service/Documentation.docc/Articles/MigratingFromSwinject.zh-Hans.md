# 从 Swinject 迁移

一步步将你的依赖注入从 Swinject 迁移到 Service 的指南。

> Localization: **[English](https://nslogmeng.github.io/swift-service/documentation/service/migratingfromswinject)**  |  **简体中文**

## 为什么迁移？

Service 从设计之初就面向现代 Swift：

- **Swift 6 并发安全** — Sendable 和 MainActor 约束是 API 的一部分，由编译器在编译时强制执行，而非运行时崩溃
- **零依赖** — 无外部包依赖；完全基于 Swift 标准库构建
- **原生属性包装器** — `@Service`、`@MainService`、`@Provider`、`@MainProvider` 提供声明式注入，无需样板代码
- **TaskLocal 环境隔离** — 测试可以并行运行而不互相污染；无需手动管理容器生命周期

## 核心概念映射

| Swinject | Service | 说明 |
|----------|---------|------|
| `Container` | `ServiceEnv` | 基于 TaskLocal，无需手动传递 |
| `container.register` | `env.register` / `env.registerMain` | Sendable 和 MainActor 服务分开注册 |
| `container.resolve` | `@Service` / `try env.resolve` | 属性包装器或手动 typed throws 解析 |
| `Assembly` + `Assembler` | `ServiceAssembly` + `env.assemble()` | 简化设计，无需独立的 Assembler 类型 |
| `.container` 作用域 | `.singleton` 作用域 | 行为相同，两个框架都默认使用 |
| `.transient` 作用域 | `.transient` 作用域 | 行为完全一致 |
| `.graph` 作用域 | `.graph` 作用域 | 行为完全一致 |
| `.weak` 作用域 | — | 无直接等价；可考虑 `.custom` 作用域 |
| `container.synchronize()` | 内置 | 通过 Mutex 和 MainActor 隔离实现线程安全 |
| `name:` 参数 | 协议/类型区分 | 使用不同的协议替代字符串命名 |

## Container → ServiceEnv

在 Swinject 中，你需要创建并管理一个 `Container` 实例，将其传递到需要的地方或存储为全局单例：

```swift
// Swinject
let container = Container()
container.register(DatabaseProtocol.self) { _ in DatabaseService() }

// 必须将 container 传递到使用的地方
let database = container.resolve(DatabaseProtocol.self)!
```

在 Service 中，`ServiceEnv` 使用 Swift 的 `@TaskLocal` 机制。当前环境始终可以通过 `ServiceEnv.current` 访问，无需显式传递：

```swift
// Service
ServiceEnv.current.register(DatabaseProtocol.self) {
    DatabaseService()
}

// 在同一 Task 中的任何位置都可以访问
let database = try ServiceEnv.current.resolve(DatabaseProtocol.self)
```

> Tip: `ServiceEnv.current` 会自动通过 `async`/`await` 边界传播到子 Task 中 —— 无需手动传递。

## 注册

### 工厂注册

最常见的注册模式。注意 Service 的工厂闭包不接受 resolver 参数：

```swift
// Swinject
container.register(DatabaseProtocol.self) { _ in
    DatabaseService(connectionString: "sqlite://app.db")
}

// Service
ServiceEnv.current.register(DatabaseProtocol.self) {
    DatabaseService(connectionString: "sqlite://app.db")
}
```

### 带依赖的注册

Swinject 将 `Resolver` 传入工厂闭包；Service 直接使用 `ServiceEnv.current` 并利用 typed throws 替代强制解包：

```swift
// Swinject
container.register(UserRepositoryProtocol.self) { r in
    let database = r.resolve(DatabaseProtocol.self)!
    let logger = r.resolve(LoggerProtocol.self)!
    return UserRepository(database: database, logger: logger)
}

// Service
ServiceEnv.current.register(UserRepositoryProtocol.self) {
    let database = try ServiceEnv.current.resolve(DatabaseProtocol.self)
    let logger = try ServiceEnv.current.resolve(LoggerProtocol.self)
    return UserRepository(database: database, logger: logger)
}
```

### 直接实例注册

```swift
// Swinject
let database = DatabaseService()
container.register(DatabaseProtocol.self) { _ in database }

// Service
let database = DatabaseService()
ServiceEnv.current.register(database)
```

### MainActor 服务

Swinject 没有内置的 actor 隔离概念。Service 为 MainActor 绑定的类型（如 ViewModel）提供了专用 API：

```swift
// 仅 Service — Swinject 无对应功能
ServiceEnv.current.registerMain(UserViewModel.self) {
    let api = try ServiceEnv.current.resolve(APIClientProtocol.self)
    return UserViewModel(apiClient: api)
}
```

详情请参阅 <doc:MainActorServices>。

## 解析

### 手动解析

Swinject 返回可选值，通常需要强制解包。Service 使用 typed throws 提供更安全的错误处理：

```swift
// Swinject
let database = container.resolve(DatabaseProtocol.self)!

// Service
let database = try ServiceEnv.current.resolve(DatabaseProtocol.self)
```

### 属性包装器注入

Swinject 没有内置属性包装器。Service 提供了四种，在大多数场景下无需手动解析：

```swift
// Service — 懒加载、缓存的注入
struct UserRepository {
    @Service var database: DatabaseProtocol
    @Service var logger: LoggerProtocol
}

// 直接使用 —— 服务在首次访问时解析
let repo = UserRepository()
repo.database.query("SELECT ...")
```

对于可能未注册的可选依赖：

```swift
struct UserController {
    @Service var analytics: AnalyticsService?  // 未注册时返回 nil
}
```

对于 MainActor 隔离的服务：

```swift
@MainActor
final class ProfileViewController: UIViewController {
    @MainService var viewModel: ProfileViewModel
}
```

关于 `@Service` 与 `@Provider` 的完整对比，请参阅 <doc:BasicUsage>。

## 作用域

Swinject 通过方法链配置作用域；Service 在注册时通过 `scope` 参数指定：

| Swinject | Service | 行为 |
|----------|---------|------|
| `.transient` | `.transient` | 每次解析创建新实例 |
| `.graph` | `.graph` | 在同一解析链内共享 |
| `.container` | `.singleton` | 单一缓存实例（两个框架都默认使用） |
| `.weak` | — | 无直接等价 |
| — | `.custom("name")` | 命名作用域，拥有独立缓存 |

```swift
// Swinject
container.register(RequestHandler.self) { _ in RequestHandler() }
    .inObjectScope(.transient)

// Service
ServiceEnv.current.register(RequestHandler.self, scope: .transient) {
    RequestHandler()
}
```

自定义作用域可以独立失效：

```swift
ServiceEnv.current.register(SessionService.self, scope: .custom("user-session")) {
    SessionService()
}

// 用户登出时，仅清除 session 作用域的服务
ServiceEnv.current.resetScope(.custom("user-session"))
```

详情请参阅 <doc:BasicUsage#服务生命周期与作用域>。

## Assembly

Swinject 使用 `Assembly` 协议配合 `Assembler` 管理装配生命周期。Service 简化为 `ServiceAssembly` 加上直接的 `assemble()` 调用：

```swift
// Swinject
class NetworkAssembly: Assembly {
    func assemble(container: Container) {
        container.register(APIClientProtocol.self) { _ in
            APIClient()
        }
    }
}

let assembler = Assembler([
    NetworkAssembly(),
    RepositoryAssembly()
])
let resolver = assembler.resolver

// Service
struct NetworkAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.register(APIClientProtocol.self) {
            APIClient()
        }
    }
}

ServiceEnv.current.assemble(
    NetworkAssembly(),
    RepositoryAssembly()
)
```

主要区别：
- 无需独立的 `Assembler` 类型 —— 直接在 `ServiceEnv` 上调用 `assemble()`
- `ServiceAssembly` 接收 `ServiceEnv` 而非 `Container`
- Assembly 中可以同时使用 `register` 和 `registerMain` 注册 MainActor 服务

详情请参阅 <doc:ServiceAssembly>。

## 并发安全

Swinject 需要手动同步来保证线程安全：

```swift
// Swinject — 必须显式同步
let container = Container()
let threadSafeResolver = container.synchronize()
```

Service 内置并发安全，无需额外操作：

```swift
// Service — 设计上就是线程安全的
// Sendable 服务使用 Mutex 同步
ServiceEnv.current.register(DatabaseProtocol.self) { DatabaseService() }

// MainActor 服务使用 actor 隔离
ServiceEnv.current.registerMain(UserViewModel.self) { UserViewModel() }
```

编译器会强制正确使用：Sendable 服务通过 `register`/`resolve`，MainActor 服务通过 `registerMain`/`resolveMain`。使用错误的 API 会导致编译错误，而非运行时崩溃。

详情请参阅 <doc:ConcurrencyModel>。

## 测试

Swinject 测试通常为每个测试创建新的 Container。Service 利用 TaskLocal 实现环境隔离：

```swift
// Swinject
class UserServiceTests: XCTestCase {
    var container: Container!

    override func setUp() {
        container = Container()
        container.register(DatabaseProtocol.self) { _ in MockDatabase() }
        container.register(UserServiceProtocol.self) { r in
            UserService(database: r.resolve(DatabaseProtocol.self)!)
        }
    }

    func testFetchUser() {
        let service = container.resolve(UserServiceProtocol.self)!
        // ...
    }
}

// Service
final class UserServiceTests: XCTestCase {
    func testFetchUser() async throws {
        let testEnv = ServiceEnv.test
        testEnv.resetAll()

        await ServiceEnv.$current.withValue(testEnv) {
            ServiceEnv.current.register(DatabaseProtocol.self) { MockDatabase() }
            ServiceEnv.current.register(UserServiceProtocol.self) {
                let db = try ServiceEnv.current.resolve(DatabaseProtocol.self)
                return UserService(database: db)
            }

            let service = try ServiceEnv.current.resolve(UserServiceProtocol.self)
            // ...
        }
    }
}
```

基于 TaskLocal 的测试优势：
- 每个测试函数可以使用独立的环境
- 测试可以并行运行，无共享状态冲突
- 无需 `setUp`/`tearDown` 管理容器生命周期

详情请参阅 <doc:ServiceEnvironments>。

## 迁移检查清单

使用此清单追踪你的迁移进度：

1. 将 `import Swinject` 替换为 `import Service`
2. 将 `Container()` 创建替换为 `ServiceEnv.current`
3. 更新工厂注册 —— 从闭包中移除 resolver 参数（`r`/`_`）
4. 将工厂中的 `r.resolve(T.self)!` 替换为 `try ServiceEnv.current.resolve(T.self)`
5. 迁移对象作用域：`.container` → `.singleton`（默认），`.transient` → `.transient`，`.graph` → `.graph`
6. 将 `Assembly` 替换为 `ServiceAssembly`，移除 `Assembler` 的使用
7. 添加 `@Service` / `@MainService` 属性包装器替代调用处的手动解析
8. 对 MainActor 绑定的服务（ViewModel、UI 控制器）使用 `registerMain` / `@MainService`
9. 将测试中 `setUp` 的 Container 创建替换为 `ServiceEnv.$current.withValue(.test)`
10. 移除 `container.synchronize()` 调用 —— 线程安全是内置的
11. 从 `Package.swift` 或 Podfile 中移除 Swinject 依赖

## 下一步

- <doc:BasicUsage> 了解注册和注入模式的完整指南
- <doc:MainActorServices> 了解如何使用 UI 绑定的服务
- <doc:ServiceAssembly> 了解如何将注册组织为模块
- <doc:ServiceEnvironments> 了解基于环境的配置和测试
