//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

import Foundation
import Testing

@testable import Service

// MARK: - Integration Tests

@Test("Complete dependency injection flow")
func testCompleteFlow() async throws {
    let testEnv = ServiceEnv(name: "integration-test")

    let result = try await ServiceEnv.$current.withValue(testEnv) {
        // Register all services
        ServiceEnv.current.register(DatabaseProtocol.self) {
            DatabaseService(connectionString: "sqlite://test.db")
        }
        ServiceEnv.current.register(LoggerProtocol.self) {
            LoggerService(level: "INFO")
        }
        ServiceEnv.current.register(UserRepositoryProtocol.self) {
            let database = ServiceEnv.current.resolve(DatabaseProtocol.self)
            let logger = ServiceEnv.current.resolve(LoggerProtocol.self)
            return UserRepository(database: database, logger: logger)
        }
        ServiceEnv.current.register(NetworkServiceProtocol.self) {
            let logger = ServiceEnv.current.resolve(LoggerProtocol.self)
            return NetworkService(baseURL: "https://api.example.com", logger: logger)
        }

        let userService = UserServiceClass()
        return try await userService.processUser(name: "Integration Test User")
    }

    #expect(result.name == "Integration Test User")
    #expect(!result.id.isEmpty)
}

@Test("Service isolation between different environments")
func testServiceIsolationBetweenEnvironments() async throws {
    let env1 = ServiceEnv(name: "env1")
    let env2 = ServiceEnv(name: "env2")

    var service1: String?
    var service2: String?

    ServiceEnv.$current.withValue(env1) {
        ServiceEnv.current.register(String.self) {
            "env1-service"
        }
        service1 = ServiceEnv.current.resolve(String.self)
    }

    ServiceEnv.$current.withValue(env2) {
        ServiceEnv.current.register(String.self) {
            "env2-service"
        }
        service2 = ServiceEnv.current.resolve(String.self)
    }

    #expect(service1 == "env1-service")
    #expect(service2 == "env2-service")
    #expect(service1 != service2)
}
