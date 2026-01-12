# ``Service``

##
![Service Logo](logo.png)

一个轻量级、零依赖、类型安全的 Swift 依赖注入框架。

> Localization: **[English](https://nslogmeng.github.io/swift-service/documentation/service/)**  |  **简体中文**

## 概述

Service 是一个专为 Swift 应用程序设计的现代依赖注入框架。它利用 Swift 的属性包装器、TaskLocal 和并发原语，为应用程序中的依赖管理提供简单、安全且强大的方式。

使用这个库来管理应用程序的依赖，内置工具满足常见需求：

- **类型安全注入**
    
    使用属性包装器注入服务，具有编译时类型检查，无需手动管理依赖。

- **环境支持**
    
    在生产、开发和测试环境之间切换不同的服务配置。

- **MainActor 支持**
    
    为 UI 组件和视图模型提供专门的 API，与 Swift 的并发模型无缝协作。

- **线程安全**
    
    内置线程安全保证，适用于并发和异步代码。

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
- <doc:CircularDependencies>

### Examples

- <doc:RealWorldExamples>

### Deep Dive

- <doc:UnderstandingService>
- <doc:ConcurrencyModel>
