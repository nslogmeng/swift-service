# 设计愿景

Service 的设计哲学与未来方向。

> Localization: **[English](https://nslogmeng.github.io/swift-service/documentation/service/vision)**  |  **简体中文**

## 为什么需要 Service

Swift 6 引入了严格的并发检查。对于大部分代码来说，这是好事——编译器能在构建期捕获数据竞争。但对依赖注入来说，这带来了一个实际问题。

考虑一个典型的 DI 容器：注册服务、解析服务、注入到类型中。足够简单。但在严格并发下，编译器需要知道：这个服务是 `Sendable` 的吗？能跨 actor 边界传递吗？如果你的 `@MainActor` ViewModel 持有可变状态，它就不是 `Sendable` 的——而一个不区分这些情况就直接返回 `T` 的容器，要么在欺骗编译器，要么在迫使你用 `@unchecked Sendable` 来撒谎。

现有的 DI 库大多把并发当作实现细节——在内部用锁处理掉，不让 API 使用者操心。Service 的立场不同：**并发语义应该是 DI 契约的一部分，而不是被隐藏在背后。**

这不是学术讨论。当一个库用 `@unchecked Sendable` 让 API 编译通过时，它把线程安全的责任从编译器转移到了开发者身上。而 Swift 并发模型的核心目标，恰恰是要避免这种情况。

## 核心设计原则

### 并发作为 API 契约

Service 提供两条并行的依赖注入路径：

| | Sendable 服务 | MainActor 服务 |
|---|---|---|
| **注册** | `register()` | `registerMain()` |
| **解析** | `resolve()` | `resolveMain()` |
| **缓存式注入** | `@Service` | `@MainService` |
| **作用域驱动注入** | `@Provider` | `@MainProvider` |

这种拆分是对 Swift 类型系统的直接回应。`@MainActor` 类不是 `Sendable` 的。与其假装它是，Service 要求你在注册时就做出明确选择。然后编译器会在每一个解析点强制执行这个契约。

这意味着，当你试图在非隔离上下文中解析 MainActor 服务时，你会得到一个编译期错误——而不是运行时崩溃。

### 零依赖

DI 框架位于依赖图的最底层。你的应用中几乎每个模块都直接或间接依赖它。如果 DI 库本身引入了外部包，这些包就会成为整个项目的传递依赖——带来版本冲突、编译时间增加和升级时的连锁反应。

Service 只依赖 Swift 标准库。线程安全来自 `Synchronization.Mutex`，环境隔离来自 `@TaskLocal`，都是 Swift 的内建能力。

### 熟悉的心智模型

Service 没有发明新的 DI 范式。如果你用过 Swinject 或任何 register/resolve 容器，你已经知道 Service 怎么用了：

```swift
// 注册
env.register(DatabaseService.self) { DatabaseService() }

// 解析
let db = try env.resolve(DatabaseService.self)

// 或用属性包装器
struct Repository {
    @Service var database: DatabaseService
}
```

`ServiceAssembly` 协议提供了团队熟悉的模块化注册模式。目标不是教一种思考依赖的新方式——而是把成熟的模式拿来，让它在 Swift 并发模型下正确运行。

### 集中式可审计性

所有服务注册通过 Assembly 文件完成。当你需要回答"这个模块依赖了什么"或"这个服务在哪配置的"时，你只需要看一个地方。

这是一个刻意的取舍。去中心化的方式——每个服务自己声明默认实现——在小项目中可能更方便。但在大型代码库中，打开一个文件就能看到完整的依赖布线，这种可审计性值得那点额外的仪式感。

### 灵活的生命周期管理

不是每个服务都应该永远存活。Service 通过 ``ServiceScope`` 控制实例生命周期：

- **singleton** — 一个实例，全局共享（默认）
- **transient** — 每次解析都创建新实例
- **graph** — 在同一个解析链中共享，不同链之间独立
- **custom** — 命名作用域，拥有独立缓存，支持定向清除

`@Service` / `@MainService` 在注入点缓存实例。当你需要作用域驱动的行为时，`@Provider` / `@MainProvider` 把缓存完全委托给注册时指定的作用域。这形成了一个 2x2 矩阵：

|  | 注入点缓存 | 作用域驱动 |
|---|---|---|
| **Sendable** | `@Service` | `@Provider` |
| **MainActor** | `@MainService` | `@MainProvider` |

每种组合对应不同的使用场景，且不增加 API 复杂度。

## 与 Swift 演进方向的契合

Swift 6.2 引入了 [Approachable Concurrency](https://www.swift.org/blog/approachable-concurrency/)，改变了默认的隔离行为，让并发代码更容易编写。函数只在真正需要时才默认为 `@concurrent`，减少了不必要的 Sendable 要求。

这与 Service 的设计有两重关联。

首先，它验证了双轨方案的合理性。"这个服务可以跨隔离边界传递"和"这个服务在主线程上"之间的区分不会消失——Swift 6.2 让这种区分*更容易表达*，而不是*不需要表达*。`register` / `registerMain` 的拆分仍然与 Swift 对隔离的思考方式一致。

其次，Approachable Concurrency 降低了采用严格并发的门槛，这意味着会有更多项目真正开启它。随着采用率增长，正确建模并发的 DI 库与用 `@unchecked Sendable` 绕过编译器检查的库之间的差距会越来越明显。

## 未来方向

Service 的发展路线遵循几个优先级：

- **与 Swift 演进保持同步。** 随着语言并发模型的成熟，Service 会在新原语带来实际收益时采用它们——而不是追逐每一个提案。
- **保持 API 表面积小。** 增加功能容易，移除几乎不可能。每个新增都应该证明自己的价值。
- **投入文档和示例。** 一个 DI 框架只有在团队能低成本采用时才真正有用。

目标不是成为生态中功能最多的 DI 库。而是成为那个在 Swift 并发上做对了的、API 最小的、零依赖的方案。

## 另请参阅

- <doc:UnderstandingService>
- <doc:ConcurrencyModel>
