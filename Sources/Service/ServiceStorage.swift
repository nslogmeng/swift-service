//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

/// Internal storage system that manages cached service instances based on their types.
/// This class provides thread-safe service storage and retrieval using locking mechanisms
/// to ensure safe concurrent access. Service instances are created and cached on first resolution,
/// and subsequent resolutions return the same instance (singleton behavior).
///
/// The storage supports two categories of services:
/// - **Sendable services**: Thread-safe services that can be shared across concurrent contexts.
/// - **MainActor services**: Services isolated to the main actor, typically UI-related components
///   like view models.
///
/// Both categories use `@Locked` dictionaries for synchronization, enabling cross-category
/// mutual exclusion checks during registration. A service type can only be registered as
/// either Sendable or MainActor, not both.
final class ServiceStorage: @unchecked Sendable {
    /// A cache key that uniquely identifies a service instance in storage.
    /// Uses the service type's ObjectIdentifier as the key.
    struct CacheKey: Hashable, Sendable {
        /// The unique identifier for the service type.
        let typeId: ObjectIdentifier

        /// Creates a cache key for a service type.
        ///
        /// - Parameter type: The service type.
        init<Service>(_ type: Service.Type) {
            self.typeId = ObjectIdentifier(Service.self)
        }
    }

    // MARK: - Box Types

    /// A box that wraps cached service instances (both Sendable and MainActor).
    /// This enables storing any service instance in `@Locked` storage.
    /// Safety: MainActor services are only accessed from `@MainActor` methods.
    private struct CacheBox: @unchecked Sendable {
        let value: Any
    }

    /// A box that wraps MainActor-isolated factory functions.
    /// This enables storing MainActor factories in `@Locked` storage.
    /// Safety: The wrapped factory is only called from `@MainActor` methods.
    private struct MainProviderBox: @unchecked Sendable {
        let factory: @MainActor () throws -> Any
    }

    // MARK: - Unified Cache Storage

    /// Thread-safe cache storage for all service instances (both Sendable and MainActor).
    /// Uses `CacheBox` to wrap values for uniform storage.
    @Locked
    private var caches: [CacheKey: CacheBox]

    // MARK: - Provider Storage

    /// Thread-safe storage for Sendable service factory functions.
    @Locked
    private var providers: [CacheKey: @Sendable () throws -> any Sendable]

    /// Thread-safe storage for MainActor service factory functions.
    /// Uses `MainProviderBox` to wrap `@MainActor` closures.
    @Locked
    private var mainProviders: [CacheKey: MainProviderBox]

    /// Creates a new service storage instance.
    init() {}

    // MARK: - Sendable Services

    /// Resolves a Sendable service instance by its type.
    /// If not in cache, attempts to create a new instance using the registered factory function and caches it.
    ///
    /// - Parameter type: The service type.
    /// - Returns: The service instance, or nil if not registered.
    /// - Throws: Rethrows any error from the factory function.
    func resolve<Service: Sendable>(_ type: Service.Type) throws -> Service? {
        let key = CacheKey(type)

        // First, try to get from cache (fast path)
        if let box = caches[key], let service = box.value as? Service {
            return service
        }

        // Get factory (read-only, safe to do outside lock)
        guard let factory = providers[key] else {
            return nil
        }

        // Create service instance (factory may be slow, so we do it outside the lock)
        // Factory can throw, so we propagate the error
        guard let newService = try factory() as? Service else {
            return nil
        }

        // Use withLock to ensure atomic check-and-set operation (double-check pattern)
        return $caches.withLock { (caches: inout sending [CacheKey: CacheBox]) -> sending Service in
            // Double-check: another thread might have cached it while we were creating
            if let box = caches[key], let cachedService = box.value as? Service {
                return cachedService
            }

            // Store the newly created service
            caches[key] = CacheBox(value: newService)
            return newService
        }
    }

    /// Registers a Sendable service factory function.
    ///
    /// - Parameters:
    ///   - type: The service type to register.
    ///   - factory: A factory function that creates the service instance. Can throw errors.
    /// - Important: The service type must not already be registered as a MainActor service.
    ///   In debug builds, an assertion failure will be triggered if this constraint is violated.
    func register<Service: Sendable>(_ type: Service.Type, factory: @escaping @Sendable () throws -> any Sendable) {
        let key = CacheKey(type)
        if mainProviders[key] != nil {
            assertionFailure(
                "Service '\(Service.self)' is already registered as a MainActor service. "
                    + "A service type can only be registered as either Sendable or MainActor, not both."
            )
        }
        providers[key] = factory
    }

    // MARK: - MainActor Services

    /// Resolves a MainActor-isolated service instance by its type.
    /// If not in cache, attempts to create a new instance using the registered factory function and caches it.
    ///
    /// This method is designed for services that are bound to the main actor, such as UI view models
    /// and controllers. These services don't need to conform to Sendable since they're always
    /// accessed from the main thread.
    ///
    /// - Parameter type: The service type.
    /// - Returns: The service instance, or nil if not registered.
    /// - Throws: Rethrows any error from the factory function.
    @MainActor
    func resolveMain<Service>(_ type: Service.Type) throws -> Service? {
        let key = CacheKey(type)
        if let box = caches[key], let service = box.value as? Service {
            return service
        }
        if let providerBox = mainProviders[key], let service = try providerBox.factory() as? Service {
            caches[key] = CacheBox(value: service)
            return service
        }
        return nil
    }

    /// Registers a MainActor-isolated service factory function.
    ///
    /// Use this for services that must run on the main actor, such as UI view models and controllers.
    /// The factory function is marked with @MainActor to ensure service creation happens on the main thread.
    ///
    /// - Parameters:
    ///   - type: The service type to register.
    ///   - factory: A MainActor-isolated factory function that creates the service instance. Can throw errors.
    /// - Important: The service type must not already be registered as a Sendable service.
    ///   In debug builds, an assertion failure will be triggered if this constraint is violated.
    @MainActor
    func registerMain<Service>(_ type: Service.Type, factory: @escaping @MainActor () throws -> Service) {
        let key = CacheKey(type)
        if providers[key] != nil {
            assertionFailure(
                "Service '\(Service.self)' is already registered as a Sendable service. "
                    + "A service type can only be registered as either Sendable or MainActor, not both."
            )
        }
        mainProviders[key] = MainProviderBox(factory: factory)
    }

    // MARK: - Reset

    /// Clears all cached service instances (both Sendable and MainActor services).
    /// Registered service providers remain intact, so services will be recreated
    /// on the next resolution using their registered factory functions.
    func resetCaches() {
        caches.removeAll()
    }

    /// Clears all cached service instances and removes all registered service providers
    /// (both Sendable and MainActor services).
    /// This completely resets the storage to its initial state.
    func resetAll() {
        caches.removeAll()
        providers.removeAll()
        mainProviders.removeAll()
    }
}
