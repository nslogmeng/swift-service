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
    <a href="./README.md"><strong>English</strong></a> | <strong>简体中文</strong>
</div>
<br/>

一个轻量级、零依赖、类型安全的 Swift 依赖注入框架。  
受 [Swinject](https://github.com/Swinject/Swinject) 和 [swift-dependencies](https://github.com/pointfreeco/swift-dependencies) 启发，Service 利用现代 Swift 特性实现简单、健壮的依赖注入。

## ✨ 特性

- **🚀 现代 Swift**：使用属性包装器、TaskLocal 和并发原语
- **📦 零依赖**：无第三方依赖，占用空间小
- **🎯 类型安全**：编译时检查服务注册和解析
- **🔒 线程安全**：适用于并发和异步代码
- **🌍 环境支持**：可在生产、开发和测试环境之间切换
- **🎨 MainActor 支持**：为 UI 组件和视图模型提供专门的 API
- **🔍 循环依赖检测**：自动检测并提供清晰的错误信息

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

### 注册和注入

```swift
import Service

// 注册服务
ServiceEnv.current.register(DatabaseProtocol.self) {
    DatabaseService(connectionString: "sqlite://app.db")
}

// 使用 @Service 属性包装器
struct UserRepository {
    @Service
    var database: DatabaseProtocol
    
    func fetchUser(id: String) -> User? {
        return database.findUser(id: id)
    }
}
```

### MainActor 服务（UI 组件）

```swift
// 注册 MainActor 服务
await MainActor.run {
    ServiceEnv.current.registerMain(UserViewModel.self) {
        UserViewModel()
    }
}

// 在视图中使用 @MainService
@MainActor
class UserViewController {
    @MainService
    var viewModel: UserViewModel
}
```

### 环境切换

```swift
// 切换到测试环境
await ServiceEnv.$current.withValue(.test) {
    // 所有服务都使用测试环境
    let service = ServiceEnv.current.resolve(MyService.self)
}
```

## 📚 文档

完整的文档、教程和示例，请参阅 [Service 文档](https://swiftpackageindex.com/nslogmeng/swift-service/documentation/service)。

### 主题

- **[快速开始](https://swiftpackageindex.com/nslogmeng/swift-service/documentation/service/gettingstarted)** - 快速设置指南
- **[基本用法](https://swiftpackageindex.com/nslogmeng/swift-service/documentation/service/basicusage)** - 核心模式和示例
- **[MainActor 服务](https://swiftpackageindex.com/nslogmeng/swift-service/documentation/service/mainactorservices)** - 使用 UI 组件
- **[服务装配](https://swiftpackageindex.com/nslogmeng/swift-service/documentation/service/serviceassembly)** - 组织服务注册
- **[实际示例](https://swiftpackageindex.com/nslogmeng/swift-service/documentation/service/realworldexamples)** - 实用用例
- **[理解 Service](https://swiftpackageindex.com/nslogmeng/swift-service/documentation/service/understandingservice)** - 深入架构

## 💡 为什么选择 Service？

Service 专为重视以下特性的现代 Swift 项目而设计：

- **简洁性**：清晰直观的 API，易于学习和使用
- **安全性**：设计上类型安全和线程安全
- **灵活性**：支持 Sendable 和 MainActor 服务
- **零开销**：无外部依赖，运行时成本最小

非常适合 SwiftUI 应用、服务端 Swift 以及任何需要依赖注入的 Swift 项目。

## 📄 许可证

本项目采用 MIT 许可证。详见 [LICENSE](./LICENSE) 文件。
