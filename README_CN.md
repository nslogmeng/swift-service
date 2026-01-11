<div align="center">
  <img src="./images/logo.png" alt="Service Logo" >
</div>

# Service

[![GitHub License](https://img.shields.io/github/license/nslogmeng/swift-service)](./LICENSE)
[![Swift Version Status](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fnslogmeng%2Fswift-service%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/nslogmeng/swift-service)
[![Platform Support Status](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fnslogmeng%2Fswift-service%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/nslogmeng/swift-service)
[![Build Status](https://github.com/nslogmeng/swift-service/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/nslogmeng/swift-service/actions/workflows/build.yml)
[![Test Status](https://github.com/nslogmeng/swift-service/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/nslogmeng/swift-service/actions/workflows/test.yml)

<div align="center">
    <a href="./README.md">English</a> | 简体中文
</div>
<br/>

一个轻量级、零依赖、类型安全的 Swift 依赖注入框架。  
受 [Swinject](https://github.com/Swinject/Swinject) 和 [swift-dependencies](https://github.com/pointfreeco/swift-dependencies) 启发，Service 利用现代 Swift 特性实现简单、健壮的依赖注入。

## 特性

- **现代 Swift**：使用属性包装器、TaskLocal 和并发原语。
- **轻量级且零依赖**：无第三方依赖，占用空间小。
- **简单易用**：易于注册和注入服务。
- **类型安全**：编译时检查服务注册和解析。
- **线程安全**：适用于并发和异步代码。
- **环境支持**：可在生产、开发和测试环境之间切换。

## 安装

在 `Package.swift` 中添加：

```swift
dependencies: [
    .package(url: "https://github.com/nslogmeng/swift-service", .upToNextMajor(from: "1.0.0"))
],
targets: [
    .target(
        name: "MyProject",
        dependencies: [
            .product(name: "Service", package: "swift-service"),
        ]
    )
]
```

## 快速开始

### 1. 注册服务

使用工厂函数注册：

```swift
ServiceEnv.current.register(DatabaseProtocol.self) {
    DatabaseService(connectionString: "sqlite://app.db")
}
```

或直接注册服务实例：

```swift
let database = DatabaseService(connectionString: "sqlite://app.db")
ServiceEnv.current.register(database)
```

或使用 `ServiceKey` 协议：

```swift
struct DatabaseService: ServiceKey {
    static var `default`: DatabaseService {
        DatabaseService(connectionString: "sqlite://app.db")
    }
}

// 注册
ServiceEnv.current.register(DatabaseService.self)
```

### 2. 注入和使用

使用 `@Service` 属性包装器注入服务：

```swift
struct UserManager {
    @Service
    var database: DatabaseProtocol
    
    @Service
    var logger: LoggerProtocol
    
    func createUser(name: String) {
        logger.info("Creating user: \(name)")
        // 使用 database...
    }
}
```

也可以显式指定服务类型：

```swift
struct UserManager {
    @Service(DatabaseProtocol.self)
    var database: DatabaseProtocol
}
```

### 3. 环境切换示例

在不同环境（生产、开发、测试）中使用不同的服务配置：

```swift
// 在测试中切换到开发环境
await ServiceEnv.$current.withValue(.dev) {
    // 在此块中解析的所有服务都使用 dev 环境
    let userService = UserService()
    let result = userService.createUser(name: "Test User")
}
```

### 4. 依赖注入示例

服务可以依赖其他服务：

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
    let database = ServiceEnv.current.resolve(DatabaseProtocol.self)
    let logger = ServiceEnv.current.resolve(LoggerProtocol.self)
    return UserRepository(database: database, logger: logger)
}
```

### 5. MainActor 服务（UI 组件）

对于必须在主线程运行的 UI 相关服务（如视图模型、UI 控制器），swift-service 提供了专门的 MainActor 安全 API。

**背景**：在 Swift 6 的严格并发模型中，`@MainActor` 类是线程安全的（所有访问都在主线程上序列化），但**不会**自动成为 `Sendable`。这意味着它们无法使用需要 `Sendable` 遵循的标准 `register`/`resolve` API。

```swift
// 定义一个 MainActor 服务（不需要遵循 Sendable）
@MainActor
final class ViewModelService {
    var data: String = ""
    func loadData() { data = "loaded" }
}

// 在主 actor 上下文中注册
await MainActor.run {
    ServiceEnv.current.registerMain(ViewModelService.self) {
        ViewModelService()
    }
}

// 使用直接方法解析
@MainActor
func setupUI() {
    let viewModel = ServiceEnv.current.resolveMain(ViewModelService.self)
    viewModel.loadData()
}

// 或使用 @MainService 属性包装器
@MainActor
class MyViewController {
    @MainService
    var viewModel: ViewModelService
}
```

### 6. 服务装配（标准化注册）

为了更好地组织和复用，使用 `ServiceAssembly` 来分组相关的服务注册：

```swift
// 定义一个装配
struct DatabaseAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.register(DatabaseProtocol.self) {
            DatabaseService(connectionString: "sqlite://app.db")
        }
    }
}

struct NetworkAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.register(NetworkServiceProtocol.self) {
            let logger = env.resolve(LoggerProtocol.self)
            return NetworkService(baseURL: "https://api.example.com", logger: logger)
        }
    }
}

// 装配服务（必须在 @MainActor 上下文中调用）
// 在 SwiftUI 应用中，通常已经在主 actor 上下文中
ServiceEnv.current.assemble(DatabaseAssembly())

// 或一次性装配多个服务
ServiceEnv.current.assemble([
    DatabaseAssembly(),
    NetworkAssembly(),
    RepositoryAssembly()
])

// 如果不在主 actor 上下文中，使用：
await MainActor.run {
    ServiceEnv.current.assemble(DatabaseAssembly())
}
```

**注意：** `ServiceAssembly` 及其 `assemble` 方法标记为 `@MainActor` 以确保线程安全。在 SwiftUI 应用中，通常已经在主 actor 上下文中，因此无需特殊处理。在其他上下文中，使用 `await MainActor.run { }` 来调用 `assemble`。

这提供了一种标准化的、模块化的方式来组织服务注册，类似于 Swinject 的 Assembly 模式。

## API 参考

### ServiceEnv

服务环境，管理服务的注册、解析和生命周期。

```swift
// 预定义环境
ServiceEnv.online  // 生产环境
ServiceEnv.test    // 测试环境
ServiceEnv.dev     // 开发环境

// 创建自定义环境
let testEnv = ServiceEnv(name: "test")

// 切换环境
await ServiceEnv.$current.withValue(.dev) {
    // 使用 dev 环境
}

// 使用工厂函数注册服务
ServiceEnv.current.register(MyService.self) {
    MyService()
}

// 直接注册服务实例
let service = MyService()
ServiceEnv.current.register(service)

// 解析服务
let service = ServiceEnv.current.resolve(MyService.self)

// 注册 MainActor 服务（用于 UI 组件）
await MainActor.run {
    ServiceEnv.current.registerMain(ViewModelService.self) {
        ViewModelService()
    }
}

// 解析 MainActor 服务
@MainActor
func example() {
    let viewModel = ServiceEnv.current.resolveMain(ViewModelService.self)
}

// 重置缓存的服务（保留已注册的提供者）
// 服务将在下次解析时重新创建
// 此方法是异步的，确保所有缓存（包括 MainActor）都已清除
await ServiceEnv.current.resetCaches()

// 重置所有内容（清除缓存并移除所有提供者）
// 调用此方法后，所有服务必须重新注册
await ServiceEnv.current.resetAll()
```

### @Service

属性包装器，用于注入 Sendable 服务。

```swift
struct MyController {
    // 从属性类型推断服务类型
    @Service
    var myService: MyService

    // 显式指定服务类型
    @Service(MyService.self)
    var anotherService: MyService
}
```

### @MainService

属性包装器，用于注入 MainActor 隔离的服务。适用于不遵循 `Sendable` 的 UI 组件，如视图模型和控制器。

```swift
@MainActor
class MyViewController {
    // 从属性类型推断服务类型
    @MainService
    var viewModel: ViewModelService

    // 显式指定服务类型
    @MainService(ViewModelService.self)
    var anotherViewModel: ViewModelService
}
```

### ServiceKey

协议，用于定义服务的默认实现。

```swift
struct MyService: ServiceKey {
    static var `default`: MyService {
        MyService()
    }
}
```

### ServiceAssembly

协议，用于以模块化、可复用的方式组织服务注册。

**为什么使用 `@MainActor`？**

服务装配通常发生在应用初始化阶段，这是应用生命周期的非常早期阶段。装配操作强烈依赖于执行顺序，通常在 `main.swift` 或 SwiftUI App 的 `init` 方法中执行，这些代码已经在主 actor 上运行。将装配操作约束到主 actor 可以确保线程安全，并为服务注册提供可预测的、顺序执行的上下文。

**注意：** `ServiceAssembly` 标记为 `@MainActor` 以确保线程安全。`assemble` 方法必须在主 actor 上下文中调用。

```swift
struct MyAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.register(MyService.self) {
            MyService()
        }
    }
}

// 装配单个服务（必须在 @MainActor 上下文中）
ServiceEnv.current.assemble(MyAssembly())

// 装配多个服务
ServiceEnv.current.assemble([
    DatabaseAssembly(),
    NetworkAssembly()
])

// 或使用可变参数
ServiceEnv.current.assemble(
    DatabaseAssembly(),
    NetworkAssembly()
)

// 如果不在 MainActor 则使用:
await MainActor.run {
    ServiceEnv.current.assemble(MyAssembly())
}
```

## 为什么选择 Service？

Service 专为重视简洁性、安全性和灵活性的现代 Swift 项目而设计。  
它提供了简单直观的 API，无需外部依赖，同时保持类型安全和线程安全。

## 许可证

本项目采用 MIT 许可证。详见 [LICENSE](./LICENSE) 文件。

