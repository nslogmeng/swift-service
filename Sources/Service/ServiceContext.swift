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
/// The context maintains a stack of service types currently being resolved.
/// Types are compared by identity, so distinct types that share a short name are not confused:
/// 1. Push `A` onto stack -> stack: [A]
/// 2. Push `B` onto stack -> stack: [A, B]
/// 3. Push `C` onto stack -> stack: [A, B, C]
/// 4. Attempt to push `A` -> `A` already in stack -> Circular dependency detected!
///
/// Type names are only generated when an error is constructed.
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
    /// Contains the types of services currently being resolved, compared by `ObjectIdentifier`.
    @TaskLocal
    static var resolutionStack: [any Any.Type] = []

    /// The graph cache for the current resolution chain.
    /// When a top-level `resolve()` call begins, a new `GraphCacheBox` is created and propagated
    /// through `@TaskLocal` to all nested resolutions. Services registered with `.graph` scope
    /// use this cache to share instances within the same resolution graph.
    @TaskLocal
    static var graphCacheBox: GraphCacheBox?

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
        let typeID = ObjectIdentifier(type)

        // Each access to a task-local is a lookup in the task's storage, so each one is read once.
        let stack = resolutionStack

        // Check for circular dependency
        if stack.contains(where: { ObjectIdentifier($0) == typeID }) {
            let chain = (stack + [type]).map { String(describing: $0) }
            throw ServiceError.circularDependency(serviceType: String(describing: type), chain: chain)
        }

        // Check for excessive depth
        let maxDepth = ServiceEnv.maxResolutionDepth
        if stack.count >= maxDepth {
            throw ServiceError.maxDepthExceeded(depth: maxDepth, chain: stack.map { String(describing: $0) })
        }

        // Execute with the type added to the resolution stack
        var newStack = stack
        newStack.append(type)

        // Create a new GraphCacheBox at the top-level resolve if one doesn't exist yet
        let newCacheBox = graphCacheBox == nil ? GraphCacheBox() : nil

        do {
            return try $resolutionStack.withValue(newStack) {
                if let newCacheBox {
                    return try $graphCacheBox.withValue(newCacheBox) {
                        try resolve()
                    }
                } else {
                    return try resolve()
                }
            }
        } catch let error as ServiceError {
            // Propagate ServiceError directly (user-thrown or framework-generated)
            throw error
        } catch {
            // Wrap other errors (from factory) in factoryFailed
            throw ServiceError.factoryFailed(serviceType: String(describing: type), underlyingError: error)
        }
    }
}

// MARK: - Graph Cache

extension ServiceContext {
    /// A reference-type cache used for graph-scoped service resolution.
    ///
    /// `GraphCacheBox` is created at the start of a top-level `resolve()` call and
    /// propagated through `@TaskLocal` to all nested resolutions. Services registered
    /// with `.graph` scope store and retrieve instances from this cache.
    ///
    /// The cache is automatically released when the top-level `resolve()` call completes,
    /// since the `@TaskLocal` scope ends and no more references exist.
    final class GraphCacheBox: @unchecked Sendable {
        @Locked
        private var cache: [ServiceStorage.CacheKey: Box<Any>]

        init() {}

        /// Retrieves a cached instance for the given key, or creates and caches one using the factory.
        ///
        /// - Parameters:
        ///   - key: The cache key identifying the service type.
        ///   - factory: A closure that creates a new instance if none is cached.
        /// - Returns: The cached or newly created instance.
        /// - Throws: Rethrows any error from the factory closure.
        func resolve<Service>(key: ServiceStorage.CacheKey, factory: () throws -> Service) rethrows -> Service {
            if let box = $cache.withLock({ (cache: inout sending [ServiceStorage.CacheKey: Box<Any>]) -> Box<Any>? in
                cache[key]
            }), let cached = box.value as? Service {
                return cached
            }
            let instance = try factory()
            $cache.withLock { (cache: inout sending [ServiceStorage.CacheKey: Box<Any>]) in
                cache[key] = Box<Any>(instance)
            }
            return instance
        }
    }
}
