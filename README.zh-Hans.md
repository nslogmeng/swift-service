<div align="center">
  <img src="./images/logo.png" alt="Service Logo">
</div>

# Service

[![Swift Version Status](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fnslogmeng%2Fswift-service%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/nslogmeng/swift-service)
[![Platform Support Status](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fnslogmeng%2Fswift-service%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/nslogmeng/swift-service)
[![Build Status](https://github.com/nslogmeng/swift-service/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/nslogmeng/swift-service/actions/workflows/build.yml)
[![Test Status](https://github.com/nslogmeng/swift-service/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/nslogmeng/swift-service/actions/workflows/test.yml)
[![中文文档](https://img.shields.io/badge/中文文档-available-blue)](https://nslogmeng.github.io/swift-service/zh-Hans/documentation/service/?utm_source=github&utm_medium=referral&utm_campaign=service-github&utm_content=readme-badge)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/nslogmeng/swift-service)

<div align="center">
    <a href="./README.md"><strong>English</strong></a> | <strong>简体中文</strong>
</div>
<br/>

一个为 Swift 6 并发模型而生的轻量级依赖注入框架——提供显式的 Sendable 和 MainActor API、零外部依赖、基于 TaskLocal 的环境隔离。

## 核心特性

- **并发优先设计** — Swift 并发是一等公民。Sendable 和 MainActor 约束直接体现在 API 中，由编译器在每个调用点强制执行——无需 `@unchecked Sendable` 妥协。
- **原生 MainActor 支持** — 为 MainActor 隔离类型提供专属的 `registerMain()` / `@MainService` / `@MainProvider`。契合 Swift 6.2 Approachable Concurrency 的方向。
- **零依赖** — 完全基于 Swift 标准库原语（`Synchronization.Mutex`、`@TaskLocal`）构建。
- **TaskLocal 环境隔离** — 任务级环境切换，支持并行安全的测试。无需修改全局状态。
- **灵活的作用域** — singleton、transient、graph 和自定义命名作用域，精细控制实例生命周期。
- **熟悉的模式** — 受 Swinject 启发的 register/resolve API。属性包装器注入，模块化 Assembly 支持。

## 快速开始

### 1. 注册服务

```swift
import Service

// Sendable 服务——跨线程安全
ServiceEnv.current.register(DatabaseProtocol.self) {
    DatabaseService(connectionString: "sqlite://app.db")
}

// MainActor 服务——用于 UI 组件，无需 @unchecked Sendable
ServiceEnv.current.registerMain(UserViewModel.self) {
    UserViewModel()
}
```

### 2. 注入依赖

```swift
struct UserRepository {
    @Service var database: DatabaseProtocol

    func fetchUser(id: String) -> User? {
        return database.findUser(id: id)
    }
}

@MainActor
struct UserView: View {
    @MainService var viewModel: UserViewModel

    var body: some View {
        Text(viewModel.userName)
    }
}
```

### 3. 使用服务

```swift
let repository = UserRepository()
let user = repository.fetchUser(id: "123")
// database 已自动注入，无需手动传递！
```

### 测试环境切换

```swift
await ServiceEnv.$current.withValue(.test) {
    ServiceEnv.current.register(DatabaseProtocol.self) {
        MockDatabase()
    }

    let repository = UserRepository()
    // 所有解析都使用测试环境
}
```

## 服务作用域

控制服务实例的创建和缓存方式：

```swift
// Singleton（默认）——全局复用同一实例
env.register(DatabaseService.self) { DatabaseService() }

// Transient——每次解析创建新实例
env.register(RequestHandler.self, scope: .transient) { RequestHandler() }

// Graph——同一解析链内共享实例
env.register(UnitOfWork.self, scope: .graph) { UnitOfWork() }

// Custom——命名作用域，可定向清除
env.register(SessionService.self, scope: .custom("user-session")) { SessionService() }
env.resetScope(.custom("user-session"))  // 仅清除该作用域
```

### 属性包装器

Service 提供四个属性包装器，构成 2x2 矩阵：

|  | **Sendable** | **MainActor** |
|---|---|---|
| **懒加载 + 缓存** | `@Service` | `@MainService` |
| **作用域驱动** | `@Provider` | `@MainProvider` |

- **`@Service` / `@MainService`**：首次访问时解析，结果缓存在内部。
- **`@Provider` / `@MainProvider`**：每次访问时解析，缓存行为由注册的 scope 决定。

```swift
@Provider var handler: RequestHandler   // transient → 每次访问新实例
@Service var database: DatabaseProtocol // singleton → 解析一次，缓存复用
```

四个包装器均支持可选类型——未注册时返回 `nil` 而非崩溃：

```swift
@Service var analytics: AnalyticsService?
@Provider var tracker: TrackingService?
```

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

## 文档

完整的使用指南、教程和 API 参考，请查阅 [Service 文档](https://nslogmeng.github.io/swift-service/zh-Hans/documentation/service/?utm_source=github&utm_medium=referral&utm_campaign=service-github&utm_content=readme-docs)。

## 为什么选择 Service？

```swift
// 传统方式：手动传递每个依赖
class UserService {
    init(database: DatabaseProtocol, logger: LoggerProtocol) { ... }
}
let service = UserService(database: db, logger: logger)

// Service 方式：自动注入
class UserService {
    @Service var database: DatabaseProtocol
    @Service var logger: LoggerProtocol
}
let service = UserService()  // 依赖已自动注入！
```

Service 使用传统 DI 容器中开发者熟悉的 register/resolve 模式。核心区别在于：并发约束是 API 的一部分，而非隐藏在 `@unchecked Sendable` 背后。使用 `register()` 注册时，服务必须是 `Sendable` 的；使用 `registerMain()` 注册时，服务运行在主线程上。编译器在每个调用点强制执行这些约束——在构建时而非运行时捕获线程错误。

## 致谢

Service 的设计受到了 [Swinject](https://github.com/Swinject/Swinject) 和 [swift-dependencies](https://github.com/pointfreeco/swift-dependencies) 的启发。

## 许可证

本项目采用 MIT 许可证。详见 [LICENSE](./LICENSE) 文件。
