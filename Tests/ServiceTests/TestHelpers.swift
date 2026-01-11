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
        print("[\(level)] INFO: \(message)")
    }

    func error(_ message: String) {
        print("[\(level)] ERROR: \(message)")
    }

    func debug(_ message: String) {
        print("[\(level)] DEBUG: \(message)")
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
