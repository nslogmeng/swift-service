//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

/// A property wrapper that provides immediate dependency injection.
/// The service is resolved eagerly when the property wrapper is initialized.
///
/// Usage example:
/// ```swift
/// // First, register the service
/// ServiceEnv.current.register(DatabaseProtocol.self) {
///     DatabaseService()
/// }
///
/// // Then use it in your types
/// struct UserController {
///     @Service
///     var database: DatabaseProtocol
/// }
/// ```
@propertyWrapper
public struct Service<S: Sendable>: Sendable {
    /// The resolved service instance.
    public let wrappedValue: S

    /// Initializes the service by resolving it from the current service environment.
    /// The service type is inferred from the property type.
    ///
    /// - Note: If the service is not registered, this will cause a runtime fatalError.
    public init() {
        self.wrappedValue = ServiceEnv.current.resolve(S.self)
    }

    /// Initializes the service by resolving it from the current service environment.
    /// Allows explicit specification of the service type.
    ///
    /// - Parameter type: The service type to resolve.
    /// - Note: If the service is not registered, this will cause a runtime fatalError.
    public init(_ type: S.Type) {
        self.wrappedValue = ServiceEnv.current.resolve(type)
    }
}
