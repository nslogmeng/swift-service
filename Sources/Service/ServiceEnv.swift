//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

/// Represents a service environment that manages service registration, resolution, and lifecycle.
/// Each environment maintains its own isolated service registry and storage, allowing for
/// different configurations in different contexts (e.g., production, testing, development).
///
/// The environment uses TaskLocal storage to ensure thread-safe access to the current environment
/// across async contexts. Service resolution supports parameterized services via HashableKey.
///
/// Usage example:
/// ```swift
/// func testUserService() async {
///     await ServiceEnv.$current.withValue(.dev) {
///         // All services resolved in this block use dev environment
///         let userService = UserService()
///         let result = userService.createUser(name: "Test User")
///         XCTAssertNotNil(result)
///     }
/// }
/// ```
public struct ServiceEnv: Sendable {
    /// The current service environment for the current task context.
    /// Defaults to the online environment.
    @TaskLocal
    public static var current: ServiceEnv = .online

    /// A unique identifier for this environment.
    public let key: String

    /// The maximum depth allowed for dependency resolution to prevent infinite recursion.
    /// Defaults to 200 levels deep.
    public let maxResolutionDepth: Int

    /// Internal storage for caching resolved services based on their scope and parameters.
    internal let storage = ServiceStorage()

    /// Creates a new service environment with the specified configuration.
    ///
    /// - Parameters:
    ///   - key: A unique identifier for this environment.
    ///   - maxResolutionDepth: Maximum allowed dependency resolution depth (default: 200).
    public init(key: String, maxResolutionDepth: Int = 200) {
        self.key = key
        self.maxResolutionDepth = maxResolutionDepth
    }

    /// Resets all cached services for a specific scope.
    /// This is useful for cleaning up services when their lifecycle ends.
    ///
    /// - Parameter scope: The scope to reset.
    func reset(scope: Scope) {
        storage.reset(scope: scope)
    }

    /// Resets all cached services in this environment.
    /// This clears the entire service cache.
    func reset() {
        storage.reset()
    }
}

/// Predefined service environments for common use cases.
extension ServiceEnv {
    /// Production environment for live application usage.
    public static let online: ServiceEnv = ServiceEnv(key: "online")
    
    /// Internal testing environment for in-house builds.
    public static let inhouse: ServiceEnv = ServiceEnv(key: "inhouse")
    
    /// Development environment for local development and debugging.
    public static let dev: ServiceEnv = ServiceEnv(key: "dev")
}

extension ServiceEnv {
    /// Internal subscript that uses HashableKey for service resolution.
    /// This method delegates to the resolve function for actual service creation.
    /// Supports parameterized resolution via HashableKey.
    ///
    /// - Parameter key: The hashable key wrapper for the ServiceKey.
    /// - Returns: The resolved service instance.
    subscript<Key: ServiceKey>(_ key: HashableKey<Key>) -> Key.Value {
        return resolve(key)
    }

    /// Resolves a service instance with proper context management.
    /// This method ensures that service resolution happens within a proper ServiceContext
    /// and validates that nested resolutions use the context.resolve method.
    /// Supports parameterized resolution.
    ///
    /// - Parameter key: The ServiceKey type to resolve.
    /// - Returns: The resolved service instance
    private func resolve<Key: ServiceKey>(_ key: HashableKey<Key>) -> Key.Value {
        assert(ServiceContext.current.depth.isEmpty, """
        Resolve \(ServiceContext.current.depth.last ?? "") in resolution func build(with:) must use context.resolve(_:) \
        to resolve your dependency \(String(describing: key)).
        """)
        let context = ServiceContext(env: .current)
        return ServiceContext.$current.withValue(context) {
            return ServiceContext.current.resolve(Key.self, params: key.params)
        }
    }
}
