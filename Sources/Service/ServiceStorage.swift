//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

/// Internal storage system that manages cached service instances based on their types.
/// This class provides thread-safe service storage and retrieval using locking mechanisms
/// to ensure safe concurrent access. Service instances are created and cached on first resolution,
/// and subsequent resolutions return the same instance (singleton behavior).
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

    /// Thread-safe cache storage for service instances.
    /// Uses a locked dictionary to ensure safe concurrent access.
    @Locked
    private var caches: [CacheKey: any Sendable]

    /// Thread-safe storage for service factory functions.
    @Locked
    private var providers: [CacheKey: @Sendable () -> any Sendable]

    /// Creates a new service storage instance.
    init() {}

    /// Resolves a service instance by its type.
    /// If not in cache, attempts to create a new instance using the registered factory function and caches it.
    ///
    /// - Parameter type: The service type.
    /// - Returns: The service instance, or nil if not registered.
    func resolve<Service: Sendable>(_ type: Service.Type) -> Service? {
        let key = CacheKey(type)
        if let service = caches[key] as? Service {
            return service
        }
        if let factory = providers[key], let service = factory() as? Service {
            caches[key] = service
            return service
        }
        return nil
    }

    /// Registers a service factory function.
    ///
    /// - Parameters:
    ///   - type: The service type to register.
    ///   - factory: A factory function that creates the service instance.
    func register<Service: Sendable>(_ type: Service.Type, factory: @escaping @Sendable () -> any Sendable) {
        providers[CacheKey(type)] = factory
    }

    /// Clears all cached service instances.
    /// Registered service providers remain intact, so services will be recreated
    /// on the next resolution using their registered factory functions.
    func resetCaches() {
        caches.removeAll()
    }

    /// Clears all cached service instances and removes all registered service providers.
    /// This completely resets the storage to its initial state.
    func resetAll() {
        caches.removeAll()
        providers.removeAll()
    }
}
