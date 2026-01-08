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

    /// A Sendable wrapper for caching values that may not be Sendable.
    ///
    /// This is safe because:
    /// - Non-Sendable services are only resolved via the `@MainActor` resolve path.
    /// - Access to caches/providers is protected by locking.
    private struct CacheBox: @unchecked Sendable {
        let value: Any
        init(_ value: Any) { self.value = value }
    }

    /// A provider that can either be created from any concurrency domain (Sendable),
    /// or be created only on the main actor (UI/main-thread services).
    private enum Provider: @unchecked Sendable {
        case anyActor(@Sendable () -> any Sendable)
        case mainActor(@MainActor () -> Any)
    }

    /// Thread-safe cache storage for service instances.
    /// Uses a locked dictionary to ensure safe concurrent access.
    @Locked(default: [:])
    private var caches: [CacheKey: CacheBox]

    /// Thread-safe storage for service factory functions.
    @Locked(default: [:])
    private var providers: [CacheKey: Provider]

    /// Creates a new service storage instance.
    init() {}

    // MARK: - Registration

    /// Registers an any-actor service factory.
    ///
    /// - Parameters:
    ///   - type: The service type to register.
    ///   - factory: A factory function that creates the service instance.
    func registerAny<Service: Sendable>(_ type: Service.Type, factory: @escaping @Sendable () -> Service) {
        providers[CacheKey(type)] = .anyActor({ factory() })
    }

    /// Registers a main-actor service factory.
    ///
    /// - Parameters:
    ///   - type: The service type to register.
    ///   - factory: A factory function that creates the service instance on `@MainActor`.
    func registerMain<Service>(_ type: Service.Type, factory: @escaping @MainActor () -> Service) {
        providers[CacheKey(type)] = .mainActor({ factory() })
    }

    // MARK: - Resolution

    /// Resolves an any-actor (Sendable) service instance by its type.
    /// If not in cache, attempts to create a new instance using the registered factory function and caches it.
    ///
    /// - Parameter type: The service type.
    /// - Returns: The service instance, or nil if not registered.
    func resolveAny<Service: Sendable>(_ type: Service.Type) -> Service? {
        let key = CacheKey(type)

        // If the service is registered as @MainActor, do not allow resolving it from a non-main context.
        if let provider = providers[key] {
            switch provider {
            case .mainActor:
                fatalError(
                    "ServiceStorage: \(Service.self) was registered as a @MainActor service. " +
                    "Resolve it from a @MainActor context."
                )
            case .anyActor:
                break
            }
        } else {
            return nil
        }

        if let cached = caches[key]?.value as? Service {
            return cached
        }

        guard let provider = providers[key], case let .anyActor(factory) = provider else {
            return nil
        }

        // Create outside of any long-held lock. Under high contention this may create more than once;
        // factories should be safe to call multiple times.
        let createdAny = factory()
        guard let created = createdAny as? Service else { return nil }

        // Double-check cache before writing (best-effort singleton).
        if let cached = caches[key]?.value as? Service {
            return cached
        }

        caches[key] = CacheBox(created)
        return created
    }

    /// Resolves a service instance by its type on `@MainActor`.
    /// If not in cache, attempts to create a new instance using the registered factory function and caches it.
    ///
    /// - Parameter type: The service type.
    /// - Returns: The service instance, or nil if not registered.
    @MainActor
    func resolveMain<Service>(_ type: Service.Type) -> Service? {
        let key = CacheKey(type)

        if let cached = caches[key]?.value as? Service {
            return cached
        }

        guard let provider = providers[key] else { return nil }

        let createdAny: Any
        switch provider {
        case let .mainActor(factory):
            createdAny = factory()
        case let .anyActor(factory):
            createdAny = factory()
        }

        guard let created = createdAny as? Service else { return nil }

        // Double-check cache before writing (best-effort singleton).
        if let cached = caches[key]?.value as? Service {
            return cached
        }

        caches[key] = CacheBox(created)
        return created
    }

    // MARK: - Reset

    /// Resets all cached service instances.
    /// This clears the entire service cache, forcing all services to be recreated on next resolution.
    func resetCache() {
        caches.removeAll()
    }

    /// Resets cached service instances and registered factories.
    /// This clears both the service cache and provider registry.
    func resetAll() {
        caches.removeAll()
        providers.removeAll()
    }
}
