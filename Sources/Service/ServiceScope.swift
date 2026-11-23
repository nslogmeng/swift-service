//
//  Copyright © 2026 Service Contributors. All rights reserved.
//

/// When the factory of a registration runs, and how long its instance is kept.
///
/// ```swift
/// env.register(DatabaseService.self) { DatabaseService() }
/// env.register(RequestHandler.self, scope: .transient) { RequestHandler() }
/// env.register(UnitOfWork.self, scope: .graph) { UnitOfWork() }
/// env.register(SessionService.self, scope: .custom("user-session")) { SessionService() }
/// ```
public enum ServiceScope: Hashable, Sendable {
    /// One instance for the environment. This is the default.
    ///
    /// The first resolution creates the instance. It is kept until ``ServiceEnv/resetCaches()``,
    /// `resetScope(.singleton)`, or ``ServiceEnv/resetAll()``.
    case singleton

    /// A new instance for every resolution.
    case transient

    /// One instance for a resolution graph: one top-level `resolve` call and the resolutions that
    /// its factories start.
    ///
    /// ```
    /// resolve(ServiceA)
    ///   ├── resolve(UnitOfWork)        creates instance X
    ///   └── resolve(ServiceB)
    ///         └── resolve(UnitOfWork)  returns instance X
    ///
    /// resolve(ServiceA)                a new graph
    ///   └── resolve(UnitOfWork)        creates instance Y
    /// ```
    ///
    /// A graph that resolves from more than one environment has one instance for each environment.
    case graph

    /// One instance for the environment, in a named scope that can be reset on its own.
    ///
    /// ```swift
    /// env.register(SessionService.self, scope: .custom("user-session")) {
    ///     SessionService()
    /// }
    ///
    /// // Removes the cached instances of this scope only.
    /// env.resetScope(.custom("user-session"))
    /// ```
    case custom(String)
}
