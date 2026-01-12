# 快速开始

几分钟内开始使用 Service。

> Localization: **[English](https://nslogmeng.github.io/swift-service/documentation/service/gettingstarted)**  |  **简体中文**

## 安装

在 `Package.swift` 中添加 Service：

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

### 步骤 1：注册服务

使用工厂函数注册服务：

```swift
import Service

// 注册数据库服务
ServiceEnv.current.register(DatabaseProtocol.self) {
    DatabaseService(connectionString: "sqlite://app.db")
}
```

### 步骤 2：注入和使用

使用 `@Service` 属性包装器注入服务：

```swift
struct UserManager {
    @Service
    var database: DatabaseProtocol
    
    func createUser(name: String) {
        // 使用注入的数据库服务
        database.saveUser(name: name)
    }
}
```

完成！你现在可以在应用程序中使用 Service 了。

## 下一步

- 学习 <doc:BasicUsage> 了解更多注册模式
- 探索 <doc:ServiceEnvironments> 了解基于环境的配置
- 查看 <doc:RealWorldExamples> 获取实用示例
