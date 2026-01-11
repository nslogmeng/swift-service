//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

import Foundation

@testable import Service

// MARK: - Test Service Protocols

protocol DatabaseProtocol: Sendable {
    func connect() -> String
    func query(_ sql: String) -> [String]
    func disconnect()
}

protocol LoggerProtocol: Sendable {
    func info(_ message: String)
    func error(_ message: String)
    func debug(_ message: String)
}

protocol UserRepositoryProtocol: Sendable {
    func createUser(name: String) -> User
    func findUser(id: String) -> User?
    func deleteUser(id: String) -> Bool
}

protocol NetworkServiceProtocol: Sendable {
    func get(url: String) async throws -> Data
    func post(url: String, data: Data) async throws -> Data
}

// MARK: - Test Service Implementations

struct User: Sendable {
    let id: String
    let name: String
    let createdAt: Date
}

final class DatabaseService: DatabaseProtocol, @unchecked Sendable {
    private let connectionString: String

    init(connectionString: String = "sqlite://memory") {
        self.connectionString = connectionString
    }

    func connect() -> String {
        return "Connected to \(connectionString)"
    }

    func query(_ sql: String) -> [String] {
        return ["Result for: \(sql)"]
    }

    func disconnect() {
        // Cleanup connection
    }
}

final class LoggerService: LoggerProtocol, @unchecked Sendable {
    private let level: String

    init(level: String = "INFO") {
        self.level = level
    }

    func info(_ message: String) {
        // print("[\(level)] INFO: \(message)")
    }

    func error(_ message: String) {
        // print("[\(level)] ERROR: \(message)")
    }

    func debug(_ message: String) {
        // print("[\(level)] DEBUG: \(message)")
    }
}

final class UserRepository: UserRepositoryProtocol, @unchecked Sendable {
    private let database: DatabaseProtocol
    private let logger: LoggerProtocol

    init(database: DatabaseProtocol, logger: LoggerProtocol) {
        self.database = database
        self.logger = logger
    }

    func createUser(name: String) -> User {
        let user = User(id: UUID().uuidString, name: name, createdAt: Date())
        logger.info("Creating user: \(name)")
        _ = database.query("INSERT INTO users (id, name) VALUES ('\(user.id)', '\(name)')")
        return user
    }

    func findUser(id: String) -> User? {
        logger.debug("Finding user with id: \(id)")
        let results = database.query("SELECT * FROM users WHERE id = '\(id)'")
        return results.isEmpty ? nil : User(id: id, name: "Found User", createdAt: Date())
    }

    func deleteUser(id: String) -> Bool {
        logger.info("Deleting user: \(id)")
        _ = database.query("DELETE FROM users WHERE id = '\(id)'")
        return true
    }
}

final class NetworkService: NetworkServiceProtocol, @unchecked Sendable {
    private let baseURL: String
    private let logger: LoggerProtocol

    init(baseURL: String, logger: LoggerProtocol) {
        self.baseURL = baseURL
        self.logger = logger
    }

    func get(url: String) async throws -> Data {
        logger.debug("GET request to: \(url)")
        return "GET response".data(using: .utf8) ?? Data()
    }

    func post(url: String, data: Data) async throws -> Data {
        logger.debug("POST request to: \(url)")
        return "POST response".data(using: .utf8) ?? Data()
    }
}

// MARK: - ServiceKey Implementations

struct DatabaseServiceKey: ServiceKey {
    static var `default`: DatabaseServiceKey {
        DatabaseServiceKey()
    }
}

struct LoggerServiceKey: ServiceKey {
    static var `default`: LoggerServiceKey {
        LoggerServiceKey()
    }
}

// MARK: - MainActor Test Services

/// A MainActor-isolated service for testing.
/// This class is thread-safe (all access serialized on main thread) but NOT Sendable.
@MainActor
final class ViewModelService {
    var data: String = "initial"
    var loadCount: Int = 0

    func loadData() {
        data = "loaded"
        loadCount += 1
    }
}

/// A simple MainActor-isolated class for testing custom factory registration.
@MainActor
final class MainActorConfigService {
    var config: String = "default-config"
}

// MARK: - Additional MainActor Test Services

/// Simple MainActor service classes for testing different service types.
@MainActor
final class ServiceA {
    var value: String = "A"
}

@MainActor
final class ServiceB {
    var value: String = "B"
}

@MainActor
final class ServiceC {
    var value: String = "C"
}

/// MainActor service state class for testing direct instance registration.
@MainActor
final class MainState {
    var count: Int = 0
    var message: String = "initial"
}

/// MainActor services with nested dependencies for testing dependency resolution.
@MainActor
final class MainServiceA {
    var value: String = "A"
}

@MainActor
final class MainServiceB {
    let serviceA: MainServiceA
    var value: String = "B"

    init(serviceA: MainServiceA) {
        self.serviceA = serviceA
    }
}

@MainActor
final class MainServiceC {
    let serviceB: MainServiceB
    var value: String = "C"

    init(serviceB: MainServiceB) {
        self.serviceB = serviceB
    }
}

/// MainActor service that conforms to ServiceKey protocol for testing.
@MainActor
@preconcurrency
final class MainActorKeyService: ServiceKey {
    var value: String = "default-value"

    nonisolated static var `default`: MainActorKeyService {
        // This is safe because we're creating a new instance
        MainActorKeyService()
    }
}

// MARK: - ServiceAssembly Test Implementations

struct DatabaseAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.register(DatabaseProtocol.self) {
            DatabaseService(connectionString: "sqlite://assembly.db")
        }
    }
}

struct LoggerAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.register(LoggerProtocol.self) {
            LoggerService(level: "ASSEMBLY")
        }
    }
}

struct RepositoryAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.register(UserRepositoryProtocol.self) {
            let database = env.resolve(DatabaseProtocol.self)
            let logger = env.resolve(LoggerProtocol.self)
            return UserRepository(database: database, logger: logger)
        }
    }
}

struct NetworkAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.register(NetworkServiceProtocol.self) {
            let logger = env.resolve(LoggerProtocol.self)
            return NetworkService(baseURL: "https://api.assembly.com", logger: logger)
        }
    }
}

// MARK: - Additional Test Helper Types

/// Counter class for tracking factory call counts in tests.
final class CallCounter: @unchecked Sendable {
    var count: Int = 0
}

/// Counter class for tracking instance IDs in tests.
final class InstanceCounter: @unchecked Sendable {
    var id: Int = 0
}

/// Flag class for tracking initialization state in tests.
final class InitFlag: @unchecked Sendable {
    var value: Bool = false
}

/// Configuration struct for testing struct type registration.
struct Config: Sendable {
    let apiKey: String
    let timeout: Int
}

/// MainActor configuration struct for testing.
/// Marked as Sendable so it can be used in both Sendable and MainActor contexts.
struct MainConfig: Sendable {
    let theme: String
    let fontSize: Int
}

/// Application configuration struct for testing.
struct AppConfig: Sendable {
    let version: String
    let buildNumber: Int
}

/// Optional string wrapper for testing optional type registration.
struct OptionalString: Sendable {
    let value: String?
}

/// Optional int wrapper for testing optional type registration.
struct OptionalInt: Sendable {
    let value: Int?
}

/// User service struct for testing nested dependencies.
struct UserService: Sendable {
    let repository: UserRepositoryProtocol
    let logger: LoggerProtocol

    func processUser(name: String) -> User {
        logger.info("Processing: \(name)")
        return repository.createUser(name: name)
    }
}

/// User service class for testing property wrapper with async operations.
class UserServiceClass {
    @Service
    var userRepository: UserRepositoryProtocol

    @Service
    var networkService: NetworkServiceProtocol

    @Service
    var logger: LoggerProtocol

    func processUser(name: String) async throws -> User {
        logger.info("Processing user: \(name)")

        // Simulate API call
        _ = try await networkService.get(url: "/validate-user")

        // Create user
        let user = userRepository.createUser(name: name)

        logger.info("User processed successfully: \(user.id)")
        return user
    }
}

/// User controller struct for testing Service property wrapper.
struct UserController {
    @Service
    var userRepository: UserRepositoryProtocol

    @Service
    var logger: LoggerProtocol

    func handleCreateUser(name: String) -> User {
        logger.info("Handling user creation request")
        return userRepository.createUser(name: name)
    }
}

/// Database controller struct for testing Service property wrapper with explicit type.
struct DatabaseController {
    // Use explicit type initializer
    @Service(DatabaseProtocol.self)
    var database: DatabaseProtocol

    func getConnectionInfo() -> String {
        return database.connect()
    }
}
