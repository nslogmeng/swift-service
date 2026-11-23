//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

/// The registrations of one environment and the instances that they cache.
///
/// A service type has one registration, for a Sendable service or for a MainActor service.
/// For singleton and custom scopes, the factory runs at most once per cached instance.
final class ServiceStorage: Sendable {
    // MARK: - Registrations

    /// The factory of a registration. The case is the category of the service.
    private enum Factory: Sendable {
        case sendable(@Sendable () throws -> any Sendable)
        case main(@MainActor () throws -> Any)

        var isMainActor: Bool {
            if case .main = self { true } else { false }
        }
    }

    private struct Entry: Sendable {
        let scope: ServiceScope
        let factory: Factory

        /// The cache of a singleton or custom-scoped registration. `nil` for transient and graph scopes.
        let slot: CacheSlot?
    }

    /// The cache of one registration. It holds `nil` until a factory succeeds, then the `CacheBox`
    /// of the instance.
    ///
    /// - Sendable registration: the lock is held while the factory runs, so concurrent first resolutions
    ///   wait for it. The lock is not recursive: a thread must not lock a slot whose factory it is running.
    /// - MainActor registration: the main actor serializes creation. The lock is held only to read or
    ///   write the slot, and the slot holds `PendingBox.shared` while the factory runs.
    private typealias CacheSlot = Locked<AnyCacheBox?>

    /// Marks the slot of a MainActor registration whose factory is running.
    ///
    /// Safety: the class has no state.
    private final class PendingBox: AnyCacheBox, @unchecked Sendable {
        static let shared = PendingBox()
    }

    /// All registrations, keyed by `ObjectIdentifier(Service.self)`.
    ///
    /// The key is the static type. The `type` argument of a generic method can be the metatype of
    /// a subclass, which has another identifier.
    ///
    /// While this lock is held, no slot is locked, no factory runs, and no entry is released.
    /// Releasing an entry can run a `deinit` that calls back into this storage. A critical section
    /// returns the entries that it removes, and the caller passes them to `withExtendedLifetime`
    /// after the lock. An unused result is released inside the critical section by an optimized build.
    private let registry = Locked<[ObjectIdentifier: Entry]>()

    private func entry(for typeId: ObjectIdentifier) -> Entry? {
        registry.withLock { $0[typeId] }
    }

    // MARK: - Registration

    func register<Service: Sendable>(
        _ type: Service.Type,
        scope: ServiceScope = .singleton,
        factory: @escaping @Sendable () throws -> any Sendable
    ) {
        install(.sendable(factory), scope: scope, for: Service.self)
    }

    @MainActor
    func registerMain<Service>(
        _ type: Service.Type,
        scope: ServiceScope = .singleton,
        factory: @escaping @MainActor () throws -> Service
    ) {
        install(.main(factory), scope: scope, for: Service.self)
    }

    /// Stores a registration. It replaces an existing registration of the same type.
    ///
    /// The new entry keeps the slot of the entry that it replaces if the scope and the category are
    /// the same, so an instance that is already cached stays until a reset.
    private func install(_ factory: Factory, scope: ServiceScope, for type: any Any.Type) {
        let typeId = ObjectIdentifier(type)
        let replaced = registry.withLock { entries -> Entry? in
            let previous = entries[typeId]
            let slot: CacheSlot?
            switch scope {
            case .singleton, .custom:
                if let previous, previous.scope == scope, previous.factory.isMainActor == factory.isMainActor {
                    slot = previous.slot
                } else {
                    slot = CacheSlot()
                }
            case .transient, .graph:
                slot = nil
            }
            entries[typeId] = Entry(scope: scope, factory: factory, slot: slot)
            return previous
        }
        assert(
            replaced.map { $0.factory.isMainActor == factory.isMainActor } ?? true,
            "Service '\(type)' is registered as both a Sendable and a MainActor service. "
                + "A service type has one registration, and the later one replaces the earlier one."
        )
        withExtendedLifetime(replaced) {}
    }

    // MARK: - Resolution

    /// Resolves a Sendable service.
    ///
    /// A cached instance is returned without resolution tracking: no factory runs, so there is no cycle
    /// to detect and no depth to count.
    ///
    /// No instance on this path is optional. `Optional<Service>` as a generic argument or result costs
    /// a metadata lookup at run time on every call, because this code is not specialized.
    ///
    /// - Throws: `notRegistered` if the type has no Sendable registration.
    ///   Otherwise the errors of `ServiceContext.withResolutionTracking`.
    func resolve<Service: Sendable>(_ type: Service.Type) throws(ServiceError) -> Service {
        let typeId = ObjectIdentifier(Service.self)
        guard let entry = entry(for: typeId), case .sendable(let factory) = entry.factory else {
            throw Self.notRegistered(Service.self)
        }
        if let box = cachedBox(in: entry.slot, typeId: typeId) as? CacheBox<Service> {
            return box.value
        }
        return try ServiceContext.withResolutionTracking(type) {
            try resolveWithScope(typeId: typeId, scope: entry.scope, slot: entry.slot) {
                guard let service = try factory() as? Service else {
                    throw Self.notRegistered(Service.self)
                }
                return service
            }
        }
    }

    /// Resolves a MainActor service. See `resolve(_:)`.
    ///
    /// - Throws: `notRegistered` if the type has no MainActor registration.
    ///   Otherwise the errors of `ServiceContext.withResolutionTracking`.
    @MainActor
    func resolveMain<Service>(_ type: Service.Type) throws(ServiceError) -> Service {
        let typeId = ObjectIdentifier(Service.self)
        guard let entry = entry(for: typeId), case .main(let factory) = entry.factory else {
            throw Self.notRegistered(Service.self)
        }
        if let box = cachedBox(in: entry.slot, typeId: typeId) as? CacheBox<Service> {
            return box.value
        }
        return try ServiceContext.withResolutionTracking(type) {
            try resolveMainWithScope(typeId: typeId, scope: entry.scope, slot: entry.slot) {
                guard let service = try factory() as? Service else {
                    throw Self.notRegistered(Service.self)
                }
                return service
            }
        }
    }

    private static func notRegistered(_ type: any Any.Type) -> ServiceError {
        .notRegistered(serviceType: String(describing: type))
    }

    /// Returns the box that a slot holds, without resolution tracking.
    ///
    /// The result is `nil` if the current task is resolving the type. That task can be running
    /// the factory of the slot and hold its lock, so the caller continues with resolution tracking,
    /// which reports the cycle.
    ///
    /// If another thread is running the factory of a Sendable registration, this method waits for it.
    /// For a MainActor registration whose factory is running, the result is the pending marker.
    private func cachedBox(in slot: CacheSlot?, typeId: ObjectIdentifier) -> AnyCacheBox? {
        guard let slot, !ServiceContext.isResolving(typeId) else {
            return nil
        }
        return slot.withLock { $0 }
    }

    /// Returns or creates the instance of a Sendable registration.
    ///
    /// Call this method only inside `ServiceContext.withResolutionTracking`. It rejects a resolution
    /// of a type that the current task is already resolving, which would lock the slot a second time.
    private func resolveWithScope<Service>(
        typeId: ObjectIdentifier,
        scope: ServiceScope,
        slot: CacheSlot?,
        factory: () throws -> Service
    ) throws -> Service {
        guard let slot else {
            return try resolveUncached(typeId: typeId, scope: scope, factory: factory)
        }

        // If the factory throws, the slot stays empty and the next resolution runs the factory again.
        let box = try slot.withLock { (cached: inout sending AnyCacheBox?) throws -> sending AnyCacheBox in
            if let cached {
                return cached
            }
            let box = CacheBox<Service>(try factory())
            cached = box
            return box
        }
        guard let box = box as? CacheBox<Service> else {
            throw Self.notRegistered(Service.self)
        }
        return box.value
    }

    /// Returns or creates the instance of a MainActor registration.
    ///
    /// No lock is held while the factory runs. A resolution finds the pending marker only if the main
    /// actor runs it before the factory returns, in another task than the one that runs the factory.
    /// A nested run loop inside the factory does that. Such a resolution cannot get the instance and
    /// cannot wait for it on its own thread, so it throws `circularDependency`.
    @MainActor
    private func resolveMainWithScope<Service>(
        typeId: ObjectIdentifier,
        scope: ServiceScope,
        slot: CacheSlot?,
        factory: () throws -> Service
    ) throws -> Service {
        guard let slot else {
            return try resolveUncached(typeId: typeId, scope: scope, factory: factory)
        }

        let found = slot.withLock { (cached: inout sending AnyCacheBox?) -> sending AnyCacheBox? in
            if cached == nil {
                cached = PendingBox.shared
                return nil
            }
            return cached
        }
        if let found {
            guard let box = found as? CacheBox<Service> else {
                throw ServiceContext.circularDependency(Service.self, in: ServiceContext.resolutionStack)
            }
            return box.value
        }

        // If the factory throws, the slot is empty again and the next resolution runs the factory again.
        let box: CacheBox<Service>
        do {
            box = CacheBox(try factory())
        } catch {
            slot.withLock { $0 = nil }
            throw error
        }
        slot.withLock { $0 = box }
        return box.value
    }

    /// Creates the instance of a transient or graph-scoped registration.
    /// A graph-scoped instance is shared through the graph cache of the resolution chain.
    private func resolveUncached<Service>(
        typeId: ObjectIdentifier,
        scope: ServiceScope,
        factory: () throws -> Service
    ) throws -> Service {
        if case .graph = scope, let graphCache = ServiceContext.graphCacheBox {
            return try graphCache.resolve(key: .init(storage: self, typeId: typeId), factory: factory)
        }
        return try factory()
    }

    // MARK: - Reset

    // A reset takes only the registry lock, so it never waits for a running factory. A resolution that
    // already holds an old slot finishes with it and returns the instance created there. That instance
    // stays out of the cache.

    /// Empties the cache of every registration.
    func resetCaches() {
        replaceSlots { _ in true }
    }

    /// Empties the caches of the registrations with `scope`.
    func resetScope(_ scope: ServiceScope) {
        replaceSlots { $0 == scope }
    }

    /// Removes all registrations and their caches.
    func resetAll() {
        let old = registry.withLock { entries -> [ObjectIdentifier: Entry] in
            let old = entries
            entries = [:]
            return old
        }
        withExtendedLifetime(old) {}
    }

    /// Gives each registration that has a slot and whose scope satisfies `shouldReset` a new, empty slot.
    private func replaceSlots(where shouldReset: (ServiceScope) -> Bool) {
        let old = registry.withLock { entries -> [ObjectIdentifier: Entry] in
            let old = entries
            entries = old.mapValues { entry in
                guard entry.slot != nil, shouldReset(entry.scope) else {
                    return entry
                }
                return Entry(scope: entry.scope, factory: entry.factory, slot: CacheSlot())
            }
            return old
        }
        withExtendedLifetime(old) {}
    }
}
