# ``Service``

##
![Service Logo](logo.png)

一个轻量级、零依赖、类型安全的 Swift 依赖注入框架。

> Localization: **[English](https://nslogmeng.github.io/swift-service/documentation/service/)**  |  **简体中文**

## 概述

Service 是一个专为 Swift 应用程序设计的现代依赖注入框架。它利用 Swift 的属性包装器、TaskLocal 和并发原语，为应用程序中的依赖管理提供简单、安全且强大的方式。

使用这个库来管理应用程序的依赖，内置工具满足常见需求：

- **并发原生 API**

    为 Swift 6 并发模型设计的双轨 API：`register`/`resolve` 用于 Sendable 服务，`registerMain`/`resolveMain` 用于 MainActor 隔离服务。编译器强制确保正确使用。

- **灵活的作用域**

    Singleton、transient、graph 和 custom 命名作用域，提供对服务实例生命周期的精细控制。

- **四种属性包装器**

    `@Service` 和 `@MainService` 用于懒加载缓存注入；`@Provider` 和 `@MainProvider` 用于作用域驱动的解析。全部支持可选类型，优雅处理 nil。

- **环境隔离**

    基于 TaskLocal 的环境切换，支持生产、开发和测试环境 —— 测试可以并行运行而不互相污染。

- **零依赖**

    无外部依赖，占用空间小，适合任何 Swift 项目。

## 用法

三个简单步骤开始使用 Service：

```swift
import Service

// 1. 注册服务
ServiceEnv.current.register(DatabaseProtocol.self) {
    DatabaseService(connectionString: "sqlite://app.db")
}

// 2. 使用属性包装器注入
struct UserRepository {
    @Service
    var database: DatabaseProtocol
    
    func fetchUser(id: String) -> User? {
        return database.findUser(id: id)
    }
}

// 3. 在代码中使用
let repository = UserRepository()
let user = repository.fetchUser(id: "123")
```

## Links

- [GitHub 仓库](https://github.com/nslogmeng/swift-service)
- [安装说明](https://github.com/nslogmeng/swift-service#-installation)

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:BasicUsage>
- <doc:ServiceEnvironments>

### Advanced Topics

- <doc:MainActorServices>
- <doc:ServiceAssembly>
- <doc:ErrorHandling>
- <doc:CircularDependencies>

### Examples

- <doc:RealWorldExamples>

### Deep Dive

- <doc:Vision>
- <doc:UnderstandingService>
- <doc:ConcurrencyModel>
