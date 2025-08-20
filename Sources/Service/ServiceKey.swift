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
/// struct Cat: ServiceKey {
///     static func build(with context: ServiceContext) -> Animal {
///         let owner = context.resolve(Owner.self)
///         return Cat(owner: owner)
///     }
/// }
/// ```
public protocol ServiceKey {
    /// The type of service this key represents.
    /// Defaults to Self if not specified, allowing the key type to also be the service type.
    associatedtype Value: Sendable = Self

    /// The parameters required to resolve the service.
    /// Defaults to Never if not specified, meaning the service does not require parameters.
    associatedtype Params: Hashable & Sendable = Never

    /// Builds and returns an instance of the service.
    /// This method is called when the service needs to be resolved.
    ///
    /// - Parameter context: The service context used for resolving dependencies.
    /// - Returns: A new instance of the service.
    static func build(with context: ServiceContext, params: Params?) -> Value
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
struct HashableKey<T: ServiceKey>: Hashable, Sendable {
    let params: T.Params?

    /// Creates a new HashableKey for the given type.
    init(params: T.Params? = nil) {
        self.params = params
    }

    /// Hashes the wrapped type using its ObjectIdentifier.
    /// This ensures that each unique type gets a unique hash value.
    ///
    /// - Parameter hasher: The hasher to combine the type identifier with.
    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(T.self))
        hasher.combine(params)
    }
}
