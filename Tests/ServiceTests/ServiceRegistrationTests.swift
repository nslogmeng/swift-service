//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

import Foundation
import Testing

@testable import Service

// MARK: - Service Registration Tests

@Test("ServiceEnv register with factory function executes factory only once")
func testRegisterFactoryExecutesOnce() async throws {
    let testEnv = ServiceEnv(name: "factory-once-test")
    await ServiceEnv.$current.withValue(testEnv) {
        // Use a class to track call count (thread-safe for this test)
        let callCount = CallCounter()

        // Register service with factory that tracks calls
        ServiceEnv.current.register(String.self) {
            callCount.count += 1
            return "factory-result-\(callCount.count)"
        }

        // First resolution - factory should be called
        let service1 = ServiceEnv.current.resolve(String.self)
        #expect(callCount.count == 1)
        #expect(service1 == "factory-result-1")

        // Second resolution - factory should NOT be called again (cached)
        let service2 = ServiceEnv.current.resolve(String.self)
        #expect(callCount.count == 1)  // Still 1, not 2
        #expect(service2 == "factory-result-1")  // Same cached instance

        // After cache clear, factory should be called again
        await ServiceEnv.current.resetCaches()
        let service3 = ServiceEnv.current.resolve(String.self)
        #expect(callCount.count == 2)  // Now 2
        #expect(service3 == "factory-result-2")
    }
}

@Test("ServiceEnv register with factory function can create different instances after cache clear")
func testRegisterFactoryCreatesNewInstances() async throws {
    let testEnv = ServiceEnv(name: "factory-new-instances-test")
    await ServiceEnv.$current.withValue(testEnv) {
        // Use a class to track instance ID (thread-safe for this test)
        let instanceId = InstanceCounter()

        // Register service with factory that creates unique instances
        ServiceEnv.current.register(Int.self) {
            instanceId.id += 1
            return instanceId.id
        }

        // First resolution
        let service1 = ServiceEnv.current.resolve(Int.self)
        #expect(service1 == 1)

        // Second resolution - should return cached instance
        let service2 = ServiceEnv.current.resolve(Int.self)
        #expect(service2 == 1)  // Same cached instance

        // Clear cache and resolve again
        await ServiceEnv.current.resetCaches()
        let service3 = ServiceEnv.current.resolve(Int.self)
        #expect(service3 == 2)  // New instance created
    }
}

@Test("ServiceEnv register with factory function supports lazy initialization")
func testRegisterFactoryLazyInitialization() async throws {
    let testEnv = ServiceEnv(name: "factory-lazy-test")
    ServiceEnv.$current.withValue(testEnv) {
        // Use a class to track initialization (thread-safe for this test)
        let initialized = InitFlag()

        // Register service with factory
        ServiceEnv.current.register(String.self) {
            initialized.value = true
            return "lazy-initialized"
        }

        // Factory should not be called yet
        #expect(initialized.value == false)

        // First resolution triggers factory
        let service = ServiceEnv.current.resolve(String.self)
        #expect(initialized.value == true)
        #expect(service == "lazy-initialized")
    }
}

@Test("ServiceEnv can register and resolve value types")
func testRegisterValueTypes() async throws {
    let testEnv = ServiceEnv(name: "value-types-test")
    ServiceEnv.$current.withValue(testEnv) {
        // Register Int
        ServiceEnv.current.register(Int.self) {
            42
        }

        // Register Double
        ServiceEnv.current.register(Double.self) {
            3.14
        }

        // Register Bool
        ServiceEnv.current.register(Bool.self) {
            true
        }

        // Resolve and verify
        let intValue = ServiceEnv.current.resolve(Int.self)
        let doubleValue = ServiceEnv.current.resolve(Double.self)
        let boolValue = ServiceEnv.current.resolve(Bool.self)

        #expect(intValue == 42)
        #expect(doubleValue == 3.14)
        #expect(boolValue == true)
    }
}

@Test("ServiceEnv can register and resolve struct types")
func testRegisterStructTypes() async throws {
    let testEnv = ServiceEnv(name: "struct-types-test")
    ServiceEnv.$current.withValue(testEnv) {
        // Register struct
        ServiceEnv.current.register(Config.self) {
            Config(apiKey: "test-key", timeout: 30)
        }

        // Resolve and verify
        let config = ServiceEnv.current.resolve(Config.self)
        #expect(config.apiKey == "test-key")
        #expect(config.timeout == 30)

        // Verify singleton behavior
        let config2 = ServiceEnv.current.resolve(Config.self)
        #expect(config.apiKey == config2.apiKey)
        #expect(config.timeout == config2.timeout)
    }
}

@Test("ServiceEnv can register and resolve array types")
func testRegisterArrayTypes() async throws {
    let testEnv = ServiceEnv(name: "array-types-test")
    ServiceEnv.$current.withValue(testEnv) {
        // Register array of strings
        ServiceEnv.current.register([String].self) {
            ["item1", "item2", "item3"]
        }

        // Resolve and verify
        let items = ServiceEnv.current.resolve([String].self)
        #expect(items.count == 3)
        #expect(items[0] == "item1")
        #expect(items[1] == "item2")
        #expect(items[2] == "item3")
    }
}

@Test("ServiceEnv can register and resolve dictionary types")
func testRegisterDictionaryTypes() async throws {
    let testEnv = ServiceEnv(name: "dictionary-types-test")
    ServiceEnv.$current.withValue(testEnv) {
        // Register dictionary
        ServiceEnv.current.register([String: Int].self) {
            ["one": 1, "two": 2, "three": 3]
        }

        // Resolve and verify
        let dict = ServiceEnv.current.resolve([String: Int].self)
        #expect(dict["one"] == 1)
        #expect(dict["two"] == 2)
        #expect(dict["three"] == 3)
    }
}

@Test("ServiceEnv can register concrete type and resolve as protocol")
func testRegisterConcreteResolveAsProtocol() async throws {
    let testEnv = ServiceEnv(name: "concrete-protocol-test")
    ServiceEnv.$current.withValue(testEnv) {
        // Register concrete type as protocol
        ServiceEnv.current.register(DatabaseProtocol.self) {
            DatabaseService(connectionString: "sqlite://concrete.db")
        }

        // Resolve as protocol
        let database: DatabaseProtocol = ServiceEnv.current.resolve(DatabaseProtocol.self)
        let connectionInfo = database.connect()
        #expect(connectionInfo.contains("sqlite://concrete.db"))
    }
}

@Test("ServiceEnv can register multiple services of same type with different factories")
func testRegisterMultipleServicesSameType() async throws {
    let testEnv = ServiceEnv(name: "multiple-same-type-test")
    await ServiceEnv.$current.withValue(testEnv) {
        // Register first service
        ServiceEnv.current.register(String.self) {
            "first-service"
        }

        let service1 = ServiceEnv.current.resolve(String.self)
        #expect(service1 == "first-service")

        // Register second service (overrides)
        ServiceEnv.current.register(String.self) {
            "second-service"
        }

        // Cached instance still returns first
        let service2 = ServiceEnv.current.resolve(String.self)
        #expect(service2 == "first-service")

        // After cache clear, should use new factory
        await ServiceEnv.current.resetCaches()
        let service3 = ServiceEnv.current.resolve(String.self)
        #expect(service3 == "second-service")
    }
}

@Test("ServiceEnv factory can access environment during creation")
func testFactoryAccessesEnvironment() async throws {
    let testEnv = ServiceEnv(name: "factory-env-test")
    ServiceEnv.$current.withValue(testEnv) {
        // Register a service that depends on environment
        ServiceEnv.current.register(String.self) {
            "Service for \(ServiceEnv.current.name)"
        }

        // Resolve and verify
        let service = ServiceEnv.current.resolve(String.self)
        #expect(service == "Service for factory-env-test")
    }
}

@Test("ServiceEnv can register service with nested dependencies")
func testRegisterWithNestedDependencies() async throws {
    let testEnv = ServiceEnv(name: "nested-deps-test")
    ServiceEnv.$current.withValue(testEnv) {
        // Register base services
        ServiceEnv.current.register(DatabaseProtocol.self) {
            DatabaseService(connectionString: "sqlite://nested.db")
        }
        ServiceEnv.current.register(LoggerProtocol.self) {
            LoggerService(level: "INFO")
        }

        // Register service that depends on other services
        ServiceEnv.current.register(UserRepositoryProtocol.self) {
            let db = ServiceEnv.current.resolve(DatabaseProtocol.self)
            let logger = ServiceEnv.current.resolve(LoggerProtocol.self)
            return UserRepository(database: db, logger: logger)
        }

        // Register another service that depends on the repository
        ServiceEnv.current.register(UserService.self) {
            let repo = ServiceEnv.current.resolve(UserRepositoryProtocol.self)
            let logger = ServiceEnv.current.resolve(LoggerProtocol.self)
            return UserService(repository: repo, logger: logger)
        }

        // Resolve and use
        let userService = ServiceEnv.current.resolve(UserService.self)
        let user = userService.processUser(name: "Nested Test")
        #expect(user.name == "Nested Test")
    }
}

@Test("ServiceEnv can register instance of concrete type directly")
func testRegisterConcreteTypeInstance() async throws {
    let testEnv = ServiceEnv(name: "concrete-instance-test")
    ServiceEnv.$current.withValue(testEnv) {
        // Create instance
        let config = AppConfig(version: "1.0.0", buildNumber: 100)

        // Register instance directly
        ServiceEnv.current.register(AppConfig.self) { config }

        // Resolve and verify
        let resolved = ServiceEnv.current.resolve(AppConfig.self)
        #expect(resolved.version == "1.0.0")
        #expect(resolved.buildNumber == 100)

        // Verify it's the same instance (by value comparison)
        #expect(resolved.version == config.version)
        #expect(resolved.buildNumber == config.buildNumber)
    }
}

@Test("ServiceEnv can register optional types")
func testRegisterOptionalTypes() async throws {
    let testEnv = ServiceEnv(name: "optional-types-test")
    ServiceEnv.$current.withValue(testEnv) {
        // Register optional String - wrap in Optional
        ServiceEnv.current.register(OptionalString.self) {
            OptionalString(value: "optional-value")
        }

        // Resolve and verify
        let optionalString = ServiceEnv.current.resolve(OptionalString.self)
        #expect(optionalString.value == "optional-value")

        // Register nil optional
        ServiceEnv.current.register(OptionalInt.self) {
            OptionalInt(value: nil)
        }

        let optionalInt = ServiceEnv.current.resolve(OptionalInt.self)
        #expect(optionalInt.value == nil)
    }
}
