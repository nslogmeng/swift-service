//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

// MARK: - Sendable Service Resolution

extension ServiceEnv {
    /// Resolves a Sendable service instance by its type.
    /// If the service is not registered, this will cause a runtime fatalError.
    ///
    /// This method automatically detects circular dependencies and will terminate
    /// with a clear error message if a cycle is detected (e.g., A -> B -> C -> A).
    ///
    /// Use this method for services that conform to `Sendable` and were registered
    /// using the `register` methods.
    ///
    /// - Parameter type: The service type to resolve.
    /// - Returns: The resolved service instance.
    @discardableResult
    public func resolve<Service: Sendable>(_ type: Service.Type) -> Service {
        ServiceContext.withResolutionTracking(type) {
            guard let service = storage.resolve(type) else {
                fatalError("Service: \(Service.self) must register in ServiceEnv")
            }
            return service
        }
    }
}

// MARK: - MainActor Service Resolution

extension ServiceEnv {
    /// Resolves a MainActor-isolated service instance by its type.
    /// If the service is not registered, this will cause a runtime fatalError.
    ///
    /// This method automatically detects circular dependencies and will terminate
    /// with a clear error message if a cycle is detected (e.g., A -> B -> C -> A).
    ///
    /// Use this method for services that are bound to the main actor and were registered
    /// using the `registerMain` methods. These services don't need to conform to `Sendable`
    /// since they're always accessed from the main thread.
    ///
    /// Usage example:
    /// ```swift
    /// @MainActor
    /// func setupUI() {
    ///     let viewModel = ServiceEnv.current.resolveMain(ViewModelService.self)
    ///     viewModel.loadData()
    /// }
    /// ```
    ///
    /// - Parameter type: The service type to resolve.
    /// - Returns: The resolved service instance.
    @MainActor
    @discardableResult
    public func resolveMain<Service>(_ type: Service.Type) -> Service {
        ServiceContext.withResolutionTracking(type) {
            guard let service = storage.resolveMain(type) else {
                fatalError("MainActor Service: \(Service.self) must register in ServiceEnv using registerMain")
            }
            return service
        }
    }
}
