//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

import Foundation
import Testing

@testable import Service

@Suite("Service Registration Tests")
struct ServiceRegistrationTests {
    // MARK: - Factory Tests

    @Suite("Factory")
    struct FactoryTests {
        @Test func executesOnlyOnce() async throws {
            let testEnv = ServiceEnv(name: "factory-once-test")
            try ServiceEnv.$current.withValue(testEnv) {
                let callCount = CallCounter()

                ServiceEnv.current.register(String.self) {
                    callCount.count += 1
                    return "factory-result-\(callCount.count)"
                }

                let service1 = try ServiceEnv.current.resolve(String.self)
                #expect(callCount.count == 1)
                #expect(service1 == "factory-result-1")

                let service2 = try ServiceEnv.current.resolve(String.self)
                #expect(callCount.count == 1)
                #expect(service2 == "factory-result-1")

                ServiceEnv.current.resetCaches()
                let service3 = try ServiceEnv.current.resolve(String.self)
                #expect(callCount.count == 2)
                #expect(service3 == "factory-result-2")
            }
        }

        @Test func createsNewInstancesAfterCacheClear() async throws {
            let testEnv = ServiceEnv(name: "factory-new-instances-test")
            try ServiceEnv.$current.withValue(testEnv) {
                let instanceId = InstanceCounter()

                ServiceEnv.current.register(Int.self) {
                    instanceId.id += 1
                    return instanceId.id
                }

                let service1 = try ServiceEnv.current.resolve(Int.self)
                #expect(service1 == 1)

                let service2 = try ServiceEnv.current.resolve(Int.self)
                #expect(service2 == 1)

                ServiceEnv.current.resetCaches()
                let service3 = try ServiceEnv.current.resolve(Int.self)
                #expect(service3 == 2)
            }
        }

        @Test func supportsLazyInitialization() async throws {
            let testEnv = ServiceEnv(name: "factory-lazy-test")
            try ServiceEnv.$current.withValue(testEnv) {
                let initialized = InitFlag()

                ServiceEnv.current.register(String.self) {
                    initialized.value = true
                    return "lazy-initialized"
                }

                #expect(initialized.value == false)

                let service = try ServiceEnv.current.resolve(String.self)
                #expect(initialized.value == true)
                #expect(service == "lazy-initialized")
            }
        }

        @Test func canAccessEnvironmentDuringCreation() async throws {
            let testEnv = ServiceEnv(name: "factory-env-test")
            try ServiceEnv.$current.withValue(testEnv) {
                ServiceEnv.current.register(String.self) {
                    "Service for \(ServiceEnv.current.name)"
                }

                let service = try ServiceEnv.current.resolve(String.self)
                #expect(service == "Service for factory-env-test")
            }
        }
    }

    // MARK: - Type Registration Tests

    @Suite("Type Registration")
    struct TypeRegistrationTests {
        @Test func registersValueTypes() async throws {
            let testEnv = ServiceEnv(name: "value-types-test")
            try ServiceEnv.$current.withValue(testEnv) {
                ServiceEnv.current.register(Int.self) { 42 }
                ServiceEnv.current.register(Double.self) { 3.14 }
                ServiceEnv.current.register(Bool.self) { true }

                let intValue = try ServiceEnv.current.resolve(Int.self)
                let doubleValue = try ServiceEnv.current.resolve(Double.self)
                let boolValue = try ServiceEnv.current.resolve(Bool.self)

                #expect(intValue == 42)
                #expect(doubleValue == 3.14)
                #expect(boolValue == true)
            }
        }

        @Test func registersStructTypes() async throws {
            let testEnv = ServiceEnv(name: "struct-types-test")
            try ServiceEnv.$current.withValue(testEnv) {
                ServiceEnv.current.register(Config.self) {
                    Config(apiKey: "test-key", timeout: 30)
                }

                let config = try ServiceEnv.current.resolve(Config.self)
                #expect(config.apiKey == "test-key")
                #expect(config.timeout == 30)

                let config2 = try ServiceEnv.current.resolve(Config.self)
                #expect(config.apiKey == config2.apiKey)
                #expect(config.timeout == config2.timeout)
            }
        }

        @Test func registersArrayTypes() async throws {
            let testEnv = ServiceEnv(name: "array-types-test")
            try ServiceEnv.$current.withValue(testEnv) {
                ServiceEnv.current.register([String].self) {
                    ["item1", "item2", "item3"]
                }

                let items = try ServiceEnv.current.resolve([String].self)
                #expect(items.count == 3)
                #expect(items[0] == "item1")
                #expect(items[1] == "item2")
                #expect(items[2] == "item3")
            }
        }

        @Test func registersDictionaryTypes() async throws {
            let testEnv = ServiceEnv(name: "dictionary-types-test")
            try ServiceEnv.$current.withValue(testEnv) {
                ServiceEnv.current.register([String: Int].self) {
                    ["one": 1, "two": 2, "three": 3]
                }

                let dict = try ServiceEnv.current.resolve([String: Int].self)
                #expect(dict["one"] == 1)
                #expect(dict["two"] == 2)
                #expect(dict["three"] == 3)
            }
        }

        @Test func registersConcreteTypeAndResolvesAsProtocol() async throws {
            let testEnv = ServiceEnv(name: "concrete-protocol-test")
            try ServiceEnv.$current.withValue(testEnv) {
                ServiceEnv.current.register(DatabaseProtocol.self) {
                    DatabaseService(connectionString: "sqlite://concrete.db")
                }

                let database: DatabaseProtocol = try ServiceEnv.current.resolve(DatabaseProtocol.self)
                let connectionInfo = database.connect()
                #expect(connectionInfo.contains("sqlite://concrete.db"))
            }
        }

        @Test func registersOptionalTypes() async throws {
            let testEnv = ServiceEnv(name: "optional-types-test")
            try ServiceEnv.$current.withValue(testEnv) {
                ServiceEnv.current.register(OptionalString.self) {
                    OptionalString(value: "optional-value")
                }

                let optionalString = try ServiceEnv.current.resolve(OptionalString.self)
                #expect(optionalString.value == "optional-value")

                ServiceEnv.current.register(OptionalInt.self) {
                    OptionalInt(value: nil)
                }

                let optionalInt = try ServiceEnv.current.resolve(OptionalInt.self)
                #expect(optionalInt.value == nil)
            }
        }

        @Test func registersConcreteTypeInstanceDirectly() async throws {
            let testEnv = ServiceEnv(name: "concrete-instance-test")
            try ServiceEnv.$current.withValue(testEnv) {
                let config = AppConfig(version: "1.0.0", buildNumber: 100)

                ServiceEnv.current.register(AppConfig.self) { config }

                let resolved = try ServiceEnv.current.resolve(AppConfig.self)
                #expect(resolved.version == "1.0.0")
                #expect(resolved.buildNumber == 100)

                #expect(resolved.version == config.version)
                #expect(resolved.buildNumber == config.buildNumber)
            }
        }
    }

    // MARK: - Override Registration Tests

    @Suite("Override Registration")
    struct OverrideRegistrationTests {
        @Test func overridesWithSameTypeAfterCacheClear() async throws {
            let testEnv = ServiceEnv(name: "multiple-same-type-test")
            try ServiceEnv.$current.withValue(testEnv) {
                ServiceEnv.current.register(String.self) {
                    "first-service"
                }

                let service1 = try ServiceEnv.current.resolve(String.self)
                #expect(service1 == "first-service")

                ServiceEnv.current.register(String.self) {
                    "second-service"
                }

                let service2 = try ServiceEnv.current.resolve(String.self)
                #expect(service2 == "first-service")

                ServiceEnv.current.resetCaches()
                let service3 = try ServiceEnv.current.resolve(String.self)
                #expect(service3 == "second-service")
            }
        }
    }

    // MARK: - Nested Dependencies Tests

    @Suite("Nested Dependencies")
    struct NestedDependenciesTests {
        @Test func resolvesNestedDependencies() async throws {
            let testEnv = ServiceEnv(name: "nested-deps-test")
            try ServiceEnv.$current.withValue(testEnv) {
                ServiceEnv.current.register(DatabaseProtocol.self) {
                    DatabaseService(connectionString: "sqlite://nested.db")
                }
                ServiceEnv.current.register(LoggerProtocol.self) {
                    LoggerService(level: "INFO")
                }

                ServiceEnv.current.register(UserRepositoryProtocol.self) {
                    let db = try ServiceEnv.current.resolve(DatabaseProtocol.self)
                    let logger = try ServiceEnv.current.resolve(LoggerProtocol.self)
                    return UserRepository(database: db, logger: logger)
                }

                ServiceEnv.current.register(UserService.self) {
                    let repo = try ServiceEnv.current.resolve(UserRepositoryProtocol.self)
                    let logger = try ServiceEnv.current.resolve(LoggerProtocol.self)
                    return UserService(repository: repo, logger: logger)
                }

                let userService = try ServiceEnv.current.resolve(UserService.self)
                let user = userService.processUser(name: "Nested Test")
                #expect(user.name == "Nested Test")
            }
        }
    }
}

// MARK: - Test Types

extension ServiceRegistrationTests {
    final class CallCounter: @unchecked Sendable {
        var count: Int = 0
    }

    final class InstanceCounter: @unchecked Sendable {
        var id: Int = 0
    }

    final class InitFlag: @unchecked Sendable {
        var value: Bool = false
    }
}
