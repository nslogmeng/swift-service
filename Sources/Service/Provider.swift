//
//  Copyright © 2026 Service Contributors. All rights reserved.
//

// MARK: - Sendable Provider Property Wrapper

/// A property wrapper that resolves a Sendable service on every access.
/// Unlike ``Service``, which caches the resolved instance, `@Provider` delegates
/// caching entirely to the service's registered scope.
///
/// This makes `@Provider` ideal for services registered with `.transient` scope
/// (fresh instance each access) or `.custom` scope (shared within a named scope
/// that can be independently invalidated).
///
/// The environment is captured at initialization time, ensuring consistent behavior
/// regardless of when the property is accessed.
///
/// Usage example:
/// ```swift
/// // Register a transient service
/// env.register(RequestHandler.self, scope: .transient) { RequestHandler() }
///
/// struct Controller {
///     @Provider var handler: RequestHandler  // New instance on every access
/// }
/// ```
///
/// For optional services that may not be registered:
/// ```swift
/// struct Controller {
///     @Provider var analytics: AnalyticsService?  // Returns nil if not registered
/// }
/// ```
@propertyWrapper
public struct Provider<S: Sendable>: Sendable {
    /// The environment captured at initialization time.
    private let env: ServiceEnv

    /// The resolver closure that knows how to resolve the service.
    private let resolver: @Sendable (ServiceEnv) throws -> S

    /// The resolved service instance.
    /// Resolution happens on every access; caching behavior depends on the service's scope.
    ///
    /// - Note: If the service is not registered or resolution fails, this will cause a runtime fatalError.
    ///         For error handling, use `ServiceEnv.current.resolve()` directly with try-catch.
    public var wrappedValue: S {
        do {
            return try resolver(env)
        } catch {
            fatalError("\(error)")
        }
    }

    /// Initializes the provider wrapper.
    /// The service type is inferred from the property type and will be resolved on each access.
    /// The current environment is captured at this point.
    @_disfavoredOverload
    public init() {
        self.env = ServiceEnv.current
        self.resolver = { env in try env.resolve(S.self) }
    }

    /// Initializes the provider wrapper with an explicit service type.
    ///
    /// - Parameter type: The service type to resolve.
    @_disfavoredOverload
    public init(_ type: S.Type) {
        self.env = ServiceEnv.current
        self.resolver = { env in try env.resolve(type) }
    }

    // MARK: - Optional Service Support

    /// Initializes an optional provider wrapper.
    /// If the service is not registered, the property returns `nil` instead of causing a fatal error.
    public init<Wrapped: Sendable>() where S == Wrapped? {
        self.env = ServiceEnv.current
        self.resolver = { env in try? env.resolve(Wrapped.self) }
    }

    /// Initializes an optional provider wrapper with an explicit type.
    ///
    /// - Parameter type: The wrapped service type to resolve.
    public init<Wrapped: Sendable>(_ type: Wrapped.Type) where S == Wrapped? {
        self.env = ServiceEnv.current
        self.resolver = { env in try? env.resolve(type) }
    }
}

// MARK: - MainActor Provider Property Wrapper

/// A property wrapper that resolves a MainActor-isolated service on every access.
/// Unlike ``MainService``, which caches the resolved instance, `@MainProvider` delegates
/// caching entirely to the service's registered scope.
///
/// Use this for MainActor-isolated services where you want the scope to control
/// instance lifecycle, such as transient or custom-scoped services.
///
/// Usage example:
/// ```swift
/// @MainActor
/// class MyViewController {
///     @MainProvider var viewModel: ViewModelService  // Resolved on each access
/// }
/// ```
///
/// For optional services that may not be registered:
/// ```swift
/// @MainActor
/// class MyViewController {
///     @MainProvider var analytics: AnalyticsService?  // Returns nil if not registered
/// }
/// ```
@MainActor
@propertyWrapper
public struct MainProvider<S> {
    /// The environment captured at initialization time.
    private let env: ServiceEnv

    /// The resolver closure that knows how to resolve the service.
    private let resolver: @MainActor (ServiceEnv) throws -> S

    /// The resolved service instance.
    /// Resolution happens on every access; caching behavior depends on the service's scope.
    ///
    /// - Note: If the service is not registered or resolution fails, this will cause a runtime fatalError.
    ///         For error handling, use `ServiceEnv.current.resolveMain()` directly with try-catch.
    public var wrappedValue: S {
        do {
            return try resolver(env)
        } catch {
            fatalError("\(error)")
        }
    }

    /// Initializes the provider wrapper.
    /// The service type is inferred from the property type and will be resolved on each access.
    /// The current environment is captured at this point.
    @_disfavoredOverload
    public init() {
        self.env = ServiceEnv.current
        self.resolver = { env in try env.resolveMain(S.self) }
    }

    /// Initializes the provider wrapper with an explicit service type.
    ///
    /// - Parameter type: The service type to resolve.
    @_disfavoredOverload
    public init(_ type: S.Type) {
        self.env = ServiceEnv.current
        self.resolver = { env in try env.resolveMain(type) }
    }

    // MARK: - Optional MainProvider Support

    /// Initializes an optional provider wrapper.
    /// If the service is not registered, the property returns `nil` instead of causing a fatal error.
    public init<Wrapped>() where S == Wrapped? {
        self.env = ServiceEnv.current
        self.resolver = { env in try? env.resolveMain(Wrapped.self) }
    }

    /// Initializes an optional provider wrapper with an explicit type.
    ///
    /// - Parameter type: The wrapped service type to resolve.
    public init<Wrapped>(_ type: Wrapped.Type) where S == Wrapped? {
        self.env = ServiceEnv.current
        self.resolver = { env in try? env.resolveMain(type) }
    }
}
