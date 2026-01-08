//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

/// Represents a service environment that manages service registration, resolution, and lifecycle.
/// Each environment maintains its own isolated service registry and storage, allowing for
/// different configurations in different contexts (e.g., production, testing, development).
///
/// The environment uses TaskLocal storage to ensure thread-safe access to the current environment
/// across async contexts.
///
/// Usage example:
/// ```swift
/// // Switch environment in tests
/// await ServiceEnv.$current.withValue(.dev) {
///     // All services resolved in this block use dev environment
///     let service = MyService()
///     // ...
/// }
///
/// // Register services
/// ServiceEnv.current.register(DatabaseProtocol.self) {
///     DatabaseService()
/// }
/// ```
public struct ServiceEnv: Sendable {
    /// The current service environment for the current task context.
    /// Defaults to the online environment.
    @TaskLocal
    public static var current: ServiceEnv = .online

    /// A unique identifier for this environment.
    public let name: String

    /// Internal storage for caching resolved service instances.
    let storage = ServiceStorage()

    /// Creates a new service environment with the specified name.
    ///
    /// - Parameter name: A unique identifier for this environment.
    public init(name: String) {
        self.name = name
    }

    /// Registers a service using a factory function.
    ///
    /// - Parameters:
    ///   - type: The service type to register.
    ///   - factory: A factory function that creates the service instance.
    public func register<Service: Sendable>(
        _ type: Service.Type,
        factory: @escaping @Sendable () -> Service
    ) {
        storage.register(type, factory: factory)
    }

    /// Registers a service using the ServiceKey's default value.
    ///
    /// - Parameter type: A service type conforming to the ServiceKey protocol.
    public func register<Service: ServiceKey>(_ type: Service.Type) {
        storage.register(type, factory: { Service.default })
    }

    /// Registers a service instance directly.
    /// The instance will be cached and reused for subsequent resolutions.
    ///
    /// - Parameter instance: The service instance to register.
    public func register<Service: Sendable>(_ instance: Service) {
        storage.register(Service.self, factory: { instance })
    }

    /// Clears all cached service instances.
    /// Registered service providers remain intact, so services will be recreated
    /// on the next resolution using their registered factory functions.
    ///
    /// This is useful when you want to force services to be recreated without
    /// re-registering them, such as in testing scenarios where you need fresh instances.
    ///
    /// Usage example:
    /// ```swift
    /// // Register a service
    /// ServiceEnv.current.register(String.self) {
    ///     UUID().uuidString
    /// }
    ///
    /// let service1 = ServiceEnv.current.resolve(String.self)
    ///
    /// // Clear cache - next resolution will create a new instance
    /// ServiceEnv.current.resetCaches()
    /// let service2 = ServiceEnv.current.resolve(String.self)
    /// // service1 != service2 (new instance created)
    /// ```
    public func resetCaches() {
        storage.resetCaches()
    }

    /// Clears all cached service instances and removes all registered service providers.
    /// This completely resets the service environment to its initial state.
    ///
    /// After calling this method, all services must be re-registered before they can be resolved.
    ///
    /// Usage example:
    /// ```swift
    /// // Register services
    /// ServiceEnv.current.register(DatabaseProtocol.self) {
    ///     DatabaseService()
    /// }
    ///
    /// // Reset everything
    /// ServiceEnv.current.resetAll()
    ///
    /// // Services must be re-registered
    /// ServiceEnv.current.register(DatabaseProtocol.self) {
    ///     DatabaseService()
    /// }
    /// ```
    public func resetAll() {
        storage.resetAll()
    }
}

/// Predefined service environments for common use cases.
extension ServiceEnv {
    /// Production environment for live application usage.
    public static let online: ServiceEnv = ServiceEnv(name: "online")

    /// Internal testing environment for test builds.
    public static let test: ServiceEnv = ServiceEnv(name: "test")

    /// Development environment for local development and debugging.
    public static let dev: ServiceEnv = ServiceEnv(name: "dev")
}

extension ServiceEnv {
    /// Resolves a service instance by its type.
    /// If the service is not registered, this will cause a runtime fatalError.
    ///
    /// - Parameter type: The service type to resolve.
    /// - Returns: The resolved service instance.
    public func resolve<Service: Sendable>(_ type: Service.Type) -> Service {
        guard let service = storage.resolve(type) else {
            fatalError("Service: \(Service.self) must register in ServiceEnv")
        }
        return service
    }
}
