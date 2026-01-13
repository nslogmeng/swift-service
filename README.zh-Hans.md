<div align="center">
  <img src="./images/logo.png" alt="Service Logo" >
</div>

# Service

[![GitHub License](https://img.shields.io/github/license/nslogmeng/swift-service)](./LICENSE)
[![Swift Version Status](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fnslogmeng%2Fswift-service%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/nslogmeng/swift-service)
[![Platform Support Status](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fnslogmeng%2Fswift-service%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/nslogmeng/swift-service)
[![Build Status](https://github.com/nslogmeng/swift-service/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/nslogmeng/swift-service/actions/workflows/build.yml)
[![Test Status](https://github.com/nslogmeng/swift-service/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/nslogmeng/swift-service/actions/workflows/test.yml)
[![中文文档](https://img.shields.io/badge/中文文档-available-blue)](https://nslogmeng.github.io/swift-service/zh-Hans/documentation/service/?utm_source=github&utm_medium=referral&utm_campaign=service-github&utm_content=readme-badge)

<div align="center">
    <a href="./README.md"><strong>English</strong></a> | <strong>简体中文</strong>
</div>
<br/>

一个专为现代 Swift 项目设计的轻量级、零依赖、类型安全的依赖注入框架。  
受 [Swinject](https://github.com/Swinject/Swinject) 和 [swift-dependencies](https://github.com/pointfreeco/swift-dependencies) 启发，Service 利用现代 Swift 特性实现简单、健壮的依赖注入。**上手成本极低**，使用熟悉的 register/resolve 模式，通过 property wrapper 实现优雅的依赖注入。

## ✨ 核心特性

- **🚀 现代 Swift**：使用属性包装器、TaskLocal 和并发原语，充分利用 Swift 现代特性
- **🎯 极简 API，上手即用**：使用 `@Service` 属性包装器，无需手动传递依赖，代码更简洁
- **📦 零依赖，轻量级**：无第三方依赖，不增加项目负担，适合任何 Swift 项目
- **🔒 类型安全，编译时检查**：充分利用 Swift 类型系统，在编译时捕获错误
- **⚡ 线程安全，并发友好**：内置线程安全保证，完美支持 Swift 6 并发模型
- **🌍 环境隔离，测试无忧**：基于 TaskLocal 的任务级环境切换，测试时轻松切换依赖
- **🎨 MainActor 专门支持**：为 SwiftUI 视图模型和 UI 组件提供专门的 `@MainService` API
- **🔍 循环依赖自动检测**：运行时自动检测循环依赖，提供清晰的错误信息
- **🧩 模块化 Assembly**：通过 ServiceAssembly 模式组织服务注册，代码结构更清晰

## 📦 安装

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

## 🚀 快速开始

只需三步，即可开始使用 Service：

### 1. 注册服务

```swift
import Service

// 注册服务（支持协议和具体类型）
ServiceEnv.current.register(DatabaseProtocol.self) {
    DatabaseService(connectionString: "sqlite://app.db")
}
```

### 2. 注入依赖

使用 `@Service` 属性包装器，自动解析依赖：

```swift
struct UserRepository {
    @Service
    var database: DatabaseProtocol
    
    func fetchUser(id: String) -> User? {
        return database.findUser(id: id)
    }
}
```

### 3. 使用服务

```swift
let repository = UserRepository()
let user = repository.fetchUser(id: "123")
// database 已自动注入，无需手动传递！
```

### 🎨 SwiftUI 视图模型支持

```swift
// 注册 MainActor 服务
ServiceEnv.current.registerMain(UserViewModel.self) {
    UserViewModel()
}

// 在视图中使用 @MainService
struct UserView: View {
    @MainService
    var viewModel: UserViewModel
    
    var body: some View {
        Text(viewModel.userName)
    }
}
```

### 🧪 测试环境切换

```swift
// 在测试中切换到测试环境
await ServiceEnv.$current.withValue(.test) {
    // 注册测试用的模拟服务
    ServiceEnv.current.register(DatabaseProtocol.self) {
        MockDatabase()
    }
    
    // 所有服务解析都使用测试环境
    let repository = UserRepository()
    // 使用模拟数据库进行测试...
}
```

## 📚 文档

完整的文档、教程和示例，请参阅 [Service 文档](https://nslogmeng.github.io/swift-service/zh-Hans/documentation/service/?utm_source=github&utm_medium=referral&utm_campaign=service-github&utm_content=readme-docs).

### 主题

#### 基础

- **[快速开始](https://nslogmeng.github.io/swift-service/zh-Hans/documentation/service/gettingstarted/?utm_source=github&utm_medium=referral&utm_campaign=service-github&utm_content=readme-docs)** - 快速设置指南
- **[基本用法](https://nslogmeng.github.io/swift-service/zh-Hans/documentation/service/basicusage/?utm_source=github&utm_medium=referral&utm_campaign=service-github&utm_content=readme-docs)** - 核心模式和示例
- **[服务环境](https://nslogmeng.github.io/swift-service/zh-Hans/documentation/service/serviceenvironments/?utm_source=github&utm_medium=referral&utm_campaign=service-github&utm_content=readme-docs)** - 管理不同的服务配置

#### 高级主题

- **[MainActor 服务](https://nslogmeng.github.io/swift-service/zh-Hans/documentation/service/mainactorservices/?utm_source=github&utm_medium=referral&utm_campaign=service-github&utm_content=readme-docs)** - 使用 UI 组件
- **[服务装配](https://nslogmeng.github.io/swift-service/zh-Hans/documentation/service/serviceassembly/?utm_source=github&utm_medium=referral&utm_campaign=service-github&utm_content=readme-docs)** - 组织服务注册
- **[循环依赖](https://nslogmeng.github.io/swift-service/zh-Hans/documentation/service/circulardependencies/?utm_source=github&utm_medium=referral&utm_campaign=service-github&utm_content=readme-docs)** - 理解和避免循环依赖

#### 示例

- **[实际示例](https://nslogmeng.github.io/swift-service/zh-Hans/documentation/service/realworldexamples/?utm_source=github&utm_medium=referral&utm_campaign=service-github&utm_content=readme-docs)** - 实用用例

#### 深入理解

- **[理解 Service](https://nslogmeng.github.io/swift-service/zh-Hans/documentation/service/understandingservice/?utm_source=github&utm_medium=referral&utm_campaign=service-github&utm_content=readme-docs)** - 深入架构
- **[并发模型](https://nslogmeng.github.io/swift-service/zh-Hans/documentation/service/concurrencymodel/?utm_source=github&utm_medium=referral&utm_campaign=service-github&utm_content=readme-docs)** - 理解 Service 的并发模型

## 💡 为什么选择 Service？

### 🎯 上手成本极低

如果你熟悉传统的依赖注入模式（如 Swinject），Service 的使用方式会让你感到非常熟悉。通过属性包装器，你甚至不需要手动传递依赖：

```swift
// 传统方式：需要手动传递依赖
class UserService {
    init(database: DatabaseProtocol, logger: LoggerProtocol) { ... }
}
let service = UserService(database: db, logger: logger)

// Service 方式：自动注入，代码更简洁
class UserService {
    @Service var database: DatabaseProtocol
    @Service var logger: LoggerProtocol
}
let service = UserService()  // 依赖已自动注入！
```

### 🚀 专为现代 Swift 设计

- **Swift 6 并发模型**：完美支持 `Sendable` 和 `@MainActor`，提供专门的 API 处理 UI 服务
- **TaskLocal 环境隔离**：基于任务的环境切换，测试时无需修改全局状态
- **属性包装器**：利用 Swift 现代特性，提供优雅的依赖注入体验

### 🛡️ 安全可靠

- **编译时类型检查**：充分利用 Swift 类型系统，在编译时捕获错误
- **线程安全保证**：内置锁机制，支持并发访问
- **循环依赖检测**：运行时自动检测并报告循环依赖

### 📦 轻量级，零负担

- **零依赖**：不依赖任何第三方库，不会增加项目复杂度
- **最小运行时成本**：高效的实现，对应用性能影响极小
- **广泛适用**：适合 SwiftUI 应用、服务端 Swift、命令行工具等任何 Swift 项目

### 🧩 灵活强大

- **多种注册方式**：支持工厂函数、直接实例、ServiceKey 协议
- **模块化 Assembly**：通过 ServiceAssembly 组织服务注册，代码结构清晰
- **环境隔离**：生产、开发、测试环境完全隔离，互不干扰

## 📄 许可证

本项目采用 MIT 许可证。详见 [LICENSE](./LICENSE) 文件。
