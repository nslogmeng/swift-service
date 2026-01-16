# 重置服务

Service 提供了两个方法来重置服务状态：`resetCaches()` 和 `resetAll()`。这些方法在测试场景中以及当你需要清除服务实例或完全重置服务环境时非常重要。

> Localization: **[English](https://nslogmeng.github.io/swift-service/documentation/service/resettingservices)**  |  **简体中文**

## 概述

`resetCaches()` 和 `resetAll()` 都是异步方法，确保正确清理 Sendable 和 MainActor 服务。关键区别是：

- **`resetCaches()`**：清除缓存的服务实例，但保留已注册的提供者
- **`resetAll()`**：清除缓存实例和已注册的提供者

## resetCaches()

`resetCaches()` 方法清除所有缓存的服务实例（包括 Sendable 和 MainActor 服务），同时保留已注册的服务提供者。这意味着服务将在下次解析时使用其已注册的工厂函数重新创建。

### 何时使用

在以下情况下使用 `resetCaches()`：
- 强制重新创建服务而无需重新注册
- 在测试场景中获取新实例
- 清除缓存状态同时保持服务注册

### 示例

```swift
// 注册服务
ServiceEnv.current.register(String.self) {
    UUID().uuidString
}

// 解析并缓存服务
let service1 = ServiceEnv.current.resolve(String.self)
print(service1) // 例如："550e8400-e29b-41d4-a716-446655440000"

// 清除缓存 - 下次解析将创建新实例
await ServiceEnv.current.resetCaches()
let service2 = ServiceEnv.current.resolve(String.self)
print(service2) // 不同的 UUID："6ba7b810-9dad-11d1-80b4-00c04fd430c8"

// service1 != service2（创建了新实例）
```

### 测试示例

```swift
func testServiceRecreation() async {
    // 注册一个跟踪创建次数的服务
    var creationCount = 0
    ServiceEnv.current.register(CounterService.self) {
        creationCount += 1
        return CounterService(id: creationCount)
    }
    
    // 第一次解析创建并缓存服务
    let service1 = ServiceEnv.current.resolve(CounterService.self)
    XCTAssertEqual(service1.id, 1)
    
    // 第二次解析返回缓存的实例
    let service2 = ServiceEnv.current.resolve(CounterService.self)
    XCTAssertEqual(service2.id, 1) // 相同实例
    
    // 清除缓存
    await ServiceEnv.current.resetCaches()
    
    // 第三次解析创建新实例
    let service3 = ServiceEnv.current.resolve(CounterService.self)
    XCTAssertEqual(service3.id, 2) // 新实例
}
```

## resetAll()

`resetAll()` 方法清除所有缓存的服务实例并移除所有已注册的服务提供者（包括 Sendable 和 MainActor 服务）。这将完全重置服务环境到初始状态。

### 何时使用

在以下情况下使用 `resetAll()`：
- 完全重置服务环境
- 在测试中从干净的状态开始
- 移除所有服务注册和实例

### 重要提示

调用 `resetAll()` 后，所有服务必须重新注册才能被解析。尝试解析未重新注册的服务将导致致命错误。

### 示例

```swift
// 注册服务
ServiceEnv.current.register(DatabaseProtocol.self) {
    DatabaseService(connectionString: "sqlite://app.db")
}

ServiceEnv.current.register(APIClientProtocol.self) {
    APIClient(baseURL: "https://api.example.com")
}

// 使用服务
let db = ServiceEnv.current.resolve(DatabaseProtocol.self)
let api = ServiceEnv.current.resolve(APIClientProtocol.self)

// 重置所有内容
await ServiceEnv.current.resetAll()

// 服务必须重新注册
ServiceEnv.current.register(DatabaseProtocol.self) {
    DatabaseService(connectionString: "sqlite://app.db")
}

// 现在可以再次解析服务
let newDb = ServiceEnv.current.resolve(DatabaseProtocol.self)
```

### 测试示例

```swift
func testCleanEnvironment() async {
    // 在第一个测试中注册服务
    ServiceEnv.current.register(MockDatabase.self) {
        MockDatabase()
    }
    
    let db1 = ServiceEnv.current.resolve(MockDatabase.self)
    XCTAssertNotNil(db1)
    
    // 为下一个测试完全重置
    await ServiceEnv.current.resetAll()
    
    // 之前的注册已消失
    // 需要为此测试重新注册
    ServiceEnv.current.register(MockDatabase.self) {
        MockDatabase()
    }
    
    let db2 = ServiceEnv.current.resolve(MockDatabase.self)
    XCTAssertNotNil(db2)
    // db2 是一个全新的实例
}
```

## 对比

| 特性 | `resetCaches()` | `resetAll()` |
|------|----------------|-------------|
| 清除缓存实例 | ✅ | ✅ |
| 移除已注册的提供者 | ❌ | ✅ |
| 服务需要重新注册 | ❌ | ✅ |
| 使用场景 | 获取新实例 | 完全重置 |
| 典型场景 | 使用相同设置的测试 | 干净的测试环境 |

## MainActor 服务

两种方法都能正确处理 MainActor 服务：

```swift
@MainActor
func testMainActorServiceReset() async {
    // 注册 MainActor 服务
    ServiceEnv.current.registerMain(ViewModelService.self) {
        ViewModelService()
    }
    
    let viewModel1 = ServiceEnv.current.resolveMain(ViewModelService.self)
    
    // 清除缓存 - 也适用于 MainActor 服务
    await ServiceEnv.current.resetCaches()
    
    let viewModel2 = ServiceEnv.current.resolveMain(ViewModelService.self)
    // viewModel2 是新实例
}
```

## 最佳实践

1. **在测试中使用 `resetCaches()`** 当你想要新实例但保持相同的服务设置时
2. **在测试中使用 `resetAll()`** 当你在测试用例之间需要完全干净的环境时
3. **始终 await** 这些方法，因为它们是异步的
4. **在 `resetAll()` 后重新注册服务** 在解析它们之前
5. **在测试类的 `setUp()` 或 `tearDown()` 方法中使用** 以确保干净的状态

## 线程安全

两种方法都是线程安全的，并正确处理并发访问：
- Sendable 服务使用线程安全操作清除
- MainActor 服务在主线程上清除
- 异步特性确保所有清理在方法返回前完成
