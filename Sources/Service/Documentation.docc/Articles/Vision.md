# Vision

The design philosophy behind Service and where it's headed.

> Localization: **English**  |  **[简体中文](https://nslogmeng.github.io/swift-service/zh-Hans/documentation/service/vision)**

## Why Service Exists

Swift 6 introduced strict concurrency checking. For most code, this was a welcome change — the compiler now catches data races at build time. But for dependency injection, it created a real problem.

Consider a typical DI container. You register services, you resolve them, and you inject them into your types. Simple enough. But under strict concurrency, the compiler needs to know: is this service `Sendable`? Can it cross actor boundaries? If your `@MainActor` view model holds mutable state, it's not `Sendable` — and a container that hands out `T` without distinguishing between these cases is either lying to the compiler or forcing you to lie with `@unchecked Sendable`.

Most existing DI libraries treat concurrency as an implementation detail — something handled internally with locks, something the API consumer shouldn't have to think about. Service takes a different position: **concurrency semantics should be part of the DI contract, not hidden behind it.**

This isn't an academic distinction. When a library uses `@unchecked Sendable` to make its API compile, it shifts the responsibility of thread safety from the compiler to the developer. The whole point of Swift's concurrency model is to avoid exactly that.

## Core Design Principles

### Concurrency as API Contract

Service provides two parallel tracks for dependency injection:

| | Sendable Services | MainActor Services |
|---|---|---|
| **Registration** | `register()` | `registerMain()` |
| **Resolution** | `resolve()` | `resolveMain()` |
| **Cached Injection** | `@Service` | `@MainService` |
| **Scope-driven Injection** | `@Provider` | `@MainProvider` |

This split is a direct response to Swift's type system. A `@MainActor` class isn't `Sendable`. Rather than pretending otherwise, Service asks you to make the choice explicitly at registration time. The compiler then enforces the contract at every resolution site.

This means you get a compile-time error — not a runtime crash — if you try to resolve a MainActor service from a non-isolated context.

### Zero Dependencies

A DI framework sits at the bottom of your dependency graph. Every module in your app depends on it, directly or indirectly. If the DI library itself pulls in external packages, those packages become transitive dependencies of your entire project — with all the version conflicts, build time costs, and upgrade friction that entails.

Service depends only on the Swift standard library. Its thread safety comes from `Synchronization.Mutex`. Its environment isolation comes from `@TaskLocal`. Both are built into Swift itself.

### Familiar Mental Model

Service doesn't invent a new DI paradigm. If you've used Swinject or any register/resolve container, you already know how Service works:

```swift
// Register
env.register(DatabaseService.self) { DatabaseService() }

// Resolve
let db = try env.resolve(DatabaseService.self)

// Or use property wrappers
struct Repository {
    @Service var database: DatabaseService
}
```

The `ServiceAssembly` protocol provides the same modular registration pattern that teams are used to. The goal is not to teach a new way of thinking about dependencies — it's to take an established pattern and make it work correctly under Swift's concurrency model.

### Centralized Auditability

All service registrations go through Assembly files. When you need to answer "what does this module depend on?" or "where is this service configured?", you have one place to look.

This is a deliberate trade-off. Decentralized approaches — where each service declares its own default — can feel more convenient for small projects. But in larger codebases, the ability to open one file and see the full dependency wiring is worth the ceremony.

### Flexible Lifecycle Management

Not every service should live forever. Service provides ``ServiceScope`` to control instance lifecycle:

- **singleton** — One instance, shared everywhere (the default)
- **transient** — A fresh instance on every resolution
- **graph** — Shared within a single resolution chain, fresh across chains
- **custom** — Named scopes with independent caches, allowing targeted invalidation

The `@Service` / `@MainService` wrappers cache at the injection site. When you need scope-driven behavior, `@Provider` / `@MainProvider` delegate caching entirely to the registered scope. This gives you a 2x2 matrix:

|  | Cached at injection site | Scope-driven |
|---|---|---|
| **Sendable** | `@Service` | `@Provider` |
| **MainActor** | `@MainService` | `@MainProvider` |

Each combination addresses a different use case without adding API complexity.

## Alignment with Swift's Direction

Swift 6.2 introduced [Approachable Concurrency](https://www.swift.org/blog/approachable-concurrency/), which changes the default isolation behavior to make concurrent code easier to write. Functions are now `@concurrent` by default only when they need to be, reducing unnecessary Sendable requirements.

This is relevant to Service's design in two ways.

First, it validates the dual-track approach. The distinction between "this service can cross isolation boundaries" and "this service lives on the main actor" isn't going away — Swift 6.2 made it *easier* to express, not *unnecessary* to express. The `register` / `registerMain` split remains aligned with how Swift thinks about isolation.

Second, Approachable Concurrency reduces the friction of adopting strict concurrency in general, which means more projects will actually turn it on. As adoption grows, the gap between DI libraries that properly model concurrency and those that bypass it with `@unchecked Sendable` will become more visible.

## Looking Forward

Service's roadmap is guided by a few priorities:

- **Stay aligned with Swift's evolution.** As the language's concurrency model matures, Service should adopt new primitives when they provide real benefits — not chase every proposal.
- **Keep the API surface small.** Adding features is easy; removing them is nearly impossible. Every addition should earn its place.
- **Invest in documentation and examples.** A DI framework is only useful if teams can adopt it without a steep learning curve.

The goal isn't to become the most feature-rich DI library in the ecosystem. It's to be the one that gets Swift concurrency right, with the smallest possible API, and zero dependencies.

## See Also

- <doc:UnderstandingService>
- <doc:ConcurrencyModel>
