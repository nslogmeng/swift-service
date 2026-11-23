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

    /// One registration. It is a class, so a resolution copies one reference out of the registry lock.
    private final class Entry: Sendable {
        let scope: ServiceScope
        let factory: Factory

        /// The cache of a singleton or custom-scoped registration. `nil` for transient and graph scopes.
        let slot: CacheSlot?

        init(scope: ServiceScope, factory: Factory, slot: CacheSlot?) {
            self.scope = scope
            self.factory = factory
            self.slot = slot
        }
    }

    /// The cache of one registration. It holds `nil` until a factory succeeds, then the `CacheBox`
    /// of the instance.
    ///
    /// The lock is held while the factory runs, so concurrent first resolutions wait for it.
    /// The lock is not recursive. `ServiceContext` keeps a thread from locking a slot whose factory
    /// it is running.
    private typealias CacheSlot = Locked<AnyCacheBox?>

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
    /// - Throws: `notRegistered` if the type has no Sendable registration.
    ///   Otherwise the errors of `ServiceContext.withResolutionTracking`.
    func resolve<Service: Sendable>(_ type: Service.Type) throws(ServiceError) -> Service {
        guard let entry = entry(for: ObjectIdentifier(Service.self)), case .sendable(let factory) = entry.factory
        else {
            throw Self.notRegistered(Service.self)
        }
        return try resolve(type, from: entry) { try factory() }
    }

    /// Resolves a MainActor service.
    ///
    /// - Throws: `notRegistered` if the type has no MainActor registration.
    ///   Otherwise the errors of `ServiceContext.withResolutionTracking`.
    @MainActor
    func resolveMain<Service>(_ type: Service.Type) throws(ServiceError) -> Service {
        guard let entry = entry(for: ObjectIdentifier(Service.self)), case .main(let factory) = entry.factory
        else {
            throw Self.notRegistered(Service.self)
        }
        return try resolve(type, from: entry) { try factory() }
    }

    /// Returns the cached instance of a registration, or creates one as a step of the resolution chain.
    ///
    /// A cached instance is returned without resolution tracking: no factory runs, so there is no cycle
    /// to detect and no depth to count.
    ///
    /// No instance on this path is optional. `Optional<Service>` as a generic argument or result costs
    /// a metadata lookup at run time on every call, because this code is not specialized.
    ///
    /// - Parameters:
    ///   - entry: The registration of `Service`.
    ///   - create: Calls the factory of `entry`.
    private func resolve<Service>(
        _ type: Service.Type,
        from entry: Entry,
        create: () throws -> Any
    ) throws(ServiceError) -> Service {
        // The slot is read only if this thread does not hold its lock. If it does, it is running
        // the factory of the slot, and resolution tracking below reports the cycle.
        // If another thread is running the factory, the read waits for it.
        if let slot = entry.slot,
            !ServiceContext.isResolving(Service.self, in: self),
            let box = slot.withLock({ $0 }) as? CacheBox<Service>
        {
            return box.value
        }
        return try ServiceContext.withResolutionTracking(type, in: self, locksSlot: entry.slot != nil) { chain in
            func factory() throws -> Service {
                guard let service = try create() as? Service else {
                    throw Self.notRegistered(Service.self)
                }
                return service
            }
            if let slot = entry.slot {
                return try instance(in: slot, factory: factory)
            }
            if case .graph = entry.scope {
                return try chain.graphInstance(for: .init(storage: self, type: Service.self), factory: factory)
            }
            return try factory()
        }
    }

    /// Returns the instance in a slot, or creates and stores one.
    ///
    /// The slot lock is held while the factory runs. Call this method only inside
    /// `ServiceContext.withResolutionTracking`, which rejects a resolution on a thread that holds the lock.
    private func instance<Service>(in slot: CacheSlot, factory: () throws -> Service) throws -> Service {
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

    private static func notRegistered(_ type: any Any.Type) -> ServiceError {
        .notRegistered(serviceType: String(describing: type))
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
