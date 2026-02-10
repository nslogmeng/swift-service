# ServiceAssembly

`ServiceAssembly` 提供了一种标准化、模块化的方式来组织服务注册，类似于 Swinject 的 Assembly 模式。

> Localization: **[English](https://nslogmeng.github.io/swift-service/documentation/service/serviceassembly)**  |  **简体中文**

## 为什么需要 Service Assembly？

随着应用程序的增长，管理服务注册可能会变得复杂。Service Assembly 帮助你：

- **组织注册**：将相关服务分组
- **提高可复用性**：在项目之间共享通用服务配置
- **简化测试**：轻松为不同环境切换 Assembly 服务
- **保持清晰**：将注册逻辑与业务逻辑分离

## 创建 Assembly

通过遵循 `ServiceAssembly` 协议定义 Assembly：

```swift
struct DatabaseAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.register(DatabaseProtocol.self) {
            DatabaseService(connectionString: "sqlite://app.db")
        }
    }
}
```

### 在 Assembly 中使用作用域

注册服务时可以指定作用域来控制实例的生命周期：

```swift
struct ServiceLayerAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        // Singleton（默认）— 全应用共享
        env.register(DatabaseProtocol.self) {
            DatabaseService(connectionString: "sqlite://app.db")
        }

        // Transient — 每次获取新实例
        env.register(RequestHandler.self, scope: .transient) {
            RequestHandler()
        }

        // Graph — 在同一解析链内共享
        env.register(UnitOfWork.self, scope: .graph) {
            UnitOfWork()
        }

        // Custom — 命名作用域，可定向清除
        env.register(SessionService.self, scope: .custom("user-session")) {
            SessionService()
        }
    }
}
```

## Service Assembly

### 单个 Assembly

```swift
ServiceEnv.current.assemble(DatabaseAssembly())
```

### 组织多个 Assembly

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
// 数据库 Assembly
struct DatabaseAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.register(DatabaseProtocol.self) {
            DatabaseService(connectionString: "sqlite://app.db")
        }
    }
}

// 网络 Assembly
struct NetworkAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.register(APIClientProtocol.self) {
            let logger = env.resolve(LoggerProtocol.self)
            return APIClient(baseURL: "https://api.example.com", logger: logger)
        }
    }
}

// Repo Assembly
struct RepositoryAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.register(UserRepositoryProtocol.self) {
            let database = env.resolve(DatabaseProtocol.self)
            let logger = env.resolve(LoggerProtocol.self)
            return UserRepository(database: database, logger: logger)
        }
    }
}

// 日志 Assembly
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

## 环境特定 Assembly

你可以为不同环境创建不同的 `ServiceAssembly`：

```swift
// 生产环境 ServiceAssembly
struct ProductionDatabaseAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.register(DatabaseProtocol.self) {
            DatabaseService(connectionString: "prod://database")
        }
    }
}

// 开发环境 ServiceAssembly
struct DevelopmentDatabaseAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.register(DatabaseProtocol.self) {
            DatabaseService(connectionString: "dev://database")
        }
    }
}

// 测试环境 ServiceAssembly
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

## ServiceAssembly 中的 MainActor

你可以在 ServiceAssembly 中注册 MainActor 服务，但请记住 `assemble` 必须从 `@MainActor` 上下文调用：

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

`ServiceAssembly` 标记为 `@MainActor` 以确保 thread-safe。Assembly 通常发生在应用初始化阶段，这是应用生命周期的非常早期阶段。Assemble 操作强烈依赖于执行顺序，通常在 `main.swift` 或 SwiftUI App 的 `init` 方法中执行，这些代码已经在 MainActor 上运行。将 Assembly 操作约束到 MainActor 可以确保线程安全，并为服务注册提供可预测的、顺序执行的上下文。

### 从非 MainActor 上下文调用

如果你需要从非 `@MainActor` 上下文调用 `assemble`，使用 `await MainActor.run`：

```swift
await MainActor.run {
    ServiceEnv.current.assemble(DatabaseAssembly())
}
```

## 最佳实践

1. **顺序很重要**：按依赖顺序注册服务。其他服务依赖的服务应该首先注册。

2. **按域分组**：创建将相关服务分组的 Assemble（例如，`DatabaseAssembly`、`NetworkAssembly`）。

3. **保持 Assembly 专注**：每个 Assemble 应该有一个单一职责。

4. **用于可复用性**：如果你有跨多个项目使用的通用服务配置，Assembly 使共享变得容易。

## 下一步

- 探索 <doc:RealWorldExamples> 了解更多 Assembly 模式
- 学习 <doc:ServiceEnvironments> 了解基于环境的配置
- 阅读 <doc:UnderstandingService> 深入了解 Service 的架构
