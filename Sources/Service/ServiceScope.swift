//
//  Copyright © 2026 Service Contributors. All rights reserved.
//

/// Defines the lifecycle scope for a registered service, controlling how instances are
/// created and cached during resolution.
///
/// Service scopes determine the caching behavior when resolving services:
///
/// - ``singleton``: A single instance is created and reused for all resolutions (default).
/// - ``transient``: A new instance is created every time the service is resolved.
/// - ``graph``: A single instance is shared within the same resolution graph, but different
///   resolution graphs get independent instances.
/// - ``custom(_:)``: A named scope with its own independent cache, allowing targeted invalidation.
///
/// ## Usage
///
/// ```swift
/// // Singleton (default) - same instance reused
/// env.register(DatabaseService.self) { DatabaseService() }
///
/// // Transient - new instance each time
/// env.register(RequestHandler.self, scope: .transient) { RequestHandler() }
///
/// // Graph - shared within one resolve chain
/// env.register(UnitOfWork.self, scope: .graph) { UnitOfWork() }
///
/// // Custom - named scope with independent cache
/// env.register(SessionService.self, scope: .custom("user-session")) { SessionService() }
/// ```
///
/// ## Graph Scope
///
/// Graph scope is useful when multiple services in a dependency chain should share the same
/// instance during a single resolution, but each top-level `resolve()` call should get a fresh
/// instance. For example, a `UnitOfWork` pattern where repositories in the same resolve chain
/// should share the same unit of work.
///
/// ```
/// resolve(ServiceA)
///   ├── resolve(UnitOfWork)  ← creates instance X
///   └── resolve(ServiceB)
///         └── resolve(UnitOfWork)  ← reuses instance X
///
/// resolve(ServiceA)  // new top-level call
///   └── resolve(UnitOfWork)  ← creates instance Y (new graph)
/// ```
public enum ServiceScope: Hashable, Sendable {
    /// A single instance is created and cached globally. All resolutions return the same instance.
    /// This is the default scope and matches the behavior of prior versions.
    case singleton

    /// A new instance is created every time the service is resolved. No caching is performed.
    case transient

    /// A single instance is shared within the same resolution graph. Each top-level `resolve()`
    /// call starts a new graph, and services resolved within that graph share instances.
    case graph

    /// A named scope that caches instances independently from other scopes.
    /// Instances within the same scope name share a cache, allowing targeted cache invalidation
    /// via ``ServiceEnv/resetScope(_:)``.
    ///
    /// ```swift
    /// // Register a service with a custom scope
    /// env.register(SessionService.self, scope: .custom("user-session")) {
    ///     SessionService()
    /// }
    ///
    /// // Clear only the user-session scope
    /// env.resetScope(.custom("user-session"))
    /// ```
    case custom(String)
}
