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
    /// Combines the service type with its scope to support multiple cached instances
    /// of the same type under different scopes (e.g., singleton vs custom).
    struct CacheKey: Hashable, Sendable {
        /// The unique identifier for the service type.
        let typeId: ObjectIdentifier

        /// The scope associated with this cache entry.
        let scope: ServiceScope

        /// Creates a cache key for a service type with a specified scope.
        ///
        /// - Parameters:
        ///   - type: The service type.
        ///   - scope: The scope for this cache entry. Defaults to `.singleton`.
        init<Service>(_ type: Service.Type, scope: ServiceScope = .singleton) {
            self.typeId = ObjectIdentifier(Service.self)
            self.scope = scope
        }
    }

    // MARK: - Box Types

    /// A box that wraps cached service instances (both Sendable and MainActor).
    /// This enables storing any service instance in `@Locked` storage.
    /// Safety: MainActor services are only accessed from `@MainActor` methods.
    private struct CacheBox: @unchecked Sendable {
        let value: Any
    }

    /// A box that wraps a Sendable factory function along with its scope.
    private struct ProviderEntry: @unchecked Sendable {
        let scope: ServiceScope
        let factory: @Sendable () throws -> any Sendable
    }

    /// A box that wraps a MainActor-isolated factory function along with its scope.
    /// Safety: The wrapped factory is only called from `@MainActor` methods.
    private struct MainProviderEntry: @unchecked Sendable {
        let scope: ServiceScope
        let factory: @MainActor () throws -> Any
    }

    // MARK: - Unified Cache Storage

    /// Thread-safe cache storage for all service instances (both Sendable and MainActor).
    /// Uses composite `CacheKey` (type + scope) so singleton and custom-scoped instances
    /// coexist in a single dictionary. Transient and graph scopes bypass this cache entirely.
    @Locked
    private var caches: [CacheKey: CacheBox]

    // MARK: - Provider Storage

    /// Thread-safe storage for Sendable service factory entries (scope + factory).
    @Locked
    private var providers: [CacheKey: ProviderEntry]

    /// Thread-safe storage for MainActor service factory entries (scope + factory).
    @Locked
    private var mainProviders: [CacheKey: MainProviderEntry]

    /// Creates a new service storage instance.
    init() {}

    // MARK: - Scope Resolution

    /// Resolves a service instance based on its registered scope.
    /// This unified method handles all scope types to eliminate code duplication
    /// between `resolve` and `resolveMain`.
    ///
    /// - Parameters:
    ///   - key: The cache key identifying the service type.
    ///   - scope: The lifecycle scope for the service.
    ///   - factory: A closure that creates a new service instance.
    /// - Returns: The resolved service instance, or nil if the factory returns nil.
    /// - Throws: Rethrows any error from the factory closure.
    private func resolveWithScope<Service>(
        key: CacheKey,
        scope: ServiceScope,
        factory: () throws -> Service?
    ) throws -> Service? {
        switch scope {
        case .singleton, .custom:
            // Singleton and custom scopes share the same caching logic.
            // The composite CacheKey (type + scope) ensures isolation between scopes.

            // First, try to get from cache (fast path)
            if let box = caches[key], let service = box.value as? Service {
                return service
            }

            // Create service instance (factory may be slow, so we do it outside the lock)
            guard let newService = try factory() else {
                return nil
            }

            // Use withLock to ensure atomic check-and-set operation (double-check pattern)
            let box = $caches.withLock { (caches: inout sending [CacheKey: CacheBox]) -> sending CacheBox in
                if let existing = caches[key] {
                    return existing
                }
                let newBox = CacheBox(value: newService)
                caches[key] = newBox
                return newBox
            }
            return box.value as? Service

        case .transient:
            return try factory()

        case .graph:
            if let graphCache = ServiceContext.graphCacheBox {
                return try graphCache.resolve(key: key) { try factory() }
            }
            // Fallback: no graph context (e.g., direct storage access), behave like transient
            return try factory()
        }
    }

    // MARK: - Sendable Services

    /// Resolves a Sendable service instance by its type.
    /// Behavior depends on the service's registered scope:
    /// - `.singleton`: Caches the instance globally (default, backward-compatible).
    /// - `.transient`: Creates a new instance every time, no caching.
    /// - `.graph`: Shares the instance within the current resolution graph.
    /// - `.custom`: Caches the instance within a named scope.
    ///
    /// - Parameter type: The service type.
    /// - Returns: The service instance, or nil if not registered.
    /// - Throws: Rethrows any error from the factory function.
    func resolve<Service: Sendable>(_ type: Service.Type) throws -> Service? {
        let providerKey = CacheKey(type)
        guard let entry = providers[providerKey] else {
            return nil
        }
        let cacheKey = CacheKey(type, scope: entry.scope)
        return try resolveWithScope(key: cacheKey, scope: entry.scope) {
            try entry.factory() as? Service
        }
    }

    /// Registers a Sendable service factory function with a specified scope.
    ///
    /// - Parameters:
    ///   - type: The service type to register.
    ///   - scope: The lifecycle scope for the service. Defaults to `.singleton`.
    ///   - factory: A factory function that creates the service instance. Can throw errors.
    /// - Important: The service type must not already be registered as a MainActor service.
    ///   In debug builds, an assertion failure will be triggered if this constraint is violated.
    func register<Service: Sendable>(
        _ type: Service.Type,
        scope: ServiceScope = .singleton,
        factory: @escaping @Sendable () throws -> any Sendable
    ) {
        let key = CacheKey(type)
        if mainProviders[key] != nil {
            assertionFailure(
                "Service '\(Service.self)' is already registered as a MainActor service. "
                    + "A service type can only be registered as either Sendable or MainActor, not both."
            )
        }
        providers[key] = ProviderEntry(scope: scope, factory: factory)
    }

    // MARK: - MainActor Services

    /// Resolves a MainActor-isolated service instance by its type.
    /// Behavior depends on the service's registered scope:
    /// - `.singleton`: Caches the instance globally (default, backward-compatible).
    /// - `.transient`: Creates a new instance every time, no caching.
    /// - `.graph`: Shares the instance within the current resolution graph.
    /// - `.custom`: Caches the instance within a named scope.
    ///
    /// - Parameter type: The service type.
    /// - Returns: The service instance, or nil if not registered.
    /// - Throws: Rethrows any error from the factory function.
    @MainActor
    func resolveMain<Service>(_ type: Service.Type) throws -> Service? {
        let providerKey = CacheKey(type)
        guard let entry = mainProviders[providerKey] else {
            return nil
        }
        let cacheKey = CacheKey(type, scope: entry.scope)
        return try resolveWithScope(key: cacheKey, scope: entry.scope) {
            try entry.factory() as? Service
        }
    }

    /// Registers a MainActor-isolated service factory function with a specified scope.
    ///
    /// Use this for services that must run on the main actor, such as UI view models and controllers.
    /// The factory function is marked with @MainActor to ensure service creation happens on the main thread.
    ///
    /// - Parameters:
    ///   - type: The service type to register.
    ///   - scope: The lifecycle scope for the service. Defaults to `.singleton`.
    ///   - factory: A MainActor-isolated factory function that creates the service instance. Can throw errors.
    /// - Important: The service type must not already be registered as a Sendable service.
    ///   In debug builds, an assertion failure will be triggered if this constraint is violated.
    @MainActor
    func registerMain<Service>(
        _ type: Service.Type,
        scope: ServiceScope = .singleton,
        factory: @escaping @MainActor () throws -> Service
    ) {
        let key = CacheKey(type)
        if providers[key] != nil {
            assertionFailure(
                "Service '\(Service.self)' is already registered as a Sendable service. "
                    + "A service type can only be registered as either Sendable or MainActor, not both."
            )
        }
        mainProviders[key] = MainProviderEntry(scope: scope, factory: factory)
    }

    // MARK: - Reset

    /// Clears all cached service instances (both Sendable and MainActor services),
    /// including all custom-scoped caches.
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

    /// Clears all cached service instances for a specific scope.
    /// Only affects the target scope; other scopes remain intact.
    ///
    /// - Parameter scope: The scope to clear.
    func resetScope(_ scope: ServiceScope) {
        $caches.withLock { caches in
            caches = caches.filter { $0.key.scope != scope }
        }
    }
}
