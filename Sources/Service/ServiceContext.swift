//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

import Foundation

/// A context object that manages service resolution and dependency tracking.
/// This class is responsible for resolving services while preventing circular dependencies
/// and tracking the resolution depth to avoid infinite recursion.
///
/// The context uses TaskLocal storage to maintain thread-safe access across async contexts
/// and tracks the current resolution chain to detect circular dependencies.
///
/// Usage example:
/// ```swift
/// struct OrderProcessor: ServiceKey {
///     static func build(with context: ServiceContext) -> OrderProcessorProtocol {
///         let paymentService = context.resolve(PaymentService.self)
///         let inventoryService = context.resolve(InventoryService.self)
///         let logger = context.resolve(LoggerService.self)
///
///         return OrderProcessorImpl(
///             payment: paymentService,
///             inventory: inventoryService,
///             logger: logger
///         )
///     }
/// }
/// ```
public final class ServiceContext: @unchecked Sendable {
    /// The current service context for the current task.
    /// Each task gets its own context to ensure isolation.
    @TaskLocal
    static var current = ServiceContext()

    /// The service environment this context operates in.
    let env: ServiceEnv

    /// Tracks the current dependency resolution chain to detect circular dependencies.
    /// Each entry represents a service type currently being resolved.
    @Locked
    private(set) var depth: [String]

    /// Creates a new service context for the specified environment.
    ///
    /// - Parameter env: The service environment to use (defaults to current environment).
    init(env: ServiceEnv = .current) {
        self.env = env
    }

    /// Resolves a service instance for the given ServiceKey type.
    /// This method handles the complete service resolution process including:
    /// - Circular dependency detection
    /// - Resolution depth limiting
    /// - Service caching based on scope
    /// - Dependency chain tracking
    ///
    /// - Parameter key: The ServiceKey type to resolve.
    /// - Returns: The resolved service instance.
    /// - Note: This method will terminate the program if circular dependencies or
    ///         excessive resolution depth are detected.
    public func resolve<Key: ServiceKey>(_ key: Key.Type) -> Key.Value {
        let id = String(describing: Key.Value.self)
        
        // Check for circular dependency
        if depth.contains(id) {
            fatalError("""
            Circular dependency detected for service '\(id)'.
            Dependency chain: \(depth.joined(separator: " -> ")) -> \(id)
            Check your service registration to break the cycle.
            """)
        }

        // Check for excessive resolution depth
        if depth.count > env.maxResolutionDepth {
            fatalError("""
            Maximum dependency resolution depth (\(env.maxResolutionDepth)) exceeded.
            Current resolution chain: \(depth.joined(separator: " -> "))
            This may indicate a circular dependency or overly deep dependency graph.
            """)
        }

        // Track this service in the resolution chain
        depth.append(id)
        defer { depth.removeLast() }

        // Check if service is already cached
        if let service: Key.Value = env.storage[key] {
            return service
        }

        // Build and cache the service
        let service = key.build(with: self)
        env.storage[key] = service
        return service
    }
}
