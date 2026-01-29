//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

import Foundation
import Testing

@testable import Service

@Suite("Service Property Wrapper Tests")
struct ServicePropertyWrapperTests {
    @Test func resolvesDependencies() async throws {
        let testEnv = ServiceEnv(name: "test")
        ServiceEnv.$current.withValue(testEnv) {
            ServiceEnv.current.register(DatabaseProtocol.self) {
                DatabaseService(connectionString: "sqlite://test.db")
            }
            ServiceEnv.current.register(LoggerProtocol.self) {
                LoggerService(level: "DEBUG")
            }
            ServiceEnv.current.register(UserRepositoryProtocol.self) {
                let database = try ServiceEnv.current.resolve(DatabaseProtocol.self)
                let logger = try ServiceEnv.current.resolve(LoggerProtocol.self)
                return UserRepository(database: database, logger: logger)
            }

            let controller = UserController()
            let user = controller.handleCreateUser(name: "Test User")

            #expect(user.name == "Test User")
            #expect(!user.id.isEmpty)
        }
    }

    @Test func supportsExplicitTypeInitializer() async throws {
        let testEnv = ServiceEnv(name: "explicit-type-test")
        ServiceEnv.$current.withValue(testEnv) {
            ServiceEnv.current.register(DatabaseProtocol.self) {
                DatabaseService(connectionString: "sqlite://explicit.db")
            }

            let controller = DatabaseController()
            let connectionInfo = controller.getConnectionInfo()
            #expect(connectionInfo.contains("sqlite://explicit.db"))
        }
    }
}
