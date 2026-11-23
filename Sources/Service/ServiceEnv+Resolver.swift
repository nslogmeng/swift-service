//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

// MARK: - Sendable Service Resolution

extension ServiceEnv {
    /// Resolves a Sendable service.
    ///
    /// A singleton or custom-scoped service is created by its first resolution and then cached.
    /// Concurrent first resolutions run the factory once.
    ///
    /// ```swift
    /// let database = try ServiceEnv.current.resolve(DatabaseProtocol.self)
    /// ```
    ///
    /// - Parameter type: The service type, as it was registered with `register`.
    /// - Returns: The service instance.
    /// - Throws: ``ServiceError/notRegistered(serviceType:)`` if the type has no Sendable registration.
    ///   ``ServiceError/circularDependency(serviceType:chain:)`` if the factory needs the service that
    ///   it creates. ``ServiceError/maxDepthExceeded(depth:chain:)`` at the depth limit.
    ///   ``ServiceError/factoryFailed(serviceType:underlyingError:)`` if the factory throws another
    ///   error. A `ServiceError` from the factory is thrown unchanged.
    @discardableResult
    public func resolve<Service: Sendable>(_ type: Service.Type) throws(ServiceError) -> Service {
        try storage.resolve(type)
    }
}

// MARK: - MainActor Service Resolution

extension ServiceEnv {
    /// Resolves a MainActor service.
    ///
    /// A singleton or custom-scoped service is created by its first resolution and then cached.
    ///
    /// ```swift
    /// let viewModel = try ServiceEnv.current.resolveMain(ViewModelService.self)
    /// ```
    ///
    /// - Parameter type: The service type, as it was registered with `registerMain`.
    /// - Returns: The service instance.
    /// - Throws: ``ServiceError/notRegistered(serviceType:)`` if the type has no MainActor registration.
    ///   ``ServiceError/circularDependency(serviceType:chain:)`` if the factory needs the service that
    ///   it creates. ``ServiceError/maxDepthExceeded(depth:chain:)`` at the depth limit.
    ///   ``ServiceError/factoryFailed(serviceType:underlyingError:)`` if the factory throws another
    ///   error. A `ServiceError` from the factory is thrown unchanged.
    @MainActor
    @discardableResult
    public func resolveMain<Service>(_ type: Service.Type) throws(ServiceError) -> Service {
        try storage.resolveMain(type)
    }
}
