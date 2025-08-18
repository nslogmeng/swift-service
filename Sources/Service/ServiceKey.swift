//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

/// A protocol that defines how to register and build services in the dependency injection system.
/// Types conforming to this protocol serve as keys for service registration and resolution.
///
/// The protocol requires implementing a static `build(with:)` method that defines how to construct
/// the service instance when it's requested.
///
/// Usage example:
/// ```swift
/// struct UserRepository: ServiceKey {
///     static func build(with context: ServiceContext) -> UserRepositoryProtocol {
///         let database = context.resolve(DatabaseService.self)
///         let logger = context.resolve(LoggerService.self)
///         return UserRepositoryImpl(database: database, logger: logger)
///     }
/// }
/// ```
public protocol ServiceKey {
    /// The type of service this key represents.
    /// Defaults to Self if not specified, allowing the key type to also be the service type.
    associatedtype Value: Sendable = Self

    /// Builds and returns an instance of the service.
    /// This method is called when the service needs to be resolved.
    ///
    /// - Parameter context: The service context used for resolving dependencies.
    /// - Returns: A new instance of the service.
    static func build(with context: ServiceContext) -> Value
}

/// Extension for ServiceKey types where the Value is an AnyObject (reference type).
/// This provides a default scope for object-based services, enabling lifecycle management.
extension ServiceKey where Value: AnyObject {
    /// The default scope for reference type services.
    /// Uses `.graph` scope by default, which means instances are cached within
    /// the current dependency resolution graph but not across different resolutions.
    public static var scope: Scope { .default }
}

/// A type-erased wrapper that makes ServiceKey types hashable for use in collections.
/// This struct enables ServiceKey types to be used as dictionary keys and in sets,
/// which is essential for the service caching mechanism.
struct HashableKey<T>: Hashable, Sendable {
    /// Creates a new HashableKey for the given type.
    init() {}

    /// Hashes the wrapped type using its ObjectIdentifier.
    /// This ensures that each unique type gets a unique hash value.
    ///
    /// - Parameter hasher: The hasher to combine the type identifier with.
    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(T.self))
    }
}
