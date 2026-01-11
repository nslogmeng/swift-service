//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

extension ServiceEnv {
    /// Resolves a service instance by its type.
    /// If the service is not registered, this will cause a runtime fatalError.
    ///
    /// - Parameter type: The service type to resolve.
    /// - Returns: The resolved service instance.
    public func resolve<Service: Sendable>(_ type: Service.Type) -> Service {
        guard let service = storage.resolve(type) else {
            fatalError("Service: \(Service.self) must register in ServiceEnv")
        }
        return service
    }
}
