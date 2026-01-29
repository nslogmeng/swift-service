//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

/// A context object that manages service resolution and dependency tracking.
///
/// ServiceContext is responsible for:
/// - **Circular dependency detection**: Tracks the current resolution chain and detects
///   when a service attempts to resolve itself (directly or indirectly).
/// - **Resolution depth limiting**: Prevents stack overflow from excessively deep
///   dependency graphs by enforcing a maximum resolution depth.
///
/// The context uses `@TaskLocal` storage to ensure each async task has its own isolated
/// resolution stack, making it safe for concurrent service resolution.
///
/// ## How Circular Dependency Detection Works
///
/// When resolving service A that depends on B, which depends on C, which depends on A:
/// ```
/// resolve(A) -> resolve(B) -> resolve(C) -> resolve(A) // Detected!
/// ```
///
/// The context maintains a stack of service types currently being resolved:
/// 1. Push "A" onto stack -> stack: ["A"]
/// 2. Push "B" onto stack -> stack: ["A", "B"]
/// 3. Push "C" onto stack -> stack: ["A", "B", "C"]
/// 4. Attempt to push "A" -> "A" already in stack -> Circular dependency detected!
///
/// ## Error Handling
///
/// When a circular dependency is detected, a `ServiceError.circularDependency` is thrown:
/// ```swift
/// do {
///     let service = try ServiceEnv.current.resolve(AService.self)
/// } catch ServiceError.circularDependency(let type, let chain) {
///     print("Circular dependency: \(chain.joined(separator: " -> "))")
/// }
/// ```
enum ServiceContext {
    /// The current resolution stack for this task.
    /// Contains type names of services currently being resolved.
    @TaskLocal
    static var resolutionStack: [String] = []

    /// Executes a service resolution with circular dependency tracking.
    ///
    /// This method wraps the actual resolution logic and provides:
    /// - Circular dependency detection by checking if the type is already in the stack
    /// - Resolution depth limiting to prevent stack overflow
    /// - Automatic stack cleanup via TaskLocal scoping
    ///
    /// - Parameters:
    ///   - type: The service type being resolved.
    ///   - resolve: The closure that performs the actual resolution. May throw any error.
    /// - Returns: The resolved service instance.
    /// - Throws: Always throws `ServiceError`. Framework errors (circularDependency, maxDepthExceeded)
    ///           are thrown directly. ServiceError from the resolve closure is propagated.
    ///           Other errors from the resolve closure are wrapped in `factoryFailed`.
    static func withResolutionTracking<Service>(
        _ type: Service.Type,
        resolve: () throws -> Service
    ) throws(ServiceError) -> Service {
        let typeName = String(describing: type)

        // Check for circular dependency
        if resolutionStack.contains(typeName) {
            let chain = resolutionStack + [typeName]
            throw ServiceError.circularDependency(serviceType: typeName, chain: chain)
        }

        // Check for excessive depth
        let maxDepth = ServiceEnv.maxResolutionDepth
        if resolutionStack.count >= maxDepth {
            throw ServiceError.maxDepthExceeded(depth: maxDepth, chain: resolutionStack)
        }

        // Execute with the type added to the resolution stack
        var newStack = resolutionStack
        newStack.append(typeName)

        do {
            return try $resolutionStack.withValue(newStack) {
                try resolve()
            }
        } catch let error as ServiceError {
            // Propagate ServiceError directly (user-thrown or framework-generated)
            throw error
        } catch {
            // Wrap other errors (from factory) in factoryFailed
            throw ServiceError.factoryFailed(serviceType: typeName, underlyingError: error)
        }
    }
}
