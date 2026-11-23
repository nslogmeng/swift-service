//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

// MARK: - Sendable Service Property Wrapper

/// Injects a Sendable service. The service is resolved on first access, and the wrapper keeps the instance.
///
/// The wrapper resolves from the environment that was current when the wrapper was initialized.
/// Every later access returns the instance of the first access, whatever the scope of the registration.
/// For an instance that follows the scope, use ``Provider``.
///
/// ```swift
/// struct UserController {
///     @Service var database: DatabaseProtocol
///     @Service var analytics: AnalyticsService?
/// }
/// ```
///
/// - A property of a service type stops the process with `fatalError` if the resolution fails.
///   To handle the error, call ``ServiceEnv/resolve(_:)``.
/// - A property of an optional service type is `nil` if the service is not registered. Every other
///   resolution error stops the process, as for a property of a service type.
@propertyWrapper
public struct Service<S: Sendable>: Sendable {
    /// The resolved instance. The lock is held while the service is resolved, so concurrent first
    /// accesses get one instance.
    private let storage: Locked<S?>

    /// Resolves the service from the environment that was current at initialization time.
    private let resolver: @Sendable () throws -> S

    /// The service instance. The first access resolves it.
    public var wrappedValue: S {
        storage.withLock { cached in
            if let service = cached {
                return service
            }
            do {
                let service = try resolver()
                cached = service
                return service
            } catch {
                fatalError("\(error)")
            }
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
        self.storage = Locked()
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
        self.storage = Locked()
        self.resolver = { try env.storage.resolveIfRegistered(type) }
    }
}

// MARK: - MainActor Service Property Wrapper

/// Injects a MainActor service. The service is resolved on first access, and the wrapper keeps the instance.
///
/// The wrapper resolves from the environment that was current when the wrapper was initialized.
/// Every later access returns the instance of the first access, whatever the scope of the registration.
/// For an instance that follows the scope, use ``MainProvider``.
///
/// ```swift
/// @MainActor
/// final class MyViewController {
///     @MainService var viewModel: ViewModelService
///     @MainService var analytics: AnalyticsService?
/// }
/// ```
///
/// - A property of a service type stops the process with `fatalError` if the resolution fails.
///   To handle the error, call ``ServiceEnv/resolveMain(_:)``.
/// - A property of an optional service type is `nil` if the service is not registered. Every other
///   resolution error stops the process, as for a property of a service type.
@MainActor
@propertyWrapper
public struct MainService<S> {
    /// The resolved instance. `Box` lets the nonmutating getter store it, and `@MainActor` protects it.
    ///
    /// The instance is in a `CacheBox` because `Optional<S>` costs a metadata lookup on every read,
    /// and an optional class reference does not.
    private let storage: Box<CacheBox<S>?>

    /// Resolves the service from the environment that was current at initialization time.
    private let resolver: @MainActor () throws -> S

    /// The service instance. The first access resolves it.
    public var wrappedValue: S {
        if let cached = storage.value {
            return cached.value
        }
        do {
            let service = try resolver()
            storage.value = CacheBox(service)
            return service
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
        self.storage = Box(nil)
        self.resolver = { try env.resolveMain(type) }
    }

    // MARK: - Optional MainService Support

    /// Creates a wrapper for an optional property. The property is `nil` if the service is not registered.
    public init<Wrapped>() where S == Wrapped? {
        self.init(Wrapped.self)
    }

    /// Creates a wrapper for an optional property. The property is `nil` if the service is not registered.
    ///
    /// - Parameter type: The service type to resolve.
    public init<Wrapped>(_ type: Wrapped.Type) where S == Wrapped? {
        let env = ServiceEnv.current
        self.storage = Box(nil)
        self.resolver = { try env.storage.resolveMainIfRegistered(type) }
    }
}
