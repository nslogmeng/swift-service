# MainActor 服务

Service 为处理 `@MainActor` 隔离的服务（如视图模型和 UI 控制器）提供了专门的 API。

> Localization: **[English](https://nslogmeng.github.io/swift-service/documentation/service/mainactorservices)**  |  **简体中文**

## 背景：为什么需要 MainActor 服务？

在 Swift 6 的严格并发模型中，`@MainActor` 类是线程安全的（所有访问都在主线程上序列化），但**不会**自动成为 `Sendable`。这意味着它们无法使用需要 `Sendable` 遵循的标准 `register`/`resolve` API。

### 问题

考虑一个典型的视图模型：

```swift
@MainActor
final class UserViewModel {
    var userName: String = ""
    var isLoading: Bool = false
    
    func loadUser() {
        isLoading = true
        // ... 加载用户数据
        isLoading = false
    }
}
```

这个视图模型是 `@MainActor` 隔离的，意味着所有访问必须在主线程上进行。但是，它不遵循 `Sendable`，因为：

1. 它有可变状态（`userName`、`isLoading`）
2. `@MainActor` 类在 Swift 6 中不会自动成为 `Sendable`
3. 标准的 `register`/`resolve` API 需要 `Sendable` 遵循

### 解决方案

Service 提供了专门的 `registerMain` 和 `resolveMain` 方法（以及 `@MainService` 和 `@MainProvider` 属性包装器），它们可以与 `@MainActor` 隔离的服务一起工作，而无需 `Sendable` 遵循。

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

### 使用 ServiceKey

对于具有默认实现的服务：

```swift
@MainActor
final class UserViewModel: ServiceKey {
    var userName: String = ""
    
    static var `default`: UserViewModel {
        UserViewModel()
    }
}

await MainActor.run {
    ServiceEnv.current.registerMain(UserViewModel.self)
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

## 下一步

- 学习 <doc:ServiceAssembly> 了解如何组织服务注册
- 探索 <doc:RealWorldExamples> 获取更多实用示例
- 阅读 <doc:ConcurrencyModel> 深入了解 Service 的并发模型
