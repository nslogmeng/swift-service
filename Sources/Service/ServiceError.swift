//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

/// Unified error types for the Service framework.
///
/// `ServiceError` represents all possible errors that can occur during service resolution.
/// These errors are thrown by the `resolve()` and `resolveMain()` methods when service
/// resolution fails.
///
/// ## Error Types
///
/// - ``notRegistered(serviceType:)``: The requested service has not been registered.
/// - ``circularDependency(serviceType:chain:)``: A circular dependency was detected.
/// - ``maxDepthExceeded(depth:chain:)``: The resolution depth limit was exceeded.
///
/// ## Usage
///
/// ```swift
/// do {
///     let service = try ServiceEnv.current.resolve(MyService.self)
/// } catch ServiceError.notRegistered(let type) {
///     print("Service not registered: \(type)")
/// } catch ServiceError.circularDependency(let type, let chain) {
///     print("Circular dependency detected: \(chain.joined(separator: " -> "))")
/// } catch ServiceError.maxDepthExceeded(let depth, let chain) {
///     print("Max depth \(depth) exceeded")
/// }
/// ```
public enum ServiceError: Error, CustomStringConvertible, Sendable {
    /// The requested service has not been registered in the current environment.
    ///
    /// This error occurs when attempting to resolve a service that was never registered
    /// using `register()` or `registerMain()`.
    ///
    /// - Parameter serviceType: The name of the service type that was not found.
    case notRegistered(serviceType: String)

    /// A circular dependency was detected during service resolution.
    ///
    /// This error occurs when service A depends on B, B depends on C, and C depends on A,
    /// creating a cycle that cannot be resolved.
    ///
    /// - Parameters:
    ///   - serviceType: The service type where the cycle was detected.
    ///   - chain: The full dependency chain showing the cycle.
    case circularDependency(serviceType: String, chain: [String])

    /// The maximum resolution depth was exceeded.
    ///
    /// This error occurs when the dependency chain is deeper than the allowed maximum
    /// (default: 100). This usually indicates either a circular dependency that wasn't
    /// detected or an overly complex dependency graph.
    ///
    /// - Parameters:
    ///   - depth: The maximum allowed depth that was exceeded.
    ///   - chain: The current dependency chain when the limit was reached.
    case maxDepthExceeded(depth: Int, chain: [String])

    /// The factory function failed to create the service.
    ///
    /// This error occurs when the factory function throws an error during service creation.
    /// The underlying error is wrapped and can be inspected for details.
    ///
    /// - Parameters:
    ///   - serviceType: The name of the service type that failed to create.
    ///   - underlyingError: The error thrown by the factory function.
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
