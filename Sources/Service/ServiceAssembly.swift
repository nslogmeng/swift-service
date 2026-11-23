//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

/// A group of registrations that belong together.
///
/// The protocol is isolated to the main actor. Assemblies run during application startup, in a fixed
/// order, and an assembly can then register Sendable services and MainActor services.
///
/// ```swift
/// struct DatabaseAssembly: ServiceAssembly {
///     func assemble(env: ServiceEnv) {
///         env.register(DatabaseProtocol.self) {
///             DatabaseService(connectionString: "sqlite://app.db")
///         }
///     }
/// }
///
/// ServiceEnv.current.assemble(DatabaseAssembly())
/// ```
@MainActor
public protocol ServiceAssembly {
    /// Registers the services of this assembly.
    ///
    /// - Parameter env: The environment to register the services in.
    func assemble(env: ServiceEnv)
}

extension ServiceEnv {
    /// Runs an assembly on this environment.
    ///
    /// - Parameter assembly: The assembly to run.
    @MainActor
    public func assemble(_ assembly: any ServiceAssembly) {
        assembly.assemble(env: self)
    }

    /// Runs assemblies on this environment, in the order of the array.
    ///
    /// - Parameter assemblies: The assemblies to run.
    @MainActor
    public func assemble(_ assemblies: [any ServiceAssembly]) {
        for assembly in assemblies {
            assembly.assemble(env: self)
        }
    }

    /// Runs assemblies on this environment, in the order of the arguments.
    ///
    /// ```swift
    /// ServiceEnv.current.assemble(
    ///     DatabaseAssembly(),
    ///     NetworkAssembly(),
    ///     RepositoryAssembly()
    /// )
    /// ```
    ///
    /// - Parameter assemblies: The assemblies to run.
    @MainActor
    public func assemble(_ assemblies: any ServiceAssembly...) {
        assemble(assemblies)
    }
}
