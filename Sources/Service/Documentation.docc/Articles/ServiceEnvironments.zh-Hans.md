# 服务环境

Service 支持多个环境，允许你为生产、开发和测试配置不同的服务实现。

> Localization: **[English](https://nslogmeng.github.io/swift-service/documentation/service/serviceenvironments)**  |  **简体中文**

## 预定义环境

Service 提供了三个预定义环境：

```swift
ServiceEnv.online  // 生产环境
ServiceEnv.dev     // 开发环境
ServiceEnv.test    // 测试环境
```

## 使用环境

### 默认环境

默认情况下，Service 使用 `online` 环境：

```swift
// 使用 online 环境
ServiceEnv.current.register(DatabaseProtocol.self) {
    DatabaseService(connectionString: "prod://database")
}
```

### 切换环境

使用 `withValue` 临时切换到不同的环境：

```swift
// 在测试中切换到开发环境
await ServiceEnv.$current.withValue(.dev) {
    // 在此块中解析的所有服务都使用 dev 环境
    let userService = UserService()
    let result = userService.createUser(name: "Test User")
}
```

### 环境特定注册

每个环境维护自己的服务注册表。在适当的环境中注册服务：

```swift
// 注册生产数据库
ServiceEnv.online.register(DatabaseProtocol.self) {
    DatabaseService(connectionString: "prod://database")
}

// 注册开发数据库
ServiceEnv.dev.register(DatabaseProtocol.self) {
    DatabaseService(connectionString: "dev://database")
}

// 注册测试数据库（内存中）
ServiceEnv.test.register(DatabaseProtocol.self) {
    InMemoryDatabase()
}
```

## 实际示例

以下是如何为不同环境设置不同配置的示例：

```swift
// 在应用初始化中
func setupServices() {
    let env = ServiceEnv.current
    
    if ProcessInfo.processInfo.environment["ENVIRONMENT"] == "development" {
        env.register(APIClientProtocol.self) {
            APIClient(baseURL: "https://dev-api.example.com")
        }
    } else {
        env.register(APIClientProtocol.self) {
            APIClient(baseURL: "https://api.example.com")
        }
    }
}
```

## 自定义环境

为特定用例创建自定义环境：

```swift
let stagingEnv = ServiceEnv(name: "staging")

stagingEnv.register(DatabaseProtocol.self) {
    DatabaseService(connectionString: "staging://database")
}
```

## 在测试中使用环境

环境在测试中特别有用：

```swift
func testUserCreation() async throws {
    // 使用测试环境
    await ServiceEnv.$current.withValue(.test) {
        // 注册模拟服务
        ServiceEnv.current.register(DatabaseProtocol.self) {
            MockDatabase()
        }
        
        // 测试你的代码
        let userService = UserService()
        let user = userService.createUser(name: "Test")
        XCTAssertNotNil(user)
    }
}
```

## 环境切换与 Assembly 结构保持

Service 环境的一个关键优势是能够在切换环境的同时保持相同的 Assembly 结构。这在大型项目中特别有价值，因为可以在不同上下文中保持服务注册的组织性和一致性。

### 在最外层作用域切换环境

在测试中，你可以在最外层作用域切换到 `.test` 环境，并保持相同的 Assembly 结构：

```swift
await ServiceEnv.$current.withValue(.test) {
    ServiceEnv.current.assemble([
        AppAssembly()
        // ... 其他 assemblies
    ])

    // 在 .test 环境中运行你的测试逻辑
}
```

这种方法确保了：
- 所有环境使用相同的 Assembly 结构
- 服务注册逻辑保持一致且易于维护
- 环境特定的行为被隔离到环境切换中
- 测试设置简洁明了

### 在 Assembly 中条件性注册

在 Assembly 内部，你可以根据环境条件性地注册服务，同时保持整体结构相同：

```swift
struct AppAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        if env == .test {
            env.register(Localization.self) { MockLocalization() }
        } else {
            env.register(Localization.self) { Localization() }
        }

        // 在所有环境中保持其余部分相同
        env.register(ThemeManager.self) { ThemeManager() }
    }
}
```

这种模式在大型项目中特别有用，因为：
- 你可以保持一致的服务注册结构
- 只有少数服务需要环境特定的实现
- 大多数服务在所有环境中保持不变
- 你需要轻松地在生产和测试配置之间切换

## 线程安全

环境使用 `TaskLocal` 存储，确保跨异步上下文的线程安全访问。每个任务维护自己的环境上下文，使其在并发代码中安全使用。
