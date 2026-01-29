# 错误处理

了解如何处理服务解析时的错误。

> Localization: **[English](https://nslogmeng.github.io/swift-service/documentation/service/errorhandling)**  |  **简体中文**

## 概述

Service 框架使用 Swift 原生的错误处理机制，在服务解析失败时提供清晰、可操作的错误信息。`resolve()` 和 `resolveMain()` 方法使用 **typed throws**（`throws(ServiceError)`）在编译时保证错误类型，支持使用 switch 语句进行穷尽的错误处理。

## ServiceError 类型

框架定义了四种错误类型：

### notRegistered

当尝试解析未注册的服务时抛出：

```swift
do {
    let service = try ServiceEnv.current.resolve(MyService.self)
} catch ServiceError.notRegistered(let serviceType) {
    print("服务 '\(serviceType)' 未注册")
}
```

### circularDependency

当检测到循环依赖时抛出：

```swift
do {
    let service = try ServiceEnv.current.resolve(ServiceA.self)
} catch ServiceError.circularDependency(let serviceType, let chain) {
    print("检测到循环依赖: \(chain.joined(separator: " -> "))")
}
```

### maxDepthExceeded

当解析深度超过限制时抛出（默认：100）：

```swift
do {
    let service = try ServiceEnv.current.resolve(DeeplyNestedService.self)
} catch ServiceError.maxDepthExceeded(let depth, let chain) {
    print("解析深度超过 \(depth)")
}
```

### factoryFailed

当工厂函数在创建服务时抛出错误：

```swift
do {
    let service = try ServiceEnv.current.resolve(MyService.self)
} catch ServiceError.factoryFailed(let serviceType, let underlyingError) {
    print("创建 '\(serviceType)' 失败: \(underlyingError)")
}
```

**注意：** 如果工厂函数抛出 `ServiceError`，它会直接传播，不会被包装在 `factoryFailed` 中。这允许你在工厂函数中抛出特定的 `ServiceError` 类型。

## 错误处理模式

### 使用 try 直接解析

对于程序化的服务解析，使用 `try` 配合错误处理。得益于 typed throws，你可以使用穷尽的 switch 语句：

```swift
func configureServices() throws(ServiceError) {
    let database = try ServiceEnv.current.resolve(DatabaseProtocol.self)
    let logger = try ServiceEnv.current.resolve(LoggerProtocol.self)
    // 使用服务...
}

// 或使用穷尽的 switch 显式处理错误
do {
    let database = try ServiceEnv.current.resolve(DatabaseProtocol.self)
} catch {
    switch error {  // error 是 ServiceError，不是 any Error
    case .notRegistered(let type):
        print("未注册: \(type)")
    case .circularDependency(_, let chain):
        print("循环依赖: \(chain)")
    case .maxDepthExceeded(let depth, _):
        print("深度超限: \(depth)")
    case .factoryFailed(let type, let underlying):
        print("\(type) 工厂失败: \(underlying)")
    }
}
```

### 属性包装器行为

`@Service` 和 `@MainService` 属性包装器在内部使用 `fatalError`。这是设计使然：

```swift
struct MyController {
    @Service var database: DatabaseProtocol  // 未注册时触发 fatalError
}
```

**为什么使用 fatalError？** 属性包装器在初始化时解析服务。此阶段缺少服务表示配置错误，应在开发期间捕获，而非运行时处理。

### 工厂函数

工厂函数支持 `throws`，允许错误自然传播给调用者：

```swift
ServiceEnv.current.register(UserRepository.self) {
    let database = try ServiceEnv.current.resolve(DatabaseProtocol.self)
    let logger = try ServiceEnv.current.resolve(LoggerProtocol.self)
    return UserRepository(database: database, logger: logger)
}
```

你也可以从工厂函数中抛出自定义错误或 `ServiceError`：

```swift
ServiceEnv.current.register(DatabaseService.self) {
    guard let connectionString = ProcessInfo.processInfo.environment["DB_URL"] else {
        throw ServiceError.notRegistered(serviceType: "DB_URL 环境变量")
    }
    return DatabaseService(connectionString: connectionString)
}
```

当工厂函数抛出错误时：
- `ServiceError` 会直接传播给调用者
- 其他错误会被包装在 `ServiceError.factoryFailed` 中

## 最佳实践

### 尽早注册所有服务

在应用初始化期间注册所有服务，以便尽早捕获配置错误：

```swift
@main
struct MyApp: App {
    init() {
        ServiceEnv.current.assemble(
            DatabaseAssembly(),
            LoggerAssembly(),
            RepositoryAssembly()
        )
    }
}
```

有关组织注册的更多信息，请参阅 <doc:ServiceAssembly>。

### 对必需依赖使用属性包装器

对于必须存在的服务，使用属性包装器：

```swift
struct UserController {
    @Service var userRepository: UserRepositoryProtocol
}
```

### 对可选依赖使用直接解析

对于可能未注册的服务，使用直接解析配合错误处理：

```swift
func loadAnalytics() {
    do {
        let analytics = try ServiceEnv.current.resolve(AnalyticsProtocol.self)
        analytics.track("app_launched")
    } catch {
        // 分析服务未配置，跳过追踪
    }
}
```

### 在测试中验证配置

在测试中验证所有必需服务都已注册：

```swift
@Test func testServiceConfiguration() throws {
    // 正确配置的服务不应抛出错误
    _ = try ServiceEnv.current.resolve(DatabaseProtocol.self)
    _ = try ServiceEnv.current.resolve(LoggerProtocol.self)
}
```

有关测试策略的更多信息，请参阅 <doc:ServiceEnvironments>。

## 错误信息

ServiceError 提供清晰、描述性的错误信息：

```
Service 'DatabaseProtocol' is not registered in ServiceEnv

Circular dependency detected for service 'ServiceA'.
Dependency chain: ServiceA -> ServiceB -> ServiceC -> ServiceA
Check your service registration to break the cycle.

Maximum resolution depth (100) exceeded.
Current chain: A -> B -> C -> ...
This may indicate a circular dependency or overly deep dependency graph.

Factory failed to create service 'MyService': Connection refused
```

## 另请参阅

- ``ServiceError``
- <doc:CircularDependencies>
- <doc:BasicUsage>
