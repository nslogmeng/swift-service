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

    /// Resets all cached services in this environment.
    ///
    /// This clears cached instances only, forcing all services to be recreated on next resolution.
    /// Registrations (factories) are preserved.
    public func resetCache() {
        storage.resetCache()
    }

    /// Resets cached services and registrations in this environment.
    ///
    /// This clears both cached instances and registered factories.
    /// Intended primarily for tests or full teardown scenarios.
    public func resetAll() {
        storage.resetAll()
    }
}

/// Predefined service environments for common use cases.
extension ServiceEnv {
    /// Production environment for live application usage.
    public static let online: ServiceEnv = ServiceEnv(name: "online")

    /// Internal testing environment for in-house builds.
    public static let inhouse: ServiceEnv = ServiceEnv(name: "inhouse")

    /// Development environment for local development and debugging.
    public static let dev: ServiceEnv = ServiceEnv(name: "dev")
}

// MARK: - Registration

extension ServiceEnv {
    /// Registers a service using a factory function.
    ///
    /// This overload is for services that are safe to use from any concurrency domain.
    /// The service must conform to `Sendable` and the factory must be `@Sendable`.
    ///
    /// - Parameters:
    ///   - type: The service type to register.
    ///   - factory: A factory function that creates the service instance.
    public func register<Service: Sendable>(_ type: Service.Type, factory: @escaping @Sendable () -> Service) {
        storage.registerAny(type, factory: factory)
    }

    /// Registers a service using a factory function on the main actor.
    ///
    /// This overload is intended for UI-bound services (or other main-actor-isolated services).
    /// The factory runs on `@MainActor`, so it can call `@MainActor` isolated initializers/APIs.
    ///
    /// Note: This overload is marked as disfavored to prefer the `Sendable` overload when both
    /// are viable. It remains the fallback when the `@Sendable` overload cannot type-check.
    ///
    /// - Parameters:
    ///   - type: The service type to register.
    ///   - factory: A factory function that creates the service instance on `@MainActor`.
    @_disfavoredOverload
    public func register<Service>(_ type: Service.Type, factory: @escaping @MainActor () -> Service) {
        storage.registerMain(type, factory: factory)
    }

    /// Registers a service using the ServiceKey's default value.
    ///
    /// The default value is stored in the "any-actor" channel, therefore the service must be
    /// `Sendable` to remain concurrency-safe.
    ///
    /// - Parameter type: A service type conforming to the ServiceKey protocol.
    public func register<Service: ServiceKey & Sendable>(_ type: Service.Type) {
        storage.registerAny(type, factory: { Service.default })
    }

    /// Registers a service instance directly.
    /// The instance will be cached and reused for subsequent resolutions.
    ///
    /// This overload registers an any-actor (Sendable) instance.
    ///
    /// - Parameter instance: The service instance to register.
    public func register<Service: Sendable>(_ instance: Service) {
        storage.registerAny(Service.self, factory: { instance })
    }

    /// Registers a service instance directly on the main actor channel.
    /// The instance will be cached and reused for subsequent resolutions on `@MainActor`.
    ///
    /// - Parameter instance: The service instance to register.
    @MainActor
    @_disfavoredOverload
    public func register<Service>(_ instance: Service) {
        storage.registerMain(Service.self, factory: { instance })
    }
}


// MARK: - Resolve

extension ServiceEnv {
    /// Resolves a service instance by its type.
    /// If the service is not registered, this will cause a runtime fatalError.
    ///
    /// This overload resolves only "any-actor" services (Sendable).
    ///
    /// - Parameter type: The service type to resolve.
    /// - Returns: The resolved service instance.
    public func resolve<Service: Sendable>(_ type: Service.Type) -> Service {
        guard let service = storage.resolveAny(type) else {
            fatalError("Service: \(Service.self) must register in ServiceEnv")
        }
        return service
    }

    /// Resolves a service instance by its type on `@MainActor`.
    /// If the service is not registered, this will cause a runtime fatalError.
    ///
    /// This overload can resolve both "any-actor" services and "main-actor" services.
    ///
    /// - Parameter type: The service type to resolve.
    /// - Returns: The resolved service instance.
    @MainActor
    @_disfavoredOverload
    public func resolve<Service>(_ type: Service.Type) -> Service {
        guard let service = storage.resolveMain(type) else {
            fatalError("Service: \(Service.self) must register in ServiceEnv")
        }
        return service
    }
}
