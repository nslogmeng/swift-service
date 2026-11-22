# MainActor 服务

Service 为处理 `@MainActor` 隔离的服务（如视图模型和 UI 控制器）提供了专门的 API。

> Localization: **[English](https://nslogmeng.github.io/swift-service/documentation/service/mainactorservices)**  |  **简体中文**

## 背景：为什么需要 MainActor 服务？

标准的 `register`/`resolve` API 面向跨隔离域共享的服务。工厂函数是 nonisolated 的 `@Sendable` 闭包，可以在任意线程执行，服务类型必须遵循 `Sendable`。在 MainActor 上创建和使用的服务往往满足不了这些要求。

### 问题

考虑一个典型的视图模型：

```swift
@MainActor
protocol UserViewModelProtocol {
    var userName: String { get }
}

@MainActor
final class UserViewModel: UserViewModelProtocol {
    var userName: String = ""
    var isLoading: Bool = false

    init() {
        // ... 设置初始状态
    }

    func loadUser() {
        isLoading = true
        // ... 加载用户数据
        isLoading = false
    }
}
```

这个视图模型是 `@MainActor` 隔离的，意味着所有访问必须在主线程上进行。这样的 `@MainActor` 类隐式遵循 `Sendable`：它的引用可以跨隔离域传递，因为对其状态的每次访问都经过 MainActor。它的初始化器和成员仍然是隔离的，`register` 正是在这里行不通：

1. 初始化器是 MainActor 隔离的。`register` 的工厂函数是 nonisolated 的同步闭包，无法调用 `UserViewModel()`。
2. 注册服务所用的类型往往不是 `Sendable`。`any UserViewModelProtocol` 不是 `Sendable`，因为该协议是 `@MainActor` 的，且没有继承 `Sendable`。继承自非 `Sendable` 基类的 `@MainActor` 类同样不是 `Sendable`。

### 解决方案

Service 提供了专门的 `registerMain` 和 `resolveMain` 方法（以及 `@MainService` 和 `@MainProvider` 属性包装器）。工厂函数是 `@MainActor` 闭包，实例只在 MainActor 上创建、缓存和解析。工厂函数可以调用 MainActor 隔离的初始化器，也可以解析其他 MainActor 服务，服务类型无需遵循 `Sendable`。

## 注册 MainActor 服务

### 使用 registerMain

使用 `registerMain` 注册 `@MainActor` 服务。与 `register` 一样，你可以指定 scope 参数：

```swift
@MainActor
final class UserViewModel {
    var userName: String = ""
    func loadUser() { /* ... */ }
}

// 在主 actor 上下文中注册（默认：.singleton）
await MainActor.run {
    ServiceEnv.current.registerMain(UserViewModel.self) {
        UserViewModel()
    }
}

// 指定特定作用域注册
await MainActor.run {
    ServiceEnv.current.registerMain(UserViewModel.self, scope: .transient) {
        UserViewModel()
    }
}
```

### 直接实例注册

你也可以注册现有实例：

```swift
await MainActor.run {
    let viewModel = UserViewModel()
    ServiceEnv.current.registerMain(viewModel)
}
```

## 解析 MainActor 服务

### 使用 resolveMain

使用 `resolveMain` 解析 `@MainActor` 服务（必须从 `@MainActor` 上下文调用）：

```swift
@MainActor
func setupUI() {
    let viewModel = ServiceEnv.current.resolveMain(UserViewModel.self)
    viewModel.loadUser()
}
```

### 使用 @MainService 属性包装器

`@MainService` 属性包装器为 `@MainActor` 服务提供便捷的懒加载注入。服务在首次访问时解析（而非初始化时），解析结果会被缓存：

```swift
@MainActor
class UserViewController {
    @MainService
    var viewModel: UserViewModel

    func viewDidLoad() {
        viewModel.loadUser()
    }
}
```

### 可选 MainService

对于可能未注册的 MainActor 服务，使用可选类型：

```swift
@MainActor
class UserViewController {
    @MainService var analytics: AnalyticsViewModel?  // 未注册时返回 nil

    func trackEvent(_ event: String) {
        analytics?.track(event)  // 安全的可选访问
    }
}
```

### 使用 @MainProvider 属性包装器

`@MainProvider` 属性包装器在**每次访问时**解析服务，将缓存行为委托给服务注册的作用域。这是 `@Provider` 的 MainActor 等价物：

```swift
@MainActor
class DashboardController {
    @MainProvider var viewModel: DashboardViewModel  // 每次访问时解析
}
```

当服务注册为非 singleton 作用域时，使用 `@MainProvider` 让作用域控制实例生命周期：

```swift
// 注册为 transient - 每次获取新实例
ServiceEnv.current.registerMain(DashboardViewModel.self, scope: .transient) {
    DashboardViewModel()
}
```

`@MainProvider` 同样支持可选类型：

```swift
@MainActor
class DashboardController {
    @MainProvider var analytics: AnalyticsViewModel?  // 未注册时返回 nil
}
```

**选择 @MainService 还是 @MainProvider：**

| | `@MainService` | `@MainProvider` |
|---|---|---|
| 解析时机 | 懒加载，首次访问时 | 每次访问时 |
| 本地缓存 | 始终在本地缓存 | 不进行本地缓存；委托给作用域 |
| 适用场景 | Singleton 服务 | Transient 或自定义作用域服务 |

## 完整示例：SwiftUI 应用

以下是在 SwiftUI 应用中使用 MainActor 服务的完整示例：

```swift
import SwiftUI
import Service

// 定义视图模型
@MainActor
final class UserViewModel: ObservableObject {
    @Published var userName: String = ""
    @Published var isLoading: Bool = false
    
    private let apiClient: APIClientProtocol
    
    init(apiClient: APIClientProtocol) {
        self.apiClient = apiClient
    }
    
    func loadUser() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let user = try await apiClient.fetchUser()
            userName = user.name
        } catch {
            print("Failed to load user: \(error)")
        }
    }
}

// 在 App 初始化中注册服务
@main
struct MyApp: App {
    init() {
        // 注册常规服务
        ServiceEnv.current.register(APIClientProtocol.self) {
            APIClient(baseURL: "https://api.example.com")
        }
        
        // 注册 MainActor 服务
        ServiceEnv.current.registerMain(UserViewModel.self) {
            let apiClient = ServiceEnv.current.resolve(APIClientProtocol.self)
            return UserViewModel(apiClient: apiClient)
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// 在视图中使用服务
struct ContentView: View {
    @MainService
    var viewModel: UserViewModel
    
    var body: some View {
        VStack {
            if viewModel.isLoading {
                ProgressView()
            } else {
                Text(viewModel.userName)
            }
            
            Button("Load User") {
                Task {
                    await viewModel.loadUser()
                }
            }
        }
    }
}
```

## 混合 Sendable 和 MainActor 服务

你可以混合使用常规 `Sendable` 服务和 `@MainActor` 服务：

```swift
// 注册 Sendable 服务
ServiceEnv.current.register(APIClientProtocol.self) {
    APIClient(baseURL: "https://api.example.com")
}

// 注册依赖 Sendable 服务的 MainActor 服务
await MainActor.run {
    ServiceEnv.current.registerMain(UserViewModel.self) {
        // 从 MainActor 上下文解析 Sendable 服务
        let apiClient = ServiceEnv.current.resolve(APIClientProtocol.self)
        return UserViewModel(apiClient: apiClient)
    }
}
```

## 重要提示

1. **始终从 `@MainActor` 上下文调用 `registerMain` 和 `resolveMain`**：这些方法标记为 `@MainActor`，必须从主线程调用。

2. **服务缓存**：MainActor 服务像常规服务一样被缓存。首次解析创建实例，后续解析返回同一个实例。

3. **线程安全**：对 MainActor 服务的所有访问都自动在主线程上序列化，确保线程安全。

4. **在 SwiftUI 应用中**：在 SwiftUI 的 `App` 初始化器和视图中，通常已经在主 actor 上，因此可以直接调用 `registerMain` 和 `resolveMain`，无需 `await MainActor.run`。

## 默认 MainActor 隔离的模块

启用默认 MainActor 隔离的模块（package manifest 中的 `.defaultIsolation(MainActor.self)`，或 Xcode 的 Default Actor Isolation 构建设置），会把所有未显式标注隔离的声明视为 `@MainActor`。新建的 Xcode app target 默认启用该设置。

### MainActor 服务

在这类模块中，`registerMain`、`resolveMain`、`@MainService`、`@MainProvider` 和 `ServiceAssembly` 无需任何标注：

```swift
protocol Store {
    var name: String { get }
}

final class MemoryStore: Store {
    var name = "memory"
}

struct Screen {
    @MainService var store: any Store
}

ServiceEnv.current.registerMain((any Store).self) { MemoryStore() }
```

### Sendable 服务

用 `register` 注册的服务必须退出默认隔离。把它的协议声明为 `nonisolated` 且继承 `Sendable`。遵循这种协议的类型会被推断为 nonisolated：

```swift
nonisolated protocol Logger: Sendable {
    func log(_ message: String)
}

struct ConsoleLogger: Logger {
    let prefix: String

    init(prefix: String) {
        self.prefix = prefix
    }

    func log(_ message: String) {
        print("\(prefix): \(message)")
    }
}

ServiceEnv.current.register((any Logger).self) { ConsoleLogger(prefix: "app") }
```

不经协议、直接注册具体类型时，把该类型标注为 `nonisolated`：

```swift
nonisolated final class Cache: Sendable {
    let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
    }
}

ServiceEnv.current.register(Cache.self) { Cache(capacity: 100) }
```

遵循 `ServiceKey` 的类型无需标注，因为 `ServiceKey` 是 nonisolated 的，并且继承 `Sendable`。

声明为 `protocol Logger: Sendable` 而没有 `nonisolated` 的协议仍然是 `@MainActor` 的。`register` 接受它，但它的成员以及遵循它的类型的初始化器都留在 MainActor 上。

### 常见编译错误

| 代码 | 编译错误 | 修复 |
|---|---|---|
| `protocol Logger` 用于 `register` 或 `@Service` | `type 'any Logger' does not conform to the 'Sendable' protocol` | 声明为 `nonisolated protocol Logger: Sendable`，或改用 `registerMain` |
| 带显式 `init` 的类型在 `register` 的工厂函数中创建 | `call to main actor-isolated initializer ... in a synchronous nonisolated context` | 把该类型标注为 `nonisolated`，或改用 `registerMain` |
| 在 MainActor 之外调用 `Sendable` 服务的方法 | `main actor-isolated instance method ... cannot be called from outside of the actor` | 把协议或类型标注为 `nonisolated` |
| 带可变存储属性的 `final class ViewModel: ServiceKey` | `stored property ... of 'Sendable'-conforming class 'ViewModel' is mutable` | 使用带工厂函数的 `registerMain`。`ServiceKey` 用于 Sendable 服务 |

## 下一步

- 学习 <doc:ServiceAssembly> 了解如何组织服务注册
- 探索 <doc:MigratingFromSwinject> 了解如何从 Swinject 迁移
- 阅读 <doc:ConcurrencyModel> 深入了解 Service 的并发模型
