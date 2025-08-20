//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

/// Internal storage system that manages cached service instances based on their types and scopes.
/// This class provides thread-safe storage and retrieval of services, handling both value types
/// and reference types with different scope-based lifecycle management.
final class ServiceStorage: @unchecked Sendable {
    
    /// A cache key that uniquely identifies a service instance in storage.
    /// Combines the service type identifier with its scope information for proper isolation.
    struct CacheKey: Hashable, Sendable {
        /// The unique identifier for the service type.
        let typeId: ObjectIdentifier

        /// The unique hash value for service params.
        let paramsHashValue: Int

        /// The scope associated with this service, if it's a reference type.
        /// Value types don't have scopes, so this will be nil.
        let scope: Scope?

        /// Creates a cache key for value type services (no scope).
        ///
        /// - Parameter key: The ServiceKey type.
        init<Key: ServiceKey>(_ key: HashableKey<Key>) {
            self.typeId = ObjectIdentifier(Key.self)
            self.paramsHashValue = key.params?.hashValue ?? 0
            self.scope = nil
        }

        /// Creates a cache key for reference type services (with scope).
        ///
        /// - Parameter key: The ServiceKey type where Value is AnyObject.
        init<Key: ServiceKey>(_ key: HashableKey<Key>) where Key.Value: AnyObject {
            self.typeId = ObjectIdentifier(Key.self)
            self.paramsHashValue = key.params?.hashValue ?? 0
            self.scope = Key.scope
        }
    }

    /// Thread-safe cache storage for service instances.
    /// Uses a locked dictionary to ensure concurrent access safety.
    @Locked
    private var caches: [CacheKey: any Sendable]

    /// Creates a new service storage instance.
    init() {}

    /// Subscript for value type services that don't use scopes.
    /// Provides direct storage and retrieval of service instances.
    subscript<Key: ServiceKey>(_ key: HashableKey<Key>) -> Key.Value? {
        get { caches[CacheKey(key)] as? Key.Value }
        set { caches[CacheKey(key)] = newValue }
    }

    /// Subscript for reference type services that use scope-based storage.
    /// Handles scope-specific storage patterns and caching decisions.
    subscript<Key: ServiceKey>(_ key: HashableKey<Key>) -> Key.Value? where Key.Value: AnyObject {
        get {
            let storage = caches[CacheKey(key)] as? ObjectScopeStorage
            return storage?.instance as? Key.Value
        }
        set {
            let storage = newValue.map({ Key.scope.factory($0) })
            if storage?.cache ?? false {
                caches[CacheKey(key)] = storage
            } else {
                caches[CacheKey(key)] = nil
            }
        }
    }

    /// Resets all cached services for a specific scope.
    /// This removes all service instances that belong to the specified scope,
    /// effectively clearing their cache and forcing recreation on next access.
    ///
    /// - Parameter scope: The scope to reset.
    func reset(scope: Scope) {
        caches.keys
            .filter({ $0.scope == scope })
            .forEach({ caches.removeValue(forKey: $0) })
    }

    /// Resets all cached services in this storage.
    /// This clears the entire service cache, forcing all services to be recreated.
    func reset() {
        caches.removeAll()
    }
}
