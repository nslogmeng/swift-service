//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

/// A property wrapper that provides immediate dependency injection.
/// The service is resolved eagerly when the property wrapper is initialized.
///
/// Usage example:
/// ```swift
/// struct Foo {
///     @Service(Book.self)
///     var book: Book
///
///     @Service(Cat.self)
///     var animal: Animal
/// }
/// ```
@propertyWrapper
public struct Service<S: Sendable>: Sendable {
    /// The resolved service instance.
    public let wrappedValue: S

    /// Initializes the service using a ServiceKey type.
    /// The service is resolved immediately from the current environment.
    ///
    /// - Parameter key: The ServiceKey type that defines how to build the service.
    public init<Key: ServiceKey>(_ key: Key.Type, params: Key.Params? = nil) where Key.Value == S {
        let hashKey = HashableKey<Key>(params: params)
        self.wrappedValue = ServiceEnv.current[hashKey]
    }

    /// Initializes the service using a KeyPath to ServiceEnv.
    /// This allows for more flexible service resolution patterns.
    ///
    /// - Parameter keyPath: A key path to the service in ServiceEnv.
    public init(_ keyPath: KeyPath<ServiceEnv, S> & Sendable) {
        self.wrappedValue = ServiceEnv.current[keyPath: keyPath]
    }
}

/// A property wrapper that provides lazy dependency injection.
/// The service is resolved only when first accessed, improving performance
/// for services that may not be used immediately.
///
/// Usage example:
/// ```swift
/// struct Foo {
///     @LazyService(Book.self)
///     var book: Book
///
///     @LazyService(Cat.self)
///     var animal: Animal
/// }
/// ```
@propertyWrapper
public struct LazyService<S: Sendable>: Sendable {
    /// The service env container used for resolution.
    private let env: ServiceEnv
    /// The key path used to resolve the service.
    private let keyPath: KeyPath<ServiceEnv, S> & Sendable

    /// The lazily resolved service instance.
    /// This property is computed only once and cached thereafter.
    public lazy var wrappedValue: S = {
        return env[keyPath: keyPath]
    }()

    /// Initializes the lazy service using a ServiceKey type.
    ///
    /// - Parameter key: The ServiceKey type that defines how to build the service.
    public init<Key: ServiceKey>(_ key: Key.Type, params: Key.Params? = nil) where Key.Value == S {
        self.init(\ServiceEnv.[HashableKey<Key>(params: params)])
    }

    /// Initializes the lazy service using a KeyPath to ServiceEnv.
    ///
    /// - Parameter keyPath: A key path to the service in ServiceEnv.
    public init(_ keyPath: KeyPath<ServiceEnv, S> & Sendable) {
        self.env = ServiceEnv.current
        self.keyPath = keyPath
    }
}

/// A property wrapper that provides fresh service resolution on each access.
/// Unlike Service and LazyService, this always resolves the service anew,
/// which is useful for transient or stateless services.
///
/// Usage example:
/// ```swift
/// struct Foo {
///     @ServiceProvider(Book.self)
///     var book: Book
///
///     @ServiceProvider(Cat.self)
///     var animal: Animal
/// }
/// ```
@propertyWrapper
public struct ServiceProvider<S: Sendable>: Sendable {
    /// The service env container used for resolution.
    private let env: ServiceEnv
    /// The key path used to resolve the service.
    private let keyPath: KeyPath<ServiceEnv, S> & Sendable

    /// The service instance, resolved fresh on each access.
    public var wrappedValue: S { env[keyPath: keyPath] }

    /// Initializes the service provider using a ServiceKey type.
    ///
    /// - Parameter key: The ServiceKey type that defines how to build the service.
    public init<Key: ServiceKey>(_ key: Key.Type, params: Key.Params? = nil) where Key.Value == S {
        self.init(\ServiceEnv.[HashableKey<Key>(params: params)])
    }

    /// Initializes the service provider using a KeyPath to ServiceEnv.
    ///
    /// - Parameter keyPath: A key path to the service in ServiceEnv.
    public init(_ keyPath: KeyPath<ServiceEnv, S> & Sendable) {
        self.env = ServiceEnv.current
        self.keyPath = keyPath
    }
}
