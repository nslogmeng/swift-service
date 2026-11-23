//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

// MARK: - Sendable Service Property Wrapper

/// A property wrapper that provides lazy dependency injection for Sendable services.
/// The service is resolved lazily when the property is first accessed, and the result
/// is cached for subsequent accesses.
///
/// The environment is captured at initialization time, ensuring consistent behavior
/// regardless of when the property is first accessed.
///
/// Use this for services that conform to `Sendable` and were registered using `register` methods.
///
/// Usage example:
/// ```swift
/// // First, register the service
/// ServiceEnv.current.register(DatabaseProtocol.self) {
///     DatabaseService()
/// }
///
/// // Then use it in your types - resolution happens on first access
/// struct UserController {
///     @Service var database: DatabaseProtocol
/// }
/// ```
///
/// For optional services that may not be registered:
/// ```swift
/// struct UserController {
///     @Service var analytics: AnalyticsService?  // Returns nil if not registered
/// }
/// ```
@propertyWrapper
public struct Service<S: Sendable>: Sendable {
    /// Thread-safe storage for the resolved service instance.
    private let storage: Locked<S?>

    /// Resolves the service from the environment that was current at initialization time.
    private let resolver: @Sendable () throws -> S

    /// The resolved service instance.
    /// Resolution happens lazily on first access and is cached for subsequent accesses.
    ///
    /// - Note: If the service is not registered or resolution fails, this will cause a runtime fatalError.
    ///         For error handling, use `ServiceEnv.current.resolve()` directly with try-catch.
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

    /// Initializes the service wrapper.
    /// The service type is inferred from the property type and will be resolved lazily.
    /// The current environment is captured at this point.
    ///
    /// - Note: If the service is not registered or resolution fails, this will cause a runtime fatalError
    ///         on first access. For error handling, use `ServiceEnv.current.resolve()` directly with try-catch.
    @_disfavoredOverload
    public init() {
        self.init(S.self)
    }

    /// Initializes the service wrapper with an explicit service type.
    /// The service will be resolved lazily using the captured environment.
    ///
    /// - Parameter type: The service type to resolve.
    /// - Note: If the service is not registered or resolution fails, this will cause a runtime fatalError
    ///         on first access. For error handling, use `ServiceEnv.current.resolve()` directly with try-catch.
    @_disfavoredOverload
    public init(_ type: S.Type) {
        let env = ServiceEnv.current
        self.storage = Locked()
        self.resolver = { try env.resolve(type) }
    }

    // MARK: - Optional Service Support

    /// Initializes an optional service wrapper.
    /// If the service is not registered, the property returns `nil` instead of causing a fatal error.
    ///
    /// Usage:
    /// ```swift
    /// struct UserController {
    ///     @Service var analytics: AnalyticsService?  // nil if not registered
    ///
    ///     func trackEvent(_ event: String) {
    ///         analytics?.track(event)  // Safe optional access
    ///     }
    /// }
    /// ```
    public init<Wrapped: Sendable>() where S == Wrapped? {
        self.init(Wrapped.self)
    }

    /// Initializes an optional service wrapper with an explicit type.
    ///
    /// - Parameter type: The wrapped service type to resolve.
    public init<Wrapped: Sendable>(_ type: Wrapped.Type) where S == Wrapped? {
        let env = ServiceEnv.current
        self.storage = Locked()
        self.resolver = { try? env.resolve(type) }
    }
}

// MARK: - MainActor Service Property Wrapper

/// A property wrapper that provides lazy dependency injection for MainActor-isolated services.
/// The service is resolved lazily when the property is first accessed, and the result
/// is cached for subsequent accesses.
///
/// The environment is captured at initialization time, ensuring consistent behavior
/// regardless of when the property is first accessed.
///
/// Use this for services that are bound to the main actor and were registered using `registerMain` methods.
/// These services don't need to conform to `Sendable` since they're always accessed from the main thread.
///
/// **Background**: A main-actor service is created by a `@MainActor` factory and resolved only on
/// the main actor, so its initializer can be main-actor-isolated and its type does not need to be `Sendable`.
/// This property wrapper provides a convenient way to inject such services in UI components.
///
/// Usage example:
/// ```swift
/// @MainActor
/// final class ViewModelService {
///     var data: String = ""
///     func loadData() { /* ... */ }
/// }
///
/// // Register the service
/// await MainActor.run {
///     ServiceEnv.current.registerMain(ViewModelService.self) {
///         ViewModelService()
///     }
/// }
///
/// // Use in a MainActor-isolated type
/// @MainActor
/// class MyViewController {
///     @MainService var viewModel: ViewModelService
/// }
/// ```
///
/// For optional services that may not be registered:
/// ```swift
/// @MainActor
/// class MyViewController {
///     @MainService var analytics: AnalyticsService?  // Returns nil if not registered
/// }
/// ```
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

    /// The resolved service instance.
    /// Resolution happens lazily on first access and is cached for subsequent accesses.
    ///
    /// - Note: If the service is not registered or resolution fails, this will cause a runtime fatalError.
    ///         For error handling, use `ServiceEnv.current.resolveMain()` directly with try-catch.
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

    /// Initializes the service wrapper.
    /// The service type is inferred from the property type and will be resolved lazily.
    /// The current environment is captured at this point.
    ///
    /// - Note: If the service is not registered or resolution fails, this will cause a runtime fatalError
    ///         on first access. For error handling, use `ServiceEnv.current.resolveMain()` directly with try-catch.
    @_disfavoredOverload
    public init() {
        self.init(S.self)
    }

    /// Initializes the service wrapper with an explicit service type.
    /// The service will be resolved lazily using the captured environment.
    ///
    /// - Parameter type: The service type to resolve.
    /// - Note: If the service is not registered or resolution fails, this will cause a runtime fatalError
    ///         on first access. For error handling, use `ServiceEnv.current.resolveMain()` directly with try-catch.
    @_disfavoredOverload
    public init(_ type: S.Type) {
        let env = ServiceEnv.current
        self.storage = Box(nil)
        self.resolver = { try env.resolveMain(type) }
    }

    // MARK: - Optional MainService Support

    /// Initializes an optional MainActor service wrapper.
    /// If the service is not registered, the property returns `nil` instead of causing a fatal error.
    ///
    /// Usage:
    /// ```swift
    /// @MainActor
    /// class MyViewController {
    ///     @MainService var analytics: AnalyticsService?  // nil if not registered
    ///
    ///     func trackEvent(_ event: String) {
    ///         analytics?.track(event)  // Safe optional access
    ///     }
    /// }
    /// ```
    public init<Wrapped>() where S == Wrapped? {
        self.init(Wrapped.self)
    }

    /// Initializes an optional MainActor service wrapper with an explicit type.
    ///
    /// - Parameter type: The wrapped service type to resolve.
    public init<Wrapped>(_ type: Wrapped.Type) where S == Wrapped? {
        let env = ServiceEnv.current
        self.storage = Box(nil)
        self.resolver = { try? env.resolveMain(type) }
    }
}
