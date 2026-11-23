//
//  Copyright © 2026 Service Contributors. All rights reserved.
//

// MARK: - Sendable Provider Property Wrapper

/// Injects a Sendable service and resolves it on every access.
///
/// The wrapper keeps no instance, so the scope of the registration decides which instance an access
/// returns: a transient service is new on every access, and a custom-scoped service is new after
/// its scope was reset. The wrapper resolves from the environment that was current when the wrapper
/// was initialized. For an instance that the wrapper keeps, use ``Service``.
///
/// ```swift
/// struct Controller {
///     @Provider var handler: RequestHandler
///     @Provider var analytics: AnalyticsService?
/// }
/// ```
///
/// - A property of a service type stops the process with `fatalError` if the resolution fails.
///   To handle the error, call ``ServiceEnv/resolve(_:)``.
/// - A property of an optional service type is `nil` if the service is not registered. Every other
///   resolution error stops the process, as for a property of a service type.
@propertyWrapper
public struct Provider<S: Sendable>: Sendable {
    /// Resolves the service from the environment that was current at initialization time.
    private let resolver: @Sendable () throws -> S

    /// The service instance. Every access resolves it.
    public var wrappedValue: S {
        do {
            return try resolver()
        } catch {
            fatalError("\(error)")
        }
    }

    /// Creates a wrapper for the type of the property.
    @_disfavoredOverload
    public init() {
        self.init(S.self)
    }

    /// Creates a wrapper for a service type.
    ///
    /// - Parameter type: The service type to resolve.
    @_disfavoredOverload
    public init(_ type: S.Type) {
        let env = ServiceEnv.current
        self.resolver = { try env.resolve(type) }
    }

    // MARK: - Optional Service Support

    /// Creates a wrapper for an optional property. The property is `nil` if the service is not registered.
    public init<Wrapped: Sendable>() where S == Wrapped? {
        self.init(Wrapped.self)
    }

    /// Creates a wrapper for an optional property. The property is `nil` if the service is not registered.
    ///
    /// - Parameter type: The service type to resolve.
    public init<Wrapped: Sendable>(_ type: Wrapped.Type) where S == Wrapped? {
        let env = ServiceEnv.current
        self.resolver = { try env.storage.resolveIfRegistered(type) }
    }
}

// MARK: - MainActor Provider Property Wrapper

/// Injects a MainActor service and resolves it on every access.
///
/// The wrapper keeps no instance, so the scope of the registration decides which instance an access
/// returns. The wrapper resolves from the environment that was current when the wrapper was
/// initialized. For an instance that the wrapper keeps, use ``MainService``.
///
/// ```swift
/// @MainActor
/// final class MyViewController {
///     @MainProvider var viewModel: ViewModelService
///     @MainProvider var analytics: AnalyticsService?
/// }
/// ```
///
/// - A property of a service type stops the process with `fatalError` if the resolution fails.
///   To handle the error, call ``ServiceEnv/resolveMain(_:)``.
/// - A property of an optional service type is `nil` if the service is not registered. Every other
///   resolution error stops the process, as for a property of a service type.
@MainActor
@propertyWrapper
public struct MainProvider<S> {
    /// Resolves the service from the environment that was current at initialization time.
    private let resolver: @MainActor () throws -> S

    /// The service instance. Every access resolves it.
    public var wrappedValue: S {
        do {
            return try resolver()
        } catch {
            fatalError("\(error)")
        }
    }

    /// Creates a wrapper for the type of the property.
    @_disfavoredOverload
    public init() {
        self.init(S.self)
    }

    /// Creates a wrapper for a service type.
    ///
    /// - Parameter type: The service type to resolve.
    @_disfavoredOverload
    public init(_ type: S.Type) {
        let env = ServiceEnv.current
        self.resolver = { try env.resolveMain(type) }
    }

    // MARK: - Optional MainProvider Support

    /// Creates a wrapper for an optional property. The property is `nil` if the service is not registered.
    public init<Wrapped>() where S == Wrapped? {
        self.init(Wrapped.self)
    }

    /// Creates a wrapper for an optional property. The property is `nil` if the service is not registered.
    ///
    /// - Parameter type: The service type to resolve.
    public init<Wrapped>(_ type: Wrapped.Type) where S == Wrapped? {
        let env = ServiceEnv.current
        self.resolver = { try env.storage.resolveMainIfRegistered(type) }
    }
}
