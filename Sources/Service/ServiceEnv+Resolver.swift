//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

// MARK: - Sendable Service Resolution

extension ServiceEnv {
    /// Resolves a Sendable service instance by its type.
    ///
    /// This method automatically detects circular dependencies and will throw
    /// a `ServiceError` if a cycle is detected (e.g., A -> B -> C -> A).
    ///
    /// Use this method for services that conform to `Sendable` and were registered
    /// using the `register` methods.
    ///
    /// - Parameter type: The service type to resolve.
    /// - Returns: The resolved service instance.
    /// - Throws: `ServiceError.notRegistered` if the service is not registered,
    ///           `ServiceError.circularDependency` if a circular dependency is detected,
    ///           `ServiceError.maxDepthExceeded` if the resolution depth limit is exceeded,
    ///           or `ServiceError.factoryFailed` if the factory function throws an error.
    ///           If the factory throws a `ServiceError`, it is propagated directly.
    ///
    /// ## Example
    ///
    /// ```swift
    /// do {
    ///     let database = try ServiceEnv.current.resolve(DatabaseProtocol.self)
    /// } catch {
    ///     // Typed throws: error is always ServiceError
    ///     switch error {
    ///     case .notRegistered(let type):
    ///         print("Service not registered: \(type)")
    ///     case .circularDependency(_, let chain):
    ///         print("Circular dependency: \(chain.joined(separator: " -> "))")
    ///     case .maxDepthExceeded(let depth, _):
    ///         print("Max depth \(depth) exceeded")
    ///     case .factoryFailed(let type, let underlyingError):
    ///         print("Failed to create \(type): \(underlyingError)")
    ///     }
    /// }
    /// ```
    @discardableResult
    public func resolve<Service: Sendable>(_ type: Service.Type) throws(ServiceError) -> Service {
        try ServiceContext.withResolutionTracking(type) {
            guard let service = try storage.resolve(type) else {
                throw ServiceError.notRegistered(serviceType: String(describing: Service.self))
            }
            return service
        }
    }
}

// MARK: - MainActor Service Resolution

extension ServiceEnv {
    /// Resolves a MainActor-isolated service instance by its type.
    ///
    /// This method automatically detects circular dependencies and will throw
    /// a `ServiceError` if a cycle is detected (e.g., A -> B -> C -> A).
    ///
    /// Use this method for services that are bound to the main actor and were registered
    /// using the `registerMain` methods. These services don't need to conform to `Sendable`
    /// since they're always accessed from the main thread.
    ///
    /// Usage example:
    /// ```swift
    /// @MainActor
    /// func setupUI() {
    ///     do {
    ///         let viewModel = try ServiceEnv.current.resolveMain(ViewModelService.self)
    ///         viewModel.loadData()
    ///     } catch {
    ///         print("Failed to resolve view model: \(error)")
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter type: The service type to resolve.
    /// - Returns: The resolved service instance.
    /// - Throws: `ServiceError.notRegistered` if the service is not registered,
    ///           `ServiceError.circularDependency` if a circular dependency is detected,
    ///           `ServiceError.maxDepthExceeded` if the resolution depth limit is exceeded,
    ///           or `ServiceError.factoryFailed` if the factory function throws an error.
    ///           If the factory throws a `ServiceError`, it is propagated directly.
    @MainActor
    @discardableResult
    public func resolveMain<Service>(_ type: Service.Type) throws(ServiceError) -> Service {
        try ServiceContext.withResolutionTracking(type) {
            guard let service = try storage.resolveMain(type) else {
                throw ServiceError.notRegistered(serviceType: String(describing: Service.self))
            }
            return service
        }
    }
}
