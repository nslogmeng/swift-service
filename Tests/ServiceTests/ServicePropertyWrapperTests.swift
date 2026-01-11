//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

import Foundation
import Testing
@testable import Service

// MARK: - Property Wrapper Tests

@Test("Service property wrapper resolves dependencies")
func testServicePropertyWrapper() async throws {
    // Setup test environment
    let testEnv = ServiceEnv(name: "test")
    ServiceEnv.$current.withValue(testEnv) {
        // Register services
        ServiceEnv.current.register(DatabaseProtocol.self) {
            DatabaseService(connectionString: "sqlite://test.db")
        }
        ServiceEnv.current.register(LoggerProtocol.self) {
            LoggerService(level: "DEBUG")
        }
        ServiceEnv.current.register(UserRepositoryProtocol.self) {
            let database = ServiceEnv.current.resolve(DatabaseProtocol.self)
            let logger = ServiceEnv.current.resolve(LoggerProtocol.self)
            return UserRepository(database: database, logger: logger)
        }

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

        let controller = UserController()
        let user = controller.handleCreateUser(name: "Test User")

        #expect(user.name == "Test User")
        #expect(!user.id.isEmpty)
    }
}

@Test("Service property wrapper with explicit type initializer")
func testServicePropertyWrapperExplicitType() async throws {
    let testEnv = ServiceEnv(name: "explicit-type-test")
    ServiceEnv.$current.withValue(testEnv) {
        // Register service
        ServiceEnv.current.register(DatabaseProtocol.self) {
            DatabaseService(connectionString: "sqlite://explicit.db")
        }
        
        struct DatabaseController {
            // Use explicit type initializer
            @Service(DatabaseProtocol.self)
            var database: DatabaseProtocol
            
            func getConnectionInfo() -> String {
                return database.connect()
            }
        }
        
        let controller = DatabaseController()
        let connectionInfo = controller.getConnectionInfo()
        #expect(connectionInfo.contains("sqlite://explicit.db"))
    }
}
