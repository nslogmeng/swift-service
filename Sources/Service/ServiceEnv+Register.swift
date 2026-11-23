//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

// MARK: - Sendable Service Registration

extension ServiceEnv {
    /// Registers a Sendable service with a factory.
    ///
    /// The factory can resolve other services. An error that it throws is thrown by `resolve(_:)`.
    ///
    /// ```swift
    /// ServiceEnv.current.register(UserRepository.self, scope: .transient) {
    ///     let database = try ServiceEnv.current.resolve(DatabaseProtocol.self)
    ///     return UserRepository(database: database)
    /// }
    /// ```
    ///
    /// Registering a type again replaces its registration.
    ///
    /// - Parameters:
    ///   - type: The service type to register.
    ///   - scope: When the factory runs and how long its instance is kept. The default is `.singleton`.
    ///   - factory: Creates the service instance.
    public func register<Service: Sendable>(
        _ type: Service.Type,
        scope: ServiceScope = .singleton,
        factory: @escaping @Sendable () throws -> Service
    ) {
        storage.register(type, scope: scope, factory: factory)
    }

    /// Registers a ``ServiceKey`` type as a singleton. Its factory returns `Service.default`.
    ///
    /// - Parameter type: The service type to register.
    public func register<Service: ServiceKey>(_ type: Service.Type) {
        storage.register(type, factory: { Service.default })
    }

    /// Registers a ``ServiceKey`` type with a scope. Its factory returns `Service.default`.
    ///
    /// - Parameters:
    ///   - type: The service type to register.
    ///   - scope: When the factory runs and how long its instance is kept.
    public func register<Service: ServiceKey>(_ type: Service.Type, scope: ServiceScope) {
        storage.register(type, scope: scope, factory: { Service.default })
    }

    /// Registers an existing instance as a singleton.
    ///
    /// The `instance` label separates this method from the methods that take a service type. A call that
    /// passes a type without a factory, such as `register(Database.self)`, does not compile unless the type
    /// conforms to ``ServiceKey``.
    ///
    /// - Parameter instance: The instance that every resolution of `Service` returns.
    public func register<Service: Sendable>(instance: Service) {
        storage.register(Service.self, factory: { instance })
    }
}

// MARK: - MainActor Service Registration

extension ServiceEnv {
    /// Registers a MainActor service with a factory.
    ///
    /// The instance is created, cached, and resolved on the main actor. The factory can therefore call
    /// a main-actor-isolated initializer, and the service type does not have to be `Sendable`.
    /// An error that the factory throws is thrown by `resolveMain(_:)`.
    ///
    /// ```swift
    /// ServiceEnv.current.registerMain(ViewModel.self, scope: .transient) {
    ///     let config = try ServiceEnv.current.resolveMain(ConfigService.self)
    ///     return ViewModel(config: config)
    /// }
    /// ```
    ///
    /// Registering a type again replaces its registration.
    ///
    /// - Parameters:
    ///   - type: The service type to register.
    ///   - scope: When the factory runs and how long its instance is kept. The default is `.singleton`.
    ///   - factory: Creates the service instance on the main actor.
    @MainActor
    public func registerMain<Service>(
        _ type: Service.Type,
        scope: ServiceScope = .singleton,
        factory: @escaping @MainActor () throws -> Service
    ) {
        storage.registerMain(type, scope: scope, factory: factory)
    }

    /// Registers an existing instance of a MainActor service as a singleton.
    ///
    /// The `instance` label separates this method from `registerMain(_:scope:factory:)`. A call that passes
    /// a type without a factory, such as `registerMain(ViewModel.self)`, does not compile.
    ///
    /// - Parameter instance: The instance that every resolution of `Service` returns.
    @MainActor
    public func registerMain<Service>(instance: Service) {
        storage.registerMain(Service.self, factory: { instance })
    }
}
