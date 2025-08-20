//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

/// A protocol that defines how service instances are stored and managed within a specific scope.
/// Different scope storage implementations provide different lifecycle and caching behaviors.
///
/// Conforming types must specify whether they cache instances and provide access to the stored instance.
/// The storage is used for reference type services only.
public protocol ObjectScopeStorage: AnyObject, Sendable {
    /// The stored service instance, if available.
    /// May return nil if the instance has been released or was never stored.
    var instance: AnyObject? { get }
    
    /// Indicates whether this storage type caches instances.
    /// If true, the instance will be stored in the service cache.
    /// If false, the instance will not be cached and may be recreated on each access.
    var cache: Bool { get }

    /// Initializes the storage with a service instance.
    ///
    /// - Parameter instance: The service instance to store.
    init(_ instance: AnyObject)
}

/// Shared scope storage that caches instances as singletons.
/// Instances are kept alive until the scope is explicitly reset.
/// This provides singleton behavior where the same instance is returned for all requests.
final class SharedScopeStorage: ObjectScopeStorage, @unchecked Sendable {
    /// The cached service instance.
    let instance: AnyObject?
    
    /// Always caches instances for shared scope.
    let cache: Bool = true

    /// Creates shared storage that holds a strong reference to the instance.
    ///
    /// - Parameter instance: The service instance to cache.
    init(_ instance: AnyObject) {
        self.instance = instance
    }
}

/// Graph scope storage that doesn't cache instances beyond the resolution graph.
/// Instances are available during dependency resolution but not cached long-term.
/// This provides good performance while avoiding memory leaks from long-lived caches.
final class GraphScopeStorage: ObjectScopeStorage, @unchecked Sendable {
    /// The service instance, available during graph resolution.
    let instance: AnyObject?
    
    /// Does not cache instances beyond the current resolution graph.
    let cache: Bool = false

    /// Creates graph storage that temporarily holds the instance.
    ///
    /// - Parameter instance: The service instance to hold during resolution.
    init(_ instance: AnyObject) {
        self.instance = instance
    }
}

/// Transient scope storage that never caches instances.
/// Each request creates a new instance, providing complete isolation.
/// Use this for lightweight services or when fresh instances are always needed.
final class TransientScopeStorage: ObjectScopeStorage, @unchecked Sendable {
    /// Always returns nil since transient instances are not stored.
    let instance: AnyObject? = nil
    
    /// Never caches instances for transient scope.
    let cache: Bool = false

    /// Creates transient storage that doesn't retain the instance.
    /// The instance parameter is ignored since transient services are not cached.
    ///
    /// - Parameter instance: The service instance (ignored for transient scope).
    init(_ instance: AnyObject) {
        // Transient scope doesn't store instances
    }
}

/// Weak scope storage that caches instances with weak references.
/// Instances are automatically released when no strong references exist elsewhere.
/// This provides caching benefits while allowing automatic cleanup.
final class WeakScopeStorage: ObjectScopeStorage, @unchecked Sendable {
    /// The weakly referenced service instance.
    var instance: AnyObject? { _instance }
    
    /// Caches instances using weak references.
    let cache: Bool = true

    /// The weak reference to the service instance.
    private weak var _instance: AnyObject?

    /// Creates weak storage that holds a weak reference to the instance.
    ///
    /// - Parameter instance: The service instance to hold weakly.
    init(_ instance: AnyObject) {
        self._instance = instance
    }
}
