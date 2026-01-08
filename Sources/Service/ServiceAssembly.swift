//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

/// A protocol for defining service registration assemblies.
/// Similar to Swinject's Assembly, this provides a standardized way to organize
/// and register services in a modular, reusable manner.
///
/// **Why `@MainActor`?**
/// Service assembly typically occurs during application initialization, which is a very early
/// stage of the application lifecycle. Assembly operations are strongly dependent on execution
/// order and are usually performed in `main.swift` or SwiftUI App's `init` method, where
/// the code is already running on the main actor. Constraining assembly operations to the
/// main actor ensures thread safety and provides a predictable, sequential execution context
/// for service registration.
///
/// **Note:** This protocol is marked with `@MainActor` for thread safety.
/// The `assemble` method and all `assemble` calls must be executed on the main actor.
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
/// // Assemble the assembly (must be on @MainActor)
/// ServiceEnv.current.assemble(DatabaseAssembly())
/// ```
@MainActor
public protocol ServiceAssembly {
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
    /// **Note:** This method is marked with `@MainActor` and must be called from the main actor context.
    ///
    /// Usage example:
    /// ```swift
    /// ServiceEnv.current.assemble(DatabaseAssembly())
    /// ```
    @MainActor
    public func assemble(_ assembly: ServiceAssembly) {
        assembly.assemble(env: self)
    }

    /// Assembles multiple assemblies to register services in this environment.
    /// Assemblies are assembled in the order they are provided.
    ///
    /// - Parameter assemblies: The assemblies to assemble.
    ///
    /// **Note:** This method is marked with `@MainActor` and must be called from the main actor context.
    ///
    /// Usage example:
    /// ```swift
    /// ServiceEnv.current.assemble([
    ///     DatabaseAssembly(),
    ///     NetworkAssembly(),
    ///     RepositoryAssembly()
    /// ])
    /// ```
    @MainActor
    public func assemble(_ assemblies: [ServiceAssembly]) {
        for assembly in assemblies {
            assembly.assemble(env: self)
        }
    }

    /// Assembles multiple assemblies using variadic arguments.
    ///
    /// - Parameter assemblies: The assemblies to assemble.
    ///
    /// **Note:** This method is marked with `@MainActor` and must be called from the main actor context.
    ///
    /// Usage example:
    /// ```swift
    /// ServiceEnv.current.assemble(
    ///     DatabaseAssembly(),
    ///     NetworkAssembly(),
    ///     RepositoryAssembly()
    /// )
    /// ```
    @MainActor
    public func assemble(_ assemblies: ServiceAssembly...) {
        assemble(assemblies)
    }
}
