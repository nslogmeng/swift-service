//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

/// A property wrapper that provides immediate dependency injection.
/// The service is resolved eagerly when the property wrapper is initialized.
///
/// Usage example:
/// ```swift
/// struct UserRepository {
///     @Service(DatabaseService.self)
///     var database: DatabaseProtocol
///
///     @Service(LoggerService.self)
///     var logger: LoggerProtocol
///
///     func saveUser(_ user: User) {
///         logger.info("Saving user: \(user.name)")
///         database.save(user)
///     }
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
    public init<Key: ServiceKey>(_ key: Key.Type) where Key.Value == S {
        self.wrappedValue = ServiceEnv.current[key]
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
/// struct AnalyticsManager {
///     @LazyService(MachineLearningService.self)
///     var mlService: MLServiceProtocol
///
///     func processUserBehavior(_ events: [Event]) {
///         // ML service only created if this method is called
///         let insights = mlService.analyze(events)
///         store(insights)
///     }
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
    public init<Key: ServiceKey>(_ key: Key.Type) where Key.Value == S {
        self.init(\ServiceEnv.[HashableKey<Key>()])
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
/// struct RequestHandler {
///     @ServiceProvider(UUIDGenerator.self)
///     var idGenerator: UUIDGeneratorProtocol
///
///     func handleRequest(_ request: Request) -> Response {
///         let requestId = idGenerator.generate() // Fresh UUID each time
///         return Response(id: requestId, data: process(request))
///     }
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
    public init<Key: ServiceKey>(_ key: Key.Type) where Key.Value == S {
        self.init(\ServiceEnv.[HashableKey<Key>()])
    }

    /// Initializes the service provider using a KeyPath to ServiceEnv.
    ///
    /// - Parameter keyPath: A key path to the service in ServiceEnv.
    public init(_ keyPath: KeyPath<ServiceEnv, S> & Sendable) {
        self.env = ServiceEnv.current
        self.keyPath = keyPath
    }
}
