# 循环依赖

Service 会在运行时自动检测循环依赖，并提供清晰的错误信息帮助你识别和修复依赖循环。

> Localization: **[English](https://nslogmeng.github.io/swift-service/documentation/service/circulardependencies)**  |  **简体中文**

## 什么是循环依赖？

循环依赖发生在服务以循环方式相互依赖时。例如：

- 服务 A 依赖服务 B
- 服务 B 依赖服务 C
- 服务 C 依赖服务 A

这创建了一个循环：A → B → C → A

## Service 如何检测循环

在解析服务时，Service 会追踪当前的解析链。如果一个服务尝试解析自身（直接或间接），则会检测到循环依赖，程序会终止并显示描述性错误。

### 循环依赖示例

```swift
// 服务 A 依赖 B
ServiceEnv.current.register(AService.self) {
    let b = ServiceEnv.current.resolve(BService.self)  // 解析 B
    return AService(b: b)
}

// 服务 B 依赖 C
ServiceEnv.current.register(BService.self) {
    let c = ServiceEnv.current.resolve(CService.self)  // 解析 C
    return BService(c: c)
}

// 服务 C 依赖 A（创建循环！）
ServiceEnv.current.register(CService.self) {
    let a = ServiceEnv.current.resolve(AService.self)  // 检测到循环！
    return CService(a: a)
}

// 当解析 AService 时，检测到循环：
let service = ServiceEnv.current.resolve(AService.self)
// 致命错误：检测到循环依赖
```

## 错误信息

检测到循环依赖时，你会看到显示完整依赖链的清晰错误信息：

```
Circular dependency detected for service 'AService'.
Dependency chain: AService -> BService -> CService -> AService
Check your service registration to break the cycle.
```

## 解析深度限制

为防止过深的依赖链导致栈溢出，Service 强制执行最大解析深度限制（默认 100）。如果超出：

```
Maximum resolution depth (100) exceeded.
Current chain: ServiceA -> ServiceB -> ... -> ServiceN
This may indicate a circular dependency or overly deep dependency graph.
```

## 打破循环依赖

以下是打破循环依赖的常用策略：

### 1. 重构服务结构

将共享逻辑提取到一个新服务中，让两者都依赖它：

```swift
// 之前：A 和 B 相互依赖
// 之后：将共享逻辑提取到 C

struct SharedService {
    func sharedMethod() { /* ... */ }
}

struct AService {
    let shared: SharedService
    let b: BService
}

struct BService {
    let shared: SharedService
    let a: AService  // 仍然依赖 A，但没有循环
}
```

### 2. 使用延迟解析

将解析推迟到实际需要服务时：

```swift
struct AService {
    private let bFactory: () -> BService
    
    init(bFactory: @escaping () -> BService) {
        self.bFactory = bFactory
    }
    
    func doSomething() {
        let b = bFactory()  // 仅在需要时解析
        // 使用 b...
    }
}

// 使用工厂注册
ServiceEnv.current.register(AService.self) {
    AService(bFactory: {
        ServiceEnv.current.resolve(BService.self)
    })
}
```

### 3. 使用属性注入

在构造之后注入依赖，而不是在工厂函数中：

```swift
struct AService {
    var bService: BService?
}

struct BService {
    var aService: AService?
}

// 注册服务
let a = AService()
let b = BService()

ServiceEnv.current.register(a)
ServiceEnv.current.register(b)

// 在注册后注入依赖
a.bService = b
b.aService = a
```

### 4. 引入中介者

创建一个协调两个服务的中介者服务：

```swift
struct CoordinatorService {
    let a: AService
    let b: BService
    
    func coordinate() {
        // 在 A 和 B 之间协调
    }
}

// A 和 B 不再相互依赖
struct AService {
    // 不依赖 B
}

struct BService {
    // 不依赖 A
}
```

## 实际示例

以下是一个实际场景以及如何修复它：

### 问题：UserService 和 AuthService 循环依赖

```swift
// UserService 需要 AuthService 来检查权限
struct UserService {
    let auth: AuthService
    
    func updateProfile(userId: String, profile: Profile) {
        guard auth.hasPermission(userId, .updateProfile) else { return }
        // 更新配置文件...
    }
}

// AuthService 需要 UserService 来获取用户数据
struct AuthService {
    let user: UserService
    
    func hasPermission(_ userId: String, _ permission: Permission) -> Bool {
        let user = user.getUser(id: userId)  // 循环依赖！
        return user.permissions.contains(permission)
    }
}
```

### 解决方案：提取权限服务

```swift
// 将权限逻辑提取到单独的服务
struct PermissionService {
    func hasPermission(_ userId: String, _ permission: Permission) -> Bool {
        // 检查权限，无需 UserService
        // ...
    }
}

// 两个服务都依赖 PermissionService 而不是相互依赖
struct UserService {
    let permissions: PermissionService
    
    func updateProfile(userId: String, profile: Profile) {
        guard permissions.hasPermission(userId, .updateProfile) else { return }
        // 更新配置文件...
    }
}

struct AuthService {
    let permissions: PermissionService
    
    func authenticate(credentials: Credentials) -> AuthResult {
        // 使用权限服务...
    }
}
```

## 测试循环依赖

Service 的自动检测使在开发过程中轻松捕获循环依赖。如果你怀疑有循环依赖，尝试解析服务：

```swift
func testNoCircularDependency() {
    // 如果有循环，这将失败并显示清晰的错误
    let service = ServiceEnv.current.resolve(AService.self)
    XCTAssertNotNil(service)
}
```

## 最佳实践

1. **设计具有清晰依赖的服务**：尽可能避免双向依赖。

2. **使用依赖注入**：让 Service 管理依赖，而不是服务自己创建依赖。

3. **保持服务专注**：每个服务应该有一个单一、明确定义的职责。

4. **尽早测试**：Service 的循环检测会在运行时捕获问题，但最好从一开始就设计服务以避免循环。

## 下一步

- 学习 <doc:ServiceAssembly.zh-Hans> 了解如何组织服务注册
- 探索 <doc:RealWorldExamples.zh-Hans> 了解更多模式
- 阅读 <doc:UnderstandingService.zh-Hans> 深入了解 Service 的解析机制
