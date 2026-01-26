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
/// ## Error Messages
///
/// When a circular dependency is detected, a fatal error is raised with a clear message:
/// ```
/// Circular dependency detected for service 'AService'.
/// Dependency chain: AService -> BService -> CService -> AService
/// Check your service registration to break the cycle.
/// ```
enum ServiceContext {
    /// The current resolution stack for this task.
    /// Contains type names of services currently being resolved.
    @TaskLocal
    static var resolutionStack: [String] = []

    /// Maximum allowed resolution depth to prevent stack overflow from deep dependencies.
    /// Default is 100, which should be sufficient for most applications.
    @TaskLocal
    static var maxResolutionDepth: Int = 100

    /// Executes a service resolution with circular dependency tracking.
    ///
    /// This method wraps the actual resolution logic and provides:
    /// - Circular dependency detection by checking if the type is already in the stack
    /// - Resolution depth limiting to prevent stack overflow
    /// - Automatic stack cleanup via TaskLocal scoping
    ///
    /// - Parameters:
    ///   - type: The service type being resolved.
    ///   - resolve: The closure that performs the actual resolution.
    /// - Returns: The resolved service instance.
    /// - Note: This method will terminate the program with `fatalError` if circular
    ///         dependencies or excessive resolution depth are detected.
    static func withResolutionTracking<Service>(
        _ type: Service.Type,
        resolve: () -> Service
    ) -> Service {
        let typeName = String(describing: type)

        // Check for circular dependency
        if resolutionStack.contains(typeName) {
            let chain = resolutionStack + [typeName]
            fatalError(
                """
                Circular dependency detected for service '\(typeName)'.
                Dependency chain: \(chain.joined(separator: " -> "))
                Check your service registration to break the cycle.
                """
            )
        }

        // Check for excessive depth
        if resolutionStack.count >= maxResolutionDepth {
            fatalError(
                """
                Maximum resolution depth (\(maxResolutionDepth)) exceeded.
                Current chain: \(resolutionStack.joined(separator: " -> "))
                This may indicate a circular dependency or overly deep dependency graph.
                """
            )
        }

        // Execute with the type added to the resolution stack
        var newStack = resolutionStack
        newStack.append(typeName)

        return $resolutionStack.withValue(newStack) {
            resolve()
        }
    }
}
