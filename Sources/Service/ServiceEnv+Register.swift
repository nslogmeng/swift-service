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
    /// The factory function can throw errors, which will be propagated when
    /// `resolve()` is called. This allows natural error handling when creating
    /// services with dependencies:
    ///
    /// ```swift
    /// ServiceEnv.current.register(UserRepository.self, scope: .transient) {
    ///     let database = try ServiceEnv.current.resolve(DatabaseProtocol.self)
    ///     return UserRepository(database: database)
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - type: The service type to register.
    ///   - scope: The lifecycle scope for the service. Defaults to `.singleton`.
    ///   - factory: A factory function that creates the service instance. Can throw errors.
    public func register<Service: Sendable>(
        _ type: Service.Type,
        scope: ServiceScope = .singleton,
        factory: @escaping @Sendable () throws -> Service
    ) {
        storage.register(type, scope: scope, factory: factory)
    }

    /// Registers a Sendable service using the ServiceKey's default value.
    ///
    /// - Parameter type: A service type conforming to the ServiceKey protocol.
    public func register<Service: ServiceKey>(_ type: Service.Type) {
        storage.register(type, factory: { Service.default })
    }

    /// Registers a Sendable service using the ServiceKey's default value with a specified scope.
    ///
    /// - Parameters:
    ///   - type: A service type conforming to the ServiceKey protocol.
    ///   - scope: The lifecycle scope for the service.
    public func register<Service: ServiceKey>(_ type: Service.Type, scope: ServiceScope) {
        storage.register(type, scope: scope, factory: { Service.default })
    }

    /// Registers a Sendable service instance directly.
    /// The instance will be cached and reused for subsequent resolutions.
    /// This method always uses `.singleton` scope since the instance already exists.
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
    /// The factory function can throw errors, which will be propagated when
    /// `resolveMain()` is called:
    ///
    /// ```swift
    /// ServiceEnv.current.registerMain(ViewModel.self, scope: .transient) {
    ///     let config = try ServiceEnv.current.resolveMain(ConfigService.self)
    ///     return ViewModel(config: config)
    /// }
    /// ```
    ///
    /// **Background**: In Swift 6's strict concurrency model, `@MainActor` classes are
    /// thread-safe (all access is serialized on the main thread) but are NOT automatically
    /// `Sendable`. This method provides a way to register and resolve such services without
    /// requiring `Sendable` conformance.
    ///
    /// - Parameters:
    ///   - type: The service type to register.
    ///   - scope: The lifecycle scope for the service. Defaults to `.singleton`.
    ///   - factory: A MainActor-isolated factory function that creates the service instance. Can throw errors.
    @MainActor
    public func registerMain<Service>(
        _ type: Service.Type,
        scope: ServiceScope = .singleton,
        factory: @escaping @MainActor () throws -> Service
    ) {
        storage.registerMain(type, scope: scope, factory: factory)
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

    /// Registers a MainActor-isolated service using the ServiceKey's default value with a specified scope.
    ///
    /// - Parameters:
    ///   - type: A service type conforming to the ServiceKey protocol.
    ///   - scope: The lifecycle scope for the service.
    @MainActor
    public func registerMain<Service: ServiceKey>(_ type: Service.Type, scope: ServiceScope) {
        storage.registerMain(type, scope: scope, factory: { Service.default })
    }

    /// Registers a MainActor-isolated service instance directly.
    /// The instance will be cached and reused for subsequent resolutions.
    /// This method always uses `.singleton` scope since the instance already exists.
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
