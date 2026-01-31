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

## 服务生命周期

默认情况下，服务作为 singleton 缓存。首次解析服务时，会创建并缓存它。后续解析返回同一个实例。

要清除缓存的服务（同时保留注册）：

```swift
await ServiceEnv.current.resetCaches()
```

要完全重置环境（清除缓存并移除所有注册）：

```swift
await ServiceEnv.current.resetAll()
```

## 下一步

- 学习 <doc:ServiceEnvironments> 了解基于环境的服务配置
- 探索 <doc:MainActorServices> 了解 UI 相关服务
- 查看 <doc:ServiceAssembly> 了解如何组织服务注册
