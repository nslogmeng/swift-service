//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

import Foundation

/// A protocol for defining default service implementations.
/// Types conforming to this protocol can be registered directly using `ServiceEnv.register(_:)`.
///
/// Usage example:
/// ```swift
/// struct DatabaseService: ServiceKey {
///     static var `default`: DatabaseService {
///         DatabaseService(connectionString: "sqlite://app.db")
///     }
/// }
///
/// // Register the service
/// ServiceEnv.current.register(DatabaseService.self)
/// ```
public protocol ServiceKey: Sendable {
    /// The default instance of the service.
    static var `default`: Self { get }
}
