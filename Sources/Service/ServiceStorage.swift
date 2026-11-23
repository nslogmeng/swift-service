//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

/// Internal storage system that manages service registrations and cached service instances by type.
/// This class provides thread-safe service storage and retrieval using locking mechanisms
/// to ensure safe concurrent access. Service instances are created and cached on first resolution,
/// and subsequent resolutions return the same instance (singleton behavior).
///
/// Each registration is one entry: the scope, the factory, and for singleton and custom scopes a cache slot.
/// For these scopes, the factory runs at most once per cached instance.
/// Concurrent first resolutions of the same service wait for the one that runs the factory.
///
/// The storage supports two categories of services:
/// - **Sendable services**: Thread-safe services that can be shared across concurrent contexts.
/// - **MainActor services**: Services isolated to the main actor, typically UI-related components
///   like view models.
///
/// One lock guards the registrations of both categories, enabling cross-category
/// mutual exclusion checks during registration. A service type can only be registered as
/// either Sendable or MainActor, not both.
final class ServiceStorage: @unchecked Sendable {
    // MARK: - Provider Entries

    /// A Sendable factory function with its scope and cache slot.
    private struct ProviderEntry: @unchecked Sendable {
        let scope: ServiceScope
        let factory: @Sendable () throws -> any Sendable

        /// The cache slot for singleton and custom scopes.
        /// `nil` for transient and graph scopes, which the storage does not cache.
        let slot: CacheSlot?
    }

    /// A MainActor-isolated factory function with its scope and cache slot.
    /// Safety: The wrapped factory is only called from `@MainActor` methods.
    private struct MainProviderEntry: @unchecked Sendable {
        let scope: ServiceScope
        let factory: @MainActor () throws -> Any

        /// The cache slot for singleton and custom scopes.
        /// `nil` for transient and graph scopes, which the storage does not cache.
        let slot: CacheSlot?
    }

    // MARK: - Cache Slots

    /// The cache slot of one singleton or custom-scoped registration.
    ///
    /// The slot holds `nil` until a factory succeeds, then holds the `CacheBox` of the instance.
    /// The slot's lock is held while the factory runs, which serializes creation for that registration only.
    /// The lock is not recursive: a thread must never lock a slot whose factory it is running.
    private typealias CacheSlot = Locked<AnyCacheBox?>

    /// Returns the cache slot for a new registration with `scope`.
    ///
    /// - Parameters:
    ///   - scope: The scope of the new registration.
    ///   - previous: The scope and slot of the registration that the new one replaces, if there is one.
    /// - Returns: `nil` for transient and graph scopes. The previous slot if the scope does not change,
    ///   so an instance that is already cached stays until a reset. A new, empty slot otherwise.
    private static func slot(
        for scope: ServiceScope,
        replacing previous: (scope: ServiceScope, slot: CacheSlot?)?
    ) -> CacheSlot? {
        switch scope {
        case .singleton, .custom:
            if let previous, previous.scope == scope, let slot = previous.slot {
                return slot
            }
            return CacheSlot()
        case .transient, .graph:
            return nil
        }
    }

    // MARK: - Registry

    /// The registrations of both service categories, keyed by the identifier of the service type.
    ///
    /// The key is the identifier of the static type, `ObjectIdentifier(Service.self)`. The `type` argument
    /// of a generic method can be the metatype of a subclass, which is another identifier.
    private struct Registry: Sendable {
        var providers: [ObjectIdentifier: ProviderEntry] = [:]
        var mainProviders: [ObjectIdentifier: MainProviderEntry] = [:]
    }

    /// Thread-safe storage for all registrations.
    ///
    /// One lock guards both categories. A registration checks the other category, and a reset replaces
    /// the slots of both categories, in one critical section.
    ///
    /// Lock order: the registry lock is held only to look up, insert, replace, or remove entries.
    /// While it is held, no slot lock is acquired, no factory runs, and no entry is released.
    /// Releasing an entry can release a cached instance or the objects that a factory captured, and
    /// a `deinit` of those can call back into this storage. A critical section therefore returns
    /// the entries that it replaces or removes, and the caller passes them to `withExtendedLifetime`
    /// after the lock. Discarding the result is not enough: the optimizer can then release it
    /// inside the critical section.
    @Locked(default: Registry())
    private var registry: Registry

    /// Returns the entry of a Sendable service type. The lookup runs inside the registry lock.
    private func provider(for typeId: ObjectIdentifier) -> ProviderEntry? {
        $registry.withLock { $0.providers[typeId] }
    }

    /// Returns the entry of a MainActor service type. The lookup runs inside the registry lock.
    private func mainProvider(for typeId: ObjectIdentifier) -> MainProviderEntry? {
        $registry.withLock { $0.mainProviders[typeId] }
    }

    /// Creates a new service storage instance.
    init() {}

    // MARK: - Scope Resolution

    /// Resolves a service instance based on its registered scope.
    /// This unified method handles all scope types to eliminate code duplication
    /// between `resolve` and `resolveMain`.
    ///
    /// - Parameters:
    ///   - typeId: The identifier of the service type.
    ///   - scope: The lifecycle scope for the service.
    ///   - slot: The cache slot of the registration. `nil` for transient and graph scopes.
    ///   - factory: A closure that creates a new service instance.
    /// - Returns: The resolved service instance, or nil if the factory returns nil.
    /// - Throws: Rethrows any error from the factory closure.
    /// - Important: The calling thread must not already be running the factory of `slot`, because
    ///   the slot lock is not recursive. Call this method only inside
    ///   `ServiceContext.withResolutionTracking`, which rejects such re-entrant resolution within one task
    ///   with `circularDependency`.
    private func resolveWithScope<Service>(
        typeId: ObjectIdentifier,
        scope: ServiceScope,
        slot: CacheSlot?,
        factory: () throws -> Service?
    ) throws -> Service? {
        if let slot {
            // Singleton and custom scopes share the same caching logic. Each registration has its own slot.
            //
            // The slot lock is held while the factory runs, so concurrent first resolutions of this service
            // wait here and then read the cached box. If the factory throws or returns nil, the slot
            // stays empty and the next resolution runs the factory again.
            // The box is cast outside the lock because `Service` is not required to be Sendable.
            let box = try slot.withLock { (cached: inout sending AnyCacheBox?) throws -> sending AnyCacheBox? in
                if let cached {
                    return cached
                }
                guard let newService = try factory() else {
                    return nil
                }
                let newBox = CacheBox<Service>(newService)
                cached = newBox
                return newBox
            }
            return (box as? CacheBox<Service>)?.value
        }

        if case .graph = scope, let graphCache = ServiceContext.graphCacheBox {
            return try graphCache.resolve(key: .init(storage: self, typeId: typeId), factory: factory)
        }

        // Transient scope. A graph-scoped service without a graph context (e.g., direct storage access)
        // also gets here and behaves like a transient one.
        return try factory()
    }

    /// Returns the box that a slot holds, without resolution tracking.
    ///
    /// Returning a cached instance runs no factory, so there is no cycle to detect and no depth to add.
    /// If another thread is running the factory of the slot, this method waits for it.
    ///
    /// - Parameters:
    ///   - slot: The cache slot of the registration, or `nil` if it has none.
    ///   - typeId: The identifier of the service type.
    /// - Returns: The cached box. `nil` if there is no slot, if the slot is empty, or if the current task
    ///   is resolving `typeId`. In the last case the task can be running the factory of the slot and hold
    ///   its lock, so the caller must continue with `ServiceContext.withResolutionTracking`, which reports
    ///   the cycle.
    private func cachedBox(in slot: CacheSlot?, typeId: ObjectIdentifier) -> AnyCacheBox? {
        guard let slot, !ServiceContext.isResolving(typeId) else {
            return nil
        }
        return slot.withLock { $0 }
    }

    // MARK: - Sendable Services

    /// Resolves a Sendable service instance by its type.
    /// Behavior depends on the service's registered scope:
    /// - `.singleton`: Caches the instance globally (default, backward-compatible).
    /// - `.transient`: Creates a new instance every time, no caching.
    /// - `.graph`: Shares the instance within the current resolution graph.
    /// - `.custom`: Caches the instance within a named scope.
    ///
    /// A cached instance is returned without resolution tracking. Every other resolution runs inside
    /// `ServiceContext.withResolutionTracking`.
    ///
    /// The result is not optional. An `Optional<Service>` result would become a generic argument of
    /// `withResolutionTracking` and `TaskLocal.withValue`, and generic code that is not specialized
    /// looks up the metadata of such a type at run time on every call.
    ///
    /// - Parameter type: The service type.
    /// - Returns: The service instance.
    /// - Throws: `ServiceError.notRegistered` if the type is not registered, or if its factory returns
    ///   a value of another type. Otherwise, the errors of `ServiceContext.withResolutionTracking`.
    func resolve<Service: Sendable>(_ type: Service.Type) throws(ServiceError) -> Service {
        let typeId = ObjectIdentifier(Service.self)
        guard let entry = provider(for: typeId) else {
            throw ServiceError.notRegistered(serviceType: String(describing: Service.self))
        }
        if let box = cachedBox(in: entry.slot, typeId: typeId) as? CacheBox<Service> {
            return box.value
        }
        return try ServiceContext.withResolutionTracking(type) {
            let service = try resolveWithScope(typeId: typeId, scope: entry.scope, slot: entry.slot) {
                try entry.factory() as? Service
            }
            guard let service else {
                throw ServiceError.notRegistered(serviceType: String(describing: Service.self))
            }
            return service
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
        let typeId = ObjectIdentifier(Service.self)
        let (replaced, isMainService) = $registry.withLock { registry -> (ProviderEntry?, Bool) in
            let previous = registry.providers[typeId]
            let slot = Self.slot(for: scope, replacing: previous.map { ($0.scope, $0.slot) })
            registry.providers[typeId] = ProviderEntry(scope: scope, factory: factory, slot: slot)
            return (previous, registry.mainProviders[typeId] != nil)
        }
        withExtendedLifetime(replaced) {}
        if isMainService {
            assertionFailure(
                "Service '\(Service.self)' is already registered as a MainActor service. "
                    + "A service type can only be registered as either Sendable or MainActor, not both."
            )
        }
    }

    // MARK: - MainActor Services

    /// Resolves a MainActor-isolated service instance by its type.
    /// Behavior depends on the service's registered scope:
    /// - `.singleton`: Caches the instance globally (default, backward-compatible).
    /// - `.transient`: Creates a new instance every time, no caching.
    /// - `.graph`: Shares the instance within the current resolution graph.
    /// - `.custom`: Caches the instance within a named scope.
    ///
    /// A cached instance is returned without resolution tracking. Every other resolution runs inside
    /// `ServiceContext.withResolutionTracking`.
    ///
    /// The result is not optional. An `Optional<Service>` result would become a generic argument of
    /// `withResolutionTracking` and `TaskLocal.withValue`, and generic code that is not specialized
    /// looks up the metadata of such a type at run time on every call.
    ///
    /// - Parameter type: The service type.
    /// - Returns: The service instance.
    /// - Throws: `ServiceError.notRegistered` if the type is not registered, or if its factory returns
    ///   a value of another type. Otherwise, the errors of `ServiceContext.withResolutionTracking`.
    @MainActor
    func resolveMain<Service>(_ type: Service.Type) throws(ServiceError) -> Service {
        let typeId = ObjectIdentifier(Service.self)
        guard let entry = mainProvider(for: typeId) else {
            throw ServiceError.notRegistered(serviceType: String(describing: Service.self))
        }
        if let box = cachedBox(in: entry.slot, typeId: typeId) as? CacheBox<Service> {
            return box.value
        }
        return try ServiceContext.withResolutionTracking(type) {
            let service = try resolveWithScope(typeId: typeId, scope: entry.scope, slot: entry.slot) {
                try entry.factory() as? Service
            }
            guard let service else {
                throw ServiceError.notRegistered(serviceType: String(describing: Service.self))
            }
            return service
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
        let typeId = ObjectIdentifier(Service.self)
        let (replaced, isSendableService) = $registry.withLock { registry -> (MainProviderEntry?, Bool) in
            let previous = registry.mainProviders[typeId]
            let slot = Self.slot(for: scope, replacing: previous.map { ($0.scope, $0.slot) })
            registry.mainProviders[typeId] = MainProviderEntry(scope: scope, factory: factory, slot: slot)
            return (previous, registry.providers[typeId] != nil)
        }
        withExtendedLifetime(replaced) {}
        if isSendableService {
            assertionFailure(
                "Service '\(Service.self)' is already registered as a Sendable service. "
                    + "A service type can only be registered as either Sendable or MainActor, not both."
            )
        }
    }

    // MARK: - Reset

    // Reset methods take only the registry lock, so they never wait for a running factory.
    // A resolution whose factory is running during a reset, and the resolutions waiting on its slot,
    // return the instance it creates. That instance stays out of the cache, and later resolutions
    // create a new one.
    //
    // Each method returns the old registry from its critical section and keeps it alive until after
    // the lock. That is where the old slots, and the instances cached in them, are released.

    /// Clears all cached service instances (both Sendable and MainActor services),
    /// including all custom-scoped caches.
    /// Registered service providers remain intact, so services will be recreated
    /// on the next resolution using their registered factory functions.
    func resetCaches() {
        replaceSlots { _ in true }
    }

    /// Clears all cached service instances and removes all registered service providers
    /// (both Sendable and MainActor services).
    /// This completely resets the storage to its initial state.
    func resetAll() {
        let old = $registry.withLock { registry -> Registry in
            let old = registry
            registry = Registry()
            return old
        }
        withExtendedLifetime(old) {}
    }

    /// Clears all cached service instances for a specific scope.
    /// Only affects the target scope; other scopes remain intact.
    ///
    /// - Parameter scope: The scope to clear.
    func resetScope(_ scope: ServiceScope) {
        replaceSlots { $0 == scope }
    }

    /// Gives every registration that has a cache slot and whose scope satisfies `shouldReset` a new,
    /// empty slot. The old slots are not locked, and a resolution that already holds one finishes with it.
    private func replaceSlots(where shouldReset: (ServiceScope) -> Bool) {
        let old = $registry.withLock { registry -> Registry in
            let old = registry
            registry.providers = old.providers.mapValues { entry in
                guard entry.slot != nil, shouldReset(entry.scope) else {
                    return entry
                }
                return ProviderEntry(scope: entry.scope, factory: entry.factory, slot: CacheSlot())
            }
            registry.mainProviders = old.mainProviders.mapValues { entry in
                guard entry.slot != nil, shouldReset(entry.scope) else {
                    return entry
                }
                return MainProviderEntry(scope: entry.scope, factory: entry.factory, slot: CacheSlot())
            }
            return old
        }
        withExtendedLifetime(old) {}
    }
}
