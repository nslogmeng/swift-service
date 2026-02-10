# 基本用法

学习使用 Service 注册和使用服务的基本模式。

> Localization: **[English](https://nslogmeng.github.io/swift-service/documentation/service/basicusage)**  |  **简体中文**

## 注册服务

Service 提供了多种注册服务的方式，每种方式适用于不同的场景。

### 工厂函数注册

最常见的模式是使用工厂函数注册服务：

```swift
// 注册基于协议的服务
ServiceEnv.current.register(DatabaseProtocol.self) {
    DatabaseService(connectionString: "sqlite://app.db")
}

// 注册具体类型
ServiceEnv.current.register(LoggerService.self) {
    LoggerService(logLevel: .info)
}
```

你还可以指定 **scope** 来控制服务的生命周期：

```swift
// Transient：每次访问创建新实例
ServiceEnv.current.register(RequestHandler.self, scope: .transient) {
    RequestHandler()
}

// 自定义作用域：可独立失效的共享缓存
ServiceEnv.current.register(SessionService.self, scope: .custom("user-session")) {
    SessionService()
}
```

有关所有可用作用域的详细信息，请参阅<doc:BasicUsage#服务生命周期与作用域>。

### 直接实例注册

对于已经实例化的服务，可以直接注册：

```swift
let database = DatabaseService(connectionString: "sqlite://app.db")
ServiceEnv.current.register(database)
```

### ServiceKey 协议

对于具有默认实现的服务，使用 `ServiceKey` 协议。当你的服务有一个合理的默认配置时，这可以减少样板代码：

```swift
struct DatabaseService: ServiceKey {
    let connectionString: String

    static var `default`: DatabaseService {
        DatabaseService(connectionString: "sqlite://app.db")
    }
}

// 使用默认实现注册
ServiceEnv.current.register(DatabaseService.self)

// 或使用自定义工厂函数覆盖
ServiceEnv.current.register(DatabaseService.self) {
    DatabaseService(connectionString: "postgresql://prod.db")
}
```

**何时使用 ServiceKey：**
- 具有通用默认配置的服务
- 不需要复杂初始化的简单服务
- 减少 Assembly 中的注册样板代码

有关 ServiceKey 设计的更多详细信息，请参阅 <doc:UnderstandingService>。

## 注入服务

### 使用 @Service 属性包装器

`@Service` 属性包装器提供懒加载依赖注入。服务在首次访问时解析（而非初始化时），解析结果会被缓存供后续访问使用：

```swift
struct UserRepository {
    @Service
    var database: DatabaseProtocol

    @Service
    var logger: LoggerProtocol

    func fetchUser(id: String) -> User? {
        logger.info("Fetching user: \(id)")
        return database.findUser(id: id)
    }
}
```

环境在初始化时捕获，确保无论何时首次访问属性，行为都保持一致。

### 显式类型指定

当属性类型可能不明确时，显式指定服务类型：

```swift
struct UserRepository {
    @Service(DatabaseProtocol.self)
    var database: DatabaseProtocol
}
```

### 可选服务

对于可能未注册的服务，使用可选类型。属性会返回 `nil` 而不是触发 fatal error：

```swift
struct UserController {
    @Service var analytics: AnalyticsService?  // 未注册时返回 nil

    func trackEvent(_ event: String) {
        analytics?.track(event)  // 安全的可选访问
    }
}
```

你也可以对可选类型使用显式类型指定：

```swift
struct UserController {
    @Service(AnalyticsService.self)
    var analytics: AnalyticsService?
}
```

> Tip: 所有四个属性包装器（`@Service`、`@MainService`、`@Provider`、`@MainProvider`）都支持可选类型。

### 使用 @Provider 属性包装器

`@Provider` 属性包装器在**每次访问时**解析服务，将缓存行为完全委托给服务注册的作用域。与始终在本地缓存的 `@Service` 不同，`@Provider` 非常适合 transient 或自定义作用域的服务：

```swift
// 注册 transient 服务
ServiceEnv.current.register(RequestHandler.self, scope: .transient) {
    RequestHandler()
}

struct Controller {
    @Provider var handler: RequestHandler  // 每次访问都是新实例
}
```

`@Provider` 同样支持可选类型：

```swift
struct Controller {
    @Provider var analytics: AnalyticsService?  // 未注册时返回 nil
}
```

**何时使用 @Service vs @Provider：**

| | `@Service` / `@MainService` | `@Provider` / `@MainProvider` |
|---|---|---|
| 解析时机 | 懒加载，首次访问时 | 每次访问时 |
| 本地缓存 | 始终在本地缓存 | 不进行本地缓存；委托给作用域 |
| 适用场景 | Singleton 服务 | Transient 或自定义作用域服务 |

有关 MainActor 隔离的对应版本，请参阅 <doc:MainActorServices> 中的 `@MainProvider`。

### 手动解析

你也可以使用 `try` 手动解析服务：

```swift
let database = try ServiceEnv.current.resolve(DatabaseProtocol.self)
let logger = try ServiceEnv.current.resolve(LoggerProtocol.self)
```

有关错误处理的详细信息，请参阅 <doc:ErrorHandling>。

## 依赖注入

服务可以依赖其他服务。注册服务时，可以解析其依赖：

```swift
// 注册基础服务
ServiceEnv.current.register(DatabaseProtocol.self) {
    DatabaseService()
}

ServiceEnv.current.register(LoggerProtocol.self) {
    LoggerService()
}

// 注册依赖其他服务的服务
ServiceEnv.current.register(UserRepositoryProtocol.self) {
    let database = try ServiceEnv.current.resolve(DatabaseProtocol.self)
    let logger = try ServiceEnv.current.resolve(LoggerProtocol.self)
    return UserRepository(database: database, logger: logger)
}
```

## 服务生命周期与作用域

默认情况下，服务以 `.singleton` 作用域注册 -- 首次解析服务时，会创建并缓存它。后续解析返回同一个实例。

Service 通过 ``ServiceScope`` 支持四种生命周期作用域：

| 作用域 | 行为 |
|--------|------|
| `.singleton` | 全局缓存单一实例（默认） |
| `.transient` | 每次解析都创建新实例 |
| `.graph` | 在同一解析图内共享；每次顶层 `resolve()` 调用获得新实例 |
| `.custom("name")` | 命名作用域，拥有独立缓存，支持定向失效 |

```swift
// Singleton（默认）- 复用同一实例
env.register(DatabaseService.self) { DatabaseService() }

// Transient - 每次创建新实例
env.register(RequestHandler.self, scope: .transient) { RequestHandler() }

// Graph - 在同一解析链内共享
env.register(UnitOfWork.self, scope: .graph) { UnitOfWork() }

// Custom - 命名作用域，拥有独立缓存
env.register(SessionService.self, scope: .custom("user-session")) { SessionService() }
```

### 重置服务

要清除缓存的服务（同时保留注册）：

```swift
ServiceEnv.current.resetCaches()
```

要仅清除特定作用域（例如用户登出时）：

```swift
ServiceEnv.current.resetScope(.custom("user-session"))
```

要完全重置环境（清除缓存并移除所有注册）：

```swift
ServiceEnv.current.resetAll()
```

有关重置的更多详细信息，请参阅 <doc:ServiceEnvironments>。

## 下一步

- 学习 <doc:ServiceEnvironments> 了解基于环境的服务配置
- 探索 <doc:MainActorServices> 了解 UI 相关服务
- 查看 <doc:ServiceAssembly> 了解如何组织服务注册
