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
///   These use `@Locked` dictionaries for synchronization.
/// - **MainActor services**: Services isolated to the main actor, typically UI-related components
///   like view models. These use `@MainActor`-isolated storage and don't require locks since
///   all access is serialized on the main thread.
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

    // MARK: - Sendable Services Storage

    /// Thread-safe cache storage for Sendable service instances.
    /// Uses a locked dictionary to ensure safe concurrent access.
    @Locked
    private var caches: [CacheKey: any Sendable]

    /// Thread-safe storage for Sendable service factory functions.
    @Locked
    private var providers: [CacheKey: @Sendable () throws -> any Sendable]

    // MARK: - MainActor Services Storage

    /// Cache storage for MainActor-isolated service instances.
    /// No locking is needed since all access is serialized on the main actor.
    /// These services are typically UI-related components (view models, controllers)
    /// that are bound to the main thread but don't conform to Sendable.
    @MainActor
    private var mainCaches: [CacheKey: Any] = [:]

    /// Storage for MainActor-isolated service factory functions.
    /// Factory functions are marked with @MainActor to ensure service creation
    /// happens on the main thread.
    @MainActor
    private var mainProviders: [CacheKey: @MainActor () throws -> Any] = [:]

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
        if let service = caches[key] as? Service {
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
        return $caches.withLock { (caches: inout sending [CacheKey: any Sendable]) -> sending Service in
            // Double-check: another thread might have cached it while we were creating
            if let cachedService = caches[key] as? Service {
                return cachedService
            }

            // Store the newly created service
            caches[key] = newService
            return newService
        }
    }

    /// Registers a Sendable service factory function.
    ///
    /// - Parameters:
    ///   - type: The service type to register.
    ///   - factory: A factory function that creates the service instance. Can throw errors.
    func register<Service: Sendable>(_ type: Service.Type, factory: @escaping @Sendable () throws -> any Sendable) {
        providers[CacheKey(type)] = factory
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
        if let service = mainCaches[key] as? Service {
            return service
        }
        if let factory = mainProviders[key], let service = try factory() as? Service {
            mainCaches[key] = service
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
    @MainActor
    func registerMain<Service>(_ type: Service.Type, factory: @escaping @MainActor () throws -> Service) {
        mainProviders[CacheKey(type)] = factory
    }

    // MARK: - Reset

    /// Clears all cached service instances (both Sendable and MainActor services).
    /// Registered service providers remain intact, so services will be recreated
    /// on the next resolution using their registered factory functions.
    ///
    /// This method is async to ensure MainActor caches are properly cleared
    /// on the main thread, guaranteeing consistency when the method returns.
    func resetCaches() async {
        caches.removeAll()
        await MainActor.run {
            mainCaches.removeAll()
        }
    }

    /// Clears all cached service instances and removes all registered service providers
    /// (both Sendable and MainActor services).
    /// This completely resets the storage to its initial state.
    ///
    /// This method is async to ensure MainActor storage is properly cleared
    /// on the main thread, guaranteeing consistency when the method returns.
    func resetAll() async {
        caches.removeAll()
        providers.removeAll()
        await MainActor.run {
            mainCaches.removeAll()
            mainProviders.removeAll()
        }
    }
}
