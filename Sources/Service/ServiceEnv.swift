//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

/// A service environment: a set of registrations and the instances that they cache.
///
/// Each `ServiceEnv(name:)` call creates an environment with its own registrations and caches.
/// A copy of a value refers to the same environment.
///
/// ```swift
/// ServiceEnv.current.register(DatabaseProtocol.self) {
///     DatabaseService()
/// }
///
/// // Code inside the closure, and the tasks that it starts, use `env`.
/// let env = ServiceEnv(name: "test")
/// ServiceEnv.$current.withValue(env) {
///     env.register(DatabaseProtocol.self) { MockDatabase() }
/// }
/// ```
public struct ServiceEnv: Sendable {
    /// The environment of the current task. The default is ``online``.
    ///
    /// The value is task-local. Bind another environment with `ServiceEnv.$current.withValue(_:operation:)`.
    @TaskLocal
    public static var current: ServiceEnv = .online

    /// The largest number of nested resolutions that run a factory. The default is 100.
    ///
    /// A resolution beyond the limit throws ``ServiceError/maxDepthExceeded(depth:chain:)``.
    /// A resolution that returns a cached instance does not count.
    ///
    /// The value is task-local:
    ///
    /// ```swift
    /// ServiceEnv.$maxResolutionDepth.withValue(10) {
    ///     let service = try ServiceEnv.current.resolve(MyService.self)
    /// }
    /// ```
    @TaskLocal
    public static var maxResolutionDepth: Int = 100

    /// The name of this environment.
    ///
    /// A name does not identify an environment. Every `ServiceEnv(name:)` call creates an environment
    /// with its own registry and caches, also when another environment has the same name.
    public let name: String

    /// The registrations and caches of this environment.
    let storage = ServiceStorage()

    /// Creates an environment with its own registrations and caches.
    ///
    /// - Parameter name: The name of the environment. It does not have to be unique.
    public init(name: String) {
        self.name = name
    }
}

/// Predefined environments. Each is one instance that the whole process shares.
extension ServiceEnv {
    /// The environment for production. It is the default of ``current``.
    public static let online: ServiceEnv = ServiceEnv(name: "online")

    /// An environment for test builds.
    public static let test: ServiceEnv = ServiceEnv(name: "test")

    /// An environment for local development.
    public static let dev: ServiceEnv = ServiceEnv(name: "dev")
}

extension ServiceEnv: Hashable {
    /// Returns whether two values are the same environment.
    ///
    /// Two values are equal if they share one registry and one set of caches. A copy of a value equals
    /// the original. Two environments that were created with the same name are not equal; compare
    /// ``name`` to check how an environment is named.
    public static func == (lhs: ServiceEnv, rhs: ServiceEnv) -> Bool {
        lhs.storage === rhs.storage
    }

    /// Hashes the identity of the environment.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(storage))
    }
}

extension ServiceEnv {
    /// Removes all cached instances and keeps the registrations.
    ///
    /// The next resolution of a service runs its factory again.
    public func resetCaches() {
        storage.resetCaches()
    }

    /// Removes all registrations and all cached instances.
    ///
    /// A service has to be registered again before it can be resolved.
    public func resetAll() {
        storage.resetAll()
    }

    /// Removes the cached instances of one scope and keeps the registrations.
    ///
    /// ```swift
    /// // On logout
    /// env.resetScope(.custom("user-session"))
    /// ```
    ///
    /// - Parameter scope: The scope to clear. `.transient` and `.graph` have no cache to clear.
    public func resetScope(_ scope: ServiceScope) {
        storage.resetScope(scope)
    }
}
