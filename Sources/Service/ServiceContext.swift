//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

import Foundation

/// A context object that manages service resolution and dependency tracking.
/// This class is responsible for resolving services while preventing circular dependencies,
/// tracking the resolution depth to avoid infinite recursion, and passing parameters for
/// parameterized service resolution.
///
/// You can also create custom contexts using the public initializer and inspect the environment via the public `env` property.
/// The context tracks the current resolution chain and parameters for each service type during the resolution graph.
public final class ServiceContext: @unchecked Sendable {
    /// The global service context for the current task, used for dependency resolution.
    /// Each task gets its own context to ensure isolation.
    @TaskLocal
    static var graph = ServiceContext()

    /// The service environment this context operates in.
    public let env: ServiceEnv

    /// Stores the parameters for each service type currently being resolved in the graph.
    /// Used for parameterized service resolution.
    @Locked
    private(set) var graphParams: [ObjectIdentifier: any Sendable]

    /// Tracks the current dependency resolution chain to detect circular dependencies.
    /// Each entry represents a service type currently being resolved.
    @Locked
    private(set) var depth: [String]

    /// Creates a new service context for the specified environment.
    ///
    /// - Parameter env: The service environment to use (defaults to current environment).
    public init(env: ServiceEnv = .current) {
        self.env = env
    }

    /// Resolves a service instance for the given ServiceKey type.
    /// This method handles the complete service resolution process including:
    /// - Circular dependency detection
    /// - Resolution depth limiting
    /// - Service caching based on scope and parameters
    /// - Dependency chain tracking
    /// - Passing parameters for parameterized services
    ///
    /// - Parameter keyType: The ServiceKey type to resolve.
    /// - Parameter params: Optional parameters for service construction.
    /// - Returns: The resolved service instance.
    /// - Note: This method will terminate the program if circular dependencies or
    ///         excessive resolution depth are detected.
    public func resolve<Key: ServiceKey>(_ keyType: Key.Type, params: Key.Params? = nil) -> Key.Value {
        let id = String(describing: Key.Value.self)
        let typeId = ObjectIdentifier(Key.self)
        let key = HashableKey<Key>(params: params)

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

        // Track this service in the resolution chain and store its params for graph resolution
        depth.append(id)
        graphParams[typeId] = params
        defer {
            depth.removeLast()
            graphParams.removeValue(forKey: typeId)
        }

        // Check if service is already cached
        if let service: Key.Value = env.storage[key] {
            return service
        }

        // Build and cache the service
        let service = Key.build(with: self)
        env.storage[key] = service
        return service
    }

    /// Returns the parameters for the given ServiceKey type in the current resolution graph.
    /// Use this in ServiceKey.build to access the parameters passed to resolve.
    ///
    /// - Parameter key: The ServiceKey type.
    /// - Returns: The parameters for this service type, or nil if not parameterized.
    public func resolveCurrentParams<Key: ServiceKey>(for key: Key.Type) -> Key.Params? {
        return graphParams[ObjectIdentifier(key)] as? Key.Params
    }
}
