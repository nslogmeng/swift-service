//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

/// The errors that `resolve(_:)` and `resolveMain(_:)` throw.
///
/// Both methods have typed throws, so a `catch` block gets a `ServiceError`:
///
/// ```swift
/// do {
///     let service = try ServiceEnv.current.resolve(MyService.self)
/// } catch .notRegistered(let type) {
///     print("Not registered: \(type)")
/// } catch {
///     print(error)
/// }
/// ```
public enum ServiceError: Error, CustomStringConvertible, Sendable {
    /// The environment has no registration for the service type.
    ///
    /// `resolve(_:)` finds the registrations of `register`, and `resolveMain(_:)` finds those of
    /// `registerMain`. A type that is registered with one is not registered for the other.
    ///
    /// - Parameter serviceType: The name of the service type.
    case notRegistered(serviceType: String)

    /// The factory of a service needs the service that it creates.
    ///
    /// This error occurs when service A depends on B, B depends on C, and C depends on A.
    ///
    /// It also occurs when another task resolves a singleton or custom-scoped service on the thread
    /// that is running the factory of that service. A nested run loop inside the factory does that.
    ///
    /// - Parameters:
    ///   - serviceType: The service type that was resolved a second time.
    ///   - chain: The service types that were being resolved, outermost first, followed by `serviceType`.
    case circularDependency(serviceType: String, chain: [String])

    /// The number of nested resolutions reached ``ServiceEnv/maxResolutionDepth``.
    ///
    /// - Parameters:
    ///   - depth: The limit.
    ///   - chain: The service types that were being resolved, outermost first.
    case maxDepthExceeded(depth: Int, chain: [String])

    /// The factory of a service threw an error that is not a `ServiceError`.
    ///
    /// A `ServiceError` that a factory throws, for example from a nested resolution, is thrown unchanged.
    ///
    /// - Parameters:
    ///   - serviceType: The name of the service type whose factory failed.
    ///   - underlyingError: The error that the factory threw.
    case factoryFailed(serviceType: String, underlyingError: any Error)

    public var description: String {
        switch self {
        case .notRegistered(let type):
            return "Service '\(type)' is not registered in ServiceEnv"
        case .circularDependency(let type, let chain):
            return """
                Circular dependency detected for service '\(type)'.
                Dependency chain: \(chain.joined(separator: " -> "))
                Check your service registration to break the cycle.
                """
        case .maxDepthExceeded(let depth, let chain):
            return """
                Maximum resolution depth (\(depth)) exceeded.
                Current chain: \(chain.joined(separator: " -> "))
                This may indicate a circular dependency or overly deep dependency graph.
                """
        case .factoryFailed(let serviceType, let underlyingError):
            return "Factory failed to create service '\(serviceType)': \(underlyingError)"
        }
    }
}
