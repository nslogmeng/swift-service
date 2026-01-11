//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

extension ServiceEnv {
    /// Registers a service using a factory function.
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

    /// Registers a service using the ServiceKey's default value.
    ///
    /// - Parameter type: A service type conforming to the ServiceKey protocol.
    public func register<Service: ServiceKey>(_ type: Service.Type) {
        storage.register(type, factory: { Service.default })
    }

    /// Registers a service instance directly.
    /// The instance will be cached and reused for subsequent resolutions.
    ///
    /// - Parameter instance: The service instance to register.
    public func register<Service: Sendable>(_ instance: Service) {
        storage.register(Service.self, factory: { instance })
    }
}
