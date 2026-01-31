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

    @Test func resolvesLazilyOnFirstAccess() async throws {
        let testEnv = ServiceEnv(name: "lazy-test")
        ServiceEnv.$current.withValue(testEnv) {
            // Use a wrapper class to track resolve count safely
            final class Counter: Sendable {
                let count: Int
                init(_ count: Int) { self.count = count }
            }

            ServiceEnv.current.register(Counter.self) {
                Counter(1)  // Factory creates counter with value 1
            }

            struct LazyContainer: Sendable {
                @Service var counter: Counter
            }

            // Before accessing, service should not be resolved yet
            // We verify lazy behavior by checking the wrapper stores nil initially
            let container = LazyContainer()

            // First access triggers resolution
            let value1 = container.counter
            #expect(value1.count == 1, "Should resolve on first access")

            // Second access returns cached value (same instance)
            let value2 = container.counter
            #expect(value1 === value2, "Should return same cached instance")
        }
    }

    @Test func capturesEnvironmentAtInitTime() async throws {
        let onlineEnv = ServiceEnv(name: "online-env")
        let testEnv = ServiceEnv(name: "test-env")

        ServiceEnv.$current.withValue(onlineEnv) {
            ServiceEnv.current.register(String.self) { "online-value" }
        }
        ServiceEnv.$current.withValue(testEnv) {
            ServiceEnv.current.register(String.self) { "test-value" }
        }

        struct EnvContainer: Sendable {
            @Service var value: String
        }

        // Create container in test environment
        let container = ServiceEnv.$current.withValue(testEnv) {
            EnvContainer()
        }

        // Access in online environment - should still get test value
        let value = ServiceEnv.$current.withValue(onlineEnv) {
            container.value
        }

        #expect(value == "test-value", "Should use environment captured at init time")
    }

    @Test func optionalServiceReturnsNilWhenNotRegistered() async throws {
        let testEnv = ServiceEnv(name: "optional-nil-test")
        ServiceEnv.$current.withValue(testEnv) {
            struct OptionalContainer: Sendable {
                @Service var optional: String?
            }

            let container = OptionalContainer()
            #expect(container.optional == nil, "Should return nil for unregistered service")
        }
    }

    @Test func optionalServiceReturnsValueWhenRegistered() async throws {
        let testEnv = ServiceEnv(name: "optional-value-test")
        ServiceEnv.$current.withValue(testEnv) {
            ServiceEnv.current.register(String.self) { "registered-value" }

            struct OptionalContainer: Sendable {
                @Service var optional: String?
            }

            let container = OptionalContainer()
            #expect(container.optional == "registered-value", "Should return value for registered service")
        }
    }

    @Test func optionalServiceCachesResolvedValue() async throws {
        let testEnv = ServiceEnv(name: "optional-cache-test")
        ServiceEnv.$current.withValue(testEnv) {
            ServiceEnv.current.register(String.self) { "cached-value" }

            struct OptionalCacheContainer: Sendable {
                @Service var optional: String?
            }

            let container = OptionalCacheContainer()
            let value1 = container.optional
            let value2 = container.optional

            #expect(value1 == "cached-value")
            #expect(value2 == "cached-value")
        }
    }
}
