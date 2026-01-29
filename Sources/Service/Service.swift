//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

// MARK: - Sendable Service Property Wrapper

/// A property wrapper that provides immediate dependency injection for Sendable services.
/// The service is resolved eagerly when the property wrapper is initialized.
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
/// // Then use it in your types
/// struct UserController {
///     @Service
///     var database: DatabaseProtocol
/// }
/// ```
@propertyWrapper
public struct Service<S: Sendable>: Sendable {
    /// The resolved service instance.
    public let wrappedValue: S

    /// Initializes the service by resolving it from the current service environment.
    /// The service type is inferred from the property type.
    ///
    /// - Note: If the service is not registered or resolution fails, this will cause a runtime fatalError.
    ///         For error handling, use `ServiceEnv.current.resolve()` directly with try-catch.
    public init() {
        do {
            self.wrappedValue = try ServiceEnv.current.resolve(S.self)
        } catch {
            fatalError("\(error)")
        }
    }

    /// Initializes the service by resolving it from the current service environment.
    /// Allows explicit specification of the service type.
    ///
    /// - Parameter type: The service type to resolve.
    /// - Note: If the service is not registered or resolution fails, this will cause a runtime fatalError.
    ///         For error handling, use `ServiceEnv.current.resolve()` directly with try-catch.
    public init(_ type: S.Type) {
        do {
            self.wrappedValue = try ServiceEnv.current.resolve(type)
        } catch {
            fatalError("\(error)")
        }
    }
}

// MARK: - MainActor Service Property Wrapper

/// A property wrapper that provides immediate dependency injection for MainActor-isolated services.
/// The service is resolved eagerly when the property wrapper is initialized.
///
/// Use this for services that are bound to the main actor and were registered using `registerMain` methods.
/// These services don't need to conform to `Sendable` since they're always accessed from the main thread.
///
/// **Background**: In Swift 6's strict concurrency model, `@MainActor` classes are thread-safe
/// (all access is serialized on the main thread) but are NOT automatically `Sendable`.
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
///     @MainService
///     var viewModel: ViewModelService
/// }
/// ```
@MainActor
@propertyWrapper
public struct MainService<S> {
    /// The resolved service instance.
    public let wrappedValue: S

    /// Initializes the service by resolving it from the current service environment.
    /// The service type is inferred from the property type.
    ///
    /// - Note: If the service is not registered or resolution fails, this will cause a runtime fatalError.
    ///         For error handling, use `ServiceEnv.current.resolveMain()` directly with try-catch.
    public init() {
        do {
            self.wrappedValue = try ServiceEnv.current.resolveMain(S.self)
        } catch {
            fatalError("\(error)")
        }
    }

    /// Initializes the service by resolving it from the current service environment.
    /// Allows explicit specification of the service type.
    ///
    /// - Parameter type: The service type to resolve.
    /// - Note: If the service is not registered or resolution fails, this will cause a runtime fatalError.
    ///         For error handling, use `ServiceEnv.current.resolveMain()` directly with try-catch.
    public init(_ type: S.Type) {
        do {
            self.wrappedValue = try ServiceEnv.current.resolveMain(type)
        } catch {
            fatalError("\(error)")
        }
    }
}
