//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

/// A Sendable service type that provides its own default instance.
///
/// A conforming type can be registered without a factory:
///
/// ```swift
/// struct DatabaseService: ServiceKey {
///     static var `default`: DatabaseService {
///         DatabaseService(connectionString: "sqlite://app.db")
///     }
/// }
///
/// ServiceEnv.current.register(DatabaseService.self)
/// ```
///
/// The protocol inherits `Sendable`, and `default` is nonisolated. A type whose initializer is
/// isolated to the main actor cannot conform; register it with `registerMain(_:scope:factory:)`.
public protocol ServiceKey: Sendable {
    /// The instance that the factory of the registration returns.
    static var `default`: Self { get }
}
