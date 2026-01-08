//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

/// A protocol for defining service registration assemblies.
/// Similar to Swinject's Assembly, this provides a standardized way to organize
/// and register services in a modular, reusable manner.
///
/// Usage example:
/// ```swift
/// struct DatabaseAssembly: ServiceAssembly {
///     func assemble(env: ServiceEnv) {
///         env.register(DatabaseProtocol.self) {
///             DatabaseService(connectionString: "sqlite://app.db")
///         }
///     }
/// }
///
/// // Assemble the assembly
/// ServiceEnv.current.assemble(DatabaseAssembly())
/// ```
public protocol ServiceAssembly: Sendable {
    /// Assembles services by registering them in the given environment.
    ///
    /// - Parameter env: The service environment to register services in.
    func assemble(env: ServiceEnv)
}

/// Extension to ServiceEnv for assembling services.
extension ServiceEnv {
    /// Assembles a single assembly to register services in this environment.
    ///
    /// - Parameter assembly: The assembly to assemble.
    ///
    /// Usage example:
    /// ```swift
    /// ServiceEnv.current.assemble(DatabaseAssembly())
    /// ```
    public func assemble(_ assembly: ServiceAssembly) {
        assembly.assemble(env: self)
    }

    /// Assembles multiple assemblies to register services in this environment.
    /// Assemblies are assembled in the order they are provided.
    ///
    /// - Parameter assemblies: The assemblies to assemble.
    ///
    /// Usage example:
    /// ```swift
    /// ServiceEnv.current.assemble([
    ///     DatabaseAssembly(),
    ///     NetworkAssembly(),
    ///     RepositoryAssembly()
    /// ])
    /// ```
    public func assemble(_ assemblies: [ServiceAssembly]) {
        for assembly in assemblies {
            assembly.assemble(env: self)
        }
    }

    /// Assembles multiple assemblies using variadic arguments.
    ///
    /// - Parameter assemblies: The assemblies to assemble.
    ///
    /// Usage example:
    /// ```swift
    /// ServiceEnv.current.assemble(
    ///     DatabaseAssembly(),
    ///     NetworkAssembly(),
    ///     RepositoryAssembly()
    /// )
    /// ```
    public func assemble(_ assemblies: ServiceAssembly...) {
        assemble(assemblies)
    }
}
