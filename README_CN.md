# Service

[![Swift Version](https://img.shields.io/badge/Swift-6.0-F16D39.svg?style=flat)](https://developer.apple.com/swift)
[![GitHub License](https://img.shields.io/github/license/nslogmeng/swift-service)](./LICENSE)
[![Build Status](https://github.com/nslogmeng/swift-service/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/nslogmeng/swift-service/actions/workflows/build.yml)
[![Test Status](https://github.com/nslogmeng/swift-service/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/nslogmeng/swift-service/actions/workflows/test.yml)

[English](./README.md) | [中文](./README_CN.md)

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
    .package(url: "https://github.com/nslogmeng/swift-service", from: "0.1.2")
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
    let database = ServiceEnv.current[DatabaseProtocol.self]
    let logger = ServiceEnv.current[LoggerProtocol.self]
    return UserRepository(database: database, logger: logger)
}
```

## API 参考

### ServiceEnv

服务环境，管理服务的注册、解析和生命周期。

```swift
// 预定义环境
ServiceEnv.online  // 生产环境
ServiceEnv.dev     // 开发环境
ServiceEnv.inhouse // 内部测试环境

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
let service = ServiceEnv.current[MyService.self]

// 重置所有缓存的服务
ServiceEnv.current.reset()
```

### @Service

属性包装器，用于注入服务。

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

### ServiceKey

协议，用于定义服务的默认实现。

```swift
struct MyService: ServiceKey {
    static var `default`: MyService {
        MyService()
    }
}
```

## 为什么选择 Service？

Service 专为重视简洁性、安全性和灵活性的现代 Swift 项目而设计。  
它提供了简单直观的 API，无需外部依赖，同时保持类型安全和线程安全。

## 许可证

本项目采用 MIT 许可证。详见 [LICENSE](./LICENSE) 文件。

