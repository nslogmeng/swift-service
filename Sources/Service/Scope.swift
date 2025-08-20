//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

/// Defines the lifecycle and caching behavior of service objects within the current environment storage.
/// Scopes determine how long service instances are kept alive and when they should be released.
///
/// The scope system provides several predefined scopes with different lifecycle characteristics:
/// - `.shared`: Singleton behavior, cached until explicitly reset
/// - `.graph`: Cached within dependency resolution graph only
/// - `.transient`: Never cached, always creates new instances
/// - `.weak`: Cached with weak references, released when no strong references exist
///
/// Usage example:
/// ```swift
/// struct MyService: ServiceKey {
///     static var scope: Scope { .shared } // Singleton database connection
///     
///     static func build(with context: ServiceContext) -> MyServiceProtocol {
///         return MyService()
///     }
/// }
/// ```
public struct Scope: Hashable, Sendable {
    /// The default scope used for reference type services.
    /// Currently set to `.graph` scope.
    public static let `default`: Scope = .graph

    /// Shared scope: Service instances are cached as singletons until explicitly reset.
    /// Use this for expensive-to-create services that should be reused across the application.
    public static let shared = Scope(id: "shared", factory: SharedScopeStorage.init)
    
    /// Graph scope: Service instances are cached only within the current dependency resolution graph.
    /// This is the default scope and provides good performance while avoiding memory leaks.
    public static let graph = Scope(id: "graph", factory: GraphScopeStorage.init)
    
    /// Transient scope: Service instances are never cached, always creating new instances.
    /// Use this for lightweight, stateless services or when you need fresh instances every time.
    public static let transient = Scope(id: "transient", factory: TransientScopeStorage.init)
    
    /// Weak scope: Service instances are cached with weak references.
    /// Instances are automatically released when no strong references exist elsewhere.
    public static let weak = Scope(id: "weak", factory: WeakScopeStorage.init)

    /// A unique identifier for this scope.
    public let id: String
    
    /// A factory function that creates the appropriate storage for this scope.
    /// The factory receives a service instance and returns a storage wrapper.
    public let factory: @Sendable (AnyObject) -> ObjectScopeStorage

    /// Creates a custom scope with the specified identifier and storage factory.
    ///
    /// - Parameters:
    ///   - id: A unique identifier for this scope.
    ///   - factory: A factory function that creates storage for service instances.
    public init(id: String, factory: @Sendable @escaping (AnyObject) -> ObjectScopeStorage) {
        self.id = id
        self.factory = factory
    }

    /// Compares two scopes for equality based on their identifiers.
    ///
    /// - Parameters:
    ///   - lhs: The left-hand scope.
    ///   - rhs: The right-hand scope.
    /// - Returns: True if the scopes have the same identifier.
    public static func == (lhs: Scope, rhs: Scope) -> Bool {
        return lhs.id == rhs.id
    }

    /// Hashes the scope using its identifier.
    ///
    /// - Parameter hasher: The hasher to combine the identifier with.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
