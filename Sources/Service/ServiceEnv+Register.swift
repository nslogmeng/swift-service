//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

// MARK: - Sendable Service Registration

extension ServiceEnv {
    /// Registers a Sendable service using a factory function.
    ///
    /// Use this method for services that conform to `Sendable` and can be safely
    /// shared across concurrent contexts.
    ///
    /// - Parameters:
    ///   - type: The service type to register.
    ///   - factory: A factory function that creates the service instance.
    public func register<Service: Sendable>(
        _ type: Service.Type,
        factory: @escaping @Sendable () -> Service
    ) {
        storage.register(type, factory: factory)
    }

    /// Registers a Sendable service using the ServiceKey's default value.
    ///
    /// - Parameter type: A service type conforming to the ServiceKey protocol.
    public func register<Service: ServiceKey>(_ type: Service.Type) {
        storage.register(type, factory: { Service.default })
    }

    /// Registers a Sendable service instance directly.
    /// The instance will be cached and reused for subsequent resolutions.
    ///
    /// - Parameter instance: The service instance to register.
    public func register<Service: Sendable>(_ instance: Service) {
        storage.register(Service.self, factory: { instance })
    }
}

// MARK: - MainActor Service Registration

extension ServiceEnv {
    /// Registers a MainActor-isolated service using a factory function.
    ///
    /// Use this method for services that are bound to the main actor, such as UI view models
    /// and controllers. These services don't need to conform to `Sendable` since they're
    /// always accessed from the main thread.
    ///
    /// **Background**: In Swift 6's strict concurrency model, `@MainActor` classes are
    /// thread-safe (all access is serialized on the main thread) but are NOT automatically
    /// `Sendable`. This method provides a way to register and resolve such services without
    /// requiring `Sendable` conformance.
    ///
    /// Usage example:
    /// ```swift
    /// @MainActor
    /// final class ViewModelService {
    ///     var data: String = ""
    ///     func loadData() { /* ... */ }
    /// }
    ///
    /// // Register on main actor context
    /// await MainActor.run {
    ///     ServiceEnv.current.registerMain(ViewModelService.self) {
    ///         ViewModelService()
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - type: The service type to register.
    ///   - factory: A MainActor-isolated factory function that creates the service instance.
    @MainActor
    public func registerMain<Service>(
        _ type: Service.Type,
        factory: @escaping @MainActor () -> Service
    ) {
        storage.registerMain(type, factory: factory)
    }

    /// Registers a MainActor-isolated service using the ServiceKey's default value.
    ///
    /// The service type must conform to `ServiceKey` protocol which provides a default value.
    /// This is a convenience method that creates a factory using the `ServiceKey.default` value.
    ///
    /// - Parameter type: A service type conforming to the ServiceKey protocol.
    @MainActor
    public func registerMain<Service: ServiceKey>(_ type: Service.Type) {
        storage.registerMain(type, factory: { Service.default })
    }

    /// Registers a MainActor-isolated service instance directly.
    /// The instance will be cached and reused for subsequent resolutions.
    ///
    /// Use this when you already have an instance of a MainActor-isolated service
    /// that you want to register directly.
    ///
    /// - Parameter instance: The service instance to register.
    @MainActor
    public func registerMain<Service>(_ instance: Service) {
        storage.registerMain(Service.self, factory: { instance })
    }
}
