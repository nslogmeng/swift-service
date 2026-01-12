# 服务装配

Service Assembly 提供了一种标准化、模块化的方式来组织服务注册，类似于 Swinject 的 Assembly 模式。

> Localization: **[English](https://nslogmeng.github.io/swift-service/documentation/service/serviceassembly)**  |  **简体中文**

## 为什么需要 Service Assembly？

随着应用程序的增长，管理服务注册可能会变得复杂。Service Assembly 帮助你：

- **组织注册**：将相关服务分组
- **提高可复用性**：在项目之间共享通用服务配置
- **简化测试**：轻松为不同环境交换装配
- **保持清晰**：将注册逻辑与业务逻辑分离

## 创建装配

通过遵循 `ServiceAssembly` 协议定义装配：

```swift
struct DatabaseAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.register(DatabaseProtocol.self) {
            DatabaseService(connectionString: "sqlite://app.db")
        }
    }
}
```

## 装配服务

### 单个装配

装配单个装配：

```swift
ServiceEnv.current.assemble(DatabaseAssembly())
```

### 多个装配

一次性装配多个装配：

```swift
ServiceEnv.current.assemble([
    DatabaseAssembly(),
    NetworkAssembly(),
    RepositoryAssembly()
])
```

或使用可变参数：

```swift
ServiceEnv.current.assemble(
    DatabaseAssembly(),
    NetworkAssembly(),
    RepositoryAssembly()
)
```

## 实际示例

以下是如何在实际应用中组织服务的示例：

```swift
// 数据库装配
struct DatabaseAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.register(DatabaseProtocol.self) {
            DatabaseService(connectionString: "sqlite://app.db")
        }
    }
}

// 网络装配
struct NetworkAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.register(APIClientProtocol.self) {
            let logger = env.resolve(LoggerProtocol.self)
            return APIClient(baseURL: "https://api.example.com", logger: logger)
        }
    }
}

// 仓库装配
struct RepositoryAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.register(UserRepositoryProtocol.self) {
            let database = env.resolve(DatabaseProtocol.self)
            let logger = env.resolve(LoggerProtocol.self)
            return UserRepository(database: database, logger: logger)
        }
    }
}

// 日志装配
struct LoggerAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.register(LoggerProtocol.self) {
            LoggerService(logLevel: .info)
        }
    }
}

// 应用初始化
@main
struct MyApp: App {
    init() {
        ServiceEnv.current.assemble(
            LoggerAssembly(),      // 首先注册（其他服务依赖它）
            DatabaseAssembly(),
            NetworkAssembly(),
            RepositoryAssembly()
        )
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

## 环境特定装配

你可以为不同环境创建不同的装配：

```swift
// 生产装配
struct ProductionDatabaseAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.register(DatabaseProtocol.self) {
            DatabaseService(connectionString: "prod://database")
        }
    }
}

// 开发装配
struct DevelopmentDatabaseAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.register(DatabaseProtocol.self) {
            DatabaseService(connectionString: "dev://database")
        }
    }
}

// 测试装配
struct TestDatabaseAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.register(DatabaseProtocol.self) {
            InMemoryDatabase()
        }
    }
}

// 在应用中使用
func setupServices() {
    let env = ServiceEnv.current
    
    if ProcessInfo.processInfo.environment["ENVIRONMENT"] == "test" {
        env.assemble(TestDatabaseAssembly())
    } else if ProcessInfo.processInfo.environment["ENVIRONMENT"] == "development" {
        env.assemble(DevelopmentDatabaseAssembly())
    } else {
        env.assemble(ProductionDatabaseAssembly())
    }
}
```

## 装配中的 MainActor 服务

你可以在装配中注册 MainActor 服务，但请记住 `assemble` 必须从 `@MainActor` 上下文调用：

```swift
struct ViewModelAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        // 注册常规服务
        env.register(APIClientProtocol.self) {
            APIClient(baseURL: "https://api.example.com")
        }
        
        // 注册 MainActor 服务
        env.registerMain(UserViewModel.self) {
            let apiClient = env.resolve(APIClientProtocol.self)
            return UserViewModel(apiClient: apiClient)
        }
    }
}

// 在 SwiftUI App 中（已经在 @MainActor 上）
@main
struct MyApp: App {
    init() {
        ServiceEnv.current.assemble(ViewModelAssembly())
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

## 为什么使用 @MainActor？

Service Assembly 标记为 `@MainActor` 以确保线程安全。服务装配通常发生在应用初始化阶段，这是应用生命周期的非常早期阶段。装配操作强烈依赖于执行顺序，通常在 `main.swift` 或 SwiftUI App 的 `init` 方法中执行，这些代码已经在主 actor 上运行。将装配操作约束到主 actor 可以确保线程安全，并为服务注册提供可预测的、顺序执行的上下文。

### 从非 MainActor 上下文调用

如果你需要从非 `@MainActor` 上下文调用 `assemble`，使用 `await MainActor.run`：

```swift
await MainActor.run {
    ServiceEnv.current.assemble(DatabaseAssembly())
}
```

## 最佳实践

1. **顺序很重要**：按依赖顺序注册服务。其他服务依赖的服务应该首先注册。

2. **按域分组**：创建将相关服务分组的装配（例如，`DatabaseAssembly`、`NetworkAssembly`）。

3. **保持装配专注**：每个装配应该有一个单一职责。

4. **用于可复用性**：如果你有跨多个项目使用的通用服务配置，装配使共享变得容易。

## 下一步

- 探索 <doc:RealWorldExamples> 了解更多装配模式
- 学习 <doc:ServiceEnvironments> 了解基于环境的配置
- 阅读 <doc:UnderstandingService> 深入了解 Service 的架构
