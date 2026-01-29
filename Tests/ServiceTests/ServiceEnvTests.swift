//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

import Foundation
import Testing

@testable import Service

// MARK: - ServiceEnv Tests

@Test("ServiceEnv provides different environments")
func testServiceEnvironments() async throws {
    #expect(ServiceEnv.online.name == "online")
    #expect(ServiceEnv.dev.name == "dev")
    #expect(ServiceEnv.test.name == "test")

    let customEnv = ServiceEnv(name: "custom")
    #expect(customEnv.name == "custom")
}

@Test("ServiceEnv can switch contexts")
func testServiceEnvContextSwitching() async throws {
    let testEnv = ServiceEnv(name: "test-env")

    try ServiceEnv.$current.withValue(testEnv) {
        ServiceEnv.current.register(String.self) {
            "Service built in \(ServiceEnv.current.name) environment"
        }

        let result = try ServiceEnv.current.resolve(String.self)
        #expect(result == "Service built in test-env environment")
    }

    try ServiceEnv.$current.withValue(.dev) {
        ServiceEnv.current.register(String.self) {
            "Service built in \(ServiceEnv.current.name) environment"
        }

        let result = try ServiceEnv.current.resolve(String.self)
        #expect(result == "Service built in dev environment")
    }
}

@Test("ServiceEnv can register and resolve services")
func testServiceEnvRegistrationAndResolution() async throws {
    let testEnv = ServiceEnv(name: "test")
    try ServiceEnv.$current.withValue(testEnv) {
        // Register services
        ServiceEnv.current.register(DatabaseProtocol.self) {
            DatabaseService(connectionString: "sqlite://test.db")
        }
        ServiceEnv.current.register(LoggerProtocol.self) {
            LoggerService(level: "DEBUG")
        }

        // Resolve services
        let database = try ServiceEnv.current.resolve(DatabaseProtocol.self)
        let logger = try ServiceEnv.current.resolve(LoggerProtocol.self)

        // Test actual functionality
        let connectionInfo = database.connect()
        #expect(connectionInfo.contains("sqlite://test.db"))

        logger.info("Testing logger service")
    }
}

@Test("ServiceEnv singleton behavior")
func testServiceEnvSingletonBehavior() async throws {
    let testEnv = ServiceEnv(name: "singleton-test")
    try ServiceEnv.$current.withValue(testEnv) {
        ServiceEnv.current.register(String.self) {
            UUID().uuidString
        }

        let service1 = try ServiceEnv.current.resolve(String.self)
        let service2 = try ServiceEnv.current.resolve(String.self)

        // Should return the same instance (singleton)
        #expect(service1 == service2)
    }
}

@Test("ServiceEnv resetAll functionality")
func testServiceResetAll() async throws {
    let env = ServiceEnv(name: "reset-all-test")
    try await ServiceEnv.$current.withValue(env) {
        var serviceId1: String?
        var serviceId2: String?

        ServiceEnv.current.register(String.self) {
            UUID().uuidString
        }

        serviceId1 = try ServiceEnv.current.resolve(String.self)

        // resetAll clears cache and providers (async to ensure MainActor caches are cleared)
        await ServiceEnv.current.resetAll()

        // Re-register service
        ServiceEnv.current.register(String.self) {
            UUID().uuidString
        }

        serviceId2 = try ServiceEnv.current.resolve(String.self)

        // Instances recreated after resetAll should be different
        #expect(serviceId1 != serviceId2)
    }
}

@Test("ServiceEnv resetCaches functionality")
func testServiceResetCaches() async throws {
    let env = ServiceEnv(name: "reset-caches-test")
    try await ServiceEnv.$current.withValue(env) {
        var serviceId1: String?
        var serviceId2: String?
        var serviceId3: String?

        // Register service
        ServiceEnv.current.register(String.self) {
            UUID().uuidString
        }

        // First resolution - creates and caches instance
        serviceId1 = try ServiceEnv.current.resolve(String.self)

        // Second resolution - should return same cached instance
        serviceId2 = try ServiceEnv.current.resolve(String.self)
        #expect(serviceId1 == serviceId2)

        // resetCaches clears cache but keeps providers (async to ensure MainActor caches are cleared)
        await ServiceEnv.current.resetCaches()

        // Third resolution - should create new instance using same provider
        serviceId3 = try ServiceEnv.current.resolve(String.self)

        // New instance created after resetCaches should be different
        #expect(serviceId1 != serviceId3)
        #expect(serviceId2 != serviceId3)

        // Service should still be registered (provider still exists)
        let serviceId4 = try ServiceEnv.current.resolve(String.self)
        #expect(!serviceId4.isEmpty)
    }
}

@Test("ServiceEnv resetCaches vs resetAll difference")
func testResetCachesVsResetAll() async throws {
    let env = ServiceEnv(name: "reset-comparison-test")
    try await ServiceEnv.$current.withValue(env) {
        // Register service
        ServiceEnv.current.register(String.self) {
            UUID().uuidString
        }

        let service1 = try ServiceEnv.current.resolve(String.self)

        // resetCaches - provider still exists (async to ensure MainActor caches are cleared)
        await ServiceEnv.current.resetCaches()
        let service2 = try ServiceEnv.current.resolve(String.self)
        #expect(service1 != service2)  // New instance created

        // resetAll - provider removed (async to ensure MainActor storage is cleared)
        await ServiceEnv.current.resetAll()

        // Service should no longer be registered
        // This will cause a fatalError, so we can't test it directly
        // But we can verify by re-registering
        ServiceEnv.current.register(String.self) {
            UUID().uuidString
        }
        let service3 = try ServiceEnv.current.resolve(String.self)
        #expect(!service3.isEmpty)
    }
}

@Test("ServiceEnv can register Sendable service instance directly")
func testRegisterSendableServiceInstance() async throws {
    let testEnv = ServiceEnv(name: "direct-instance-test")
    try ServiceEnv.$current.withValue(testEnv) {
        // Create instance first
        let instance = DatabaseService(connectionString: "sqlite://direct.db")

        // Register instance directly as DatabaseProtocol
        // Note: We need to explicitly specify the protocol type
        ServiceEnv.current.register(DatabaseProtocol.self) { instance }

        // Resolve and verify it's the same instance
        let resolved = try ServiceEnv.current.resolve(DatabaseProtocol.self)
        let connectionInfo = resolved.connect()
        #expect(connectionInfo.contains("sqlite://direct.db"))

        // Verify it's the same instance (singleton behavior)
        let resolved2 = try ServiceEnv.current.resolve(DatabaseProtocol.self)
        #expect(connectionInfo == resolved2.connect())
    }
}

@Test("ServiceEnv can re-register services to override existing registration")
func testServiceReRegistration() async throws {
    let testEnv = ServiceEnv(name: "re-registration-test")
    try await ServiceEnv.$current.withValue(testEnv) {
        // Register service with first factory
        ServiceEnv.current.register(String.self) {
            "first-registration"
        }

        let service1 = try ServiceEnv.current.resolve(String.self)
        #expect(service1 == "first-registration")

        // Re-register with different factory
        ServiceEnv.current.register(String.self) {
            "second-registration"
        }

        // After re-registration, new resolution should use new factory
        // But existing cached instance should still be returned
        let service2 = try ServiceEnv.current.resolve(String.self)
        #expect(service2 == "first-registration")  // Still cached

        // Clear cache and resolve again
        await ServiceEnv.current.resetCaches()
        let service3 = try ServiceEnv.current.resolve(String.self)
        #expect(service3 == "second-registration")  // Now uses new factory
    }
}

// MARK: - Hashable Tests

@Test("ServiceEnv conforms to Hashable")
func testServiceEnvHashable() async throws {
    // Test equality based on name
    let env1 = ServiceEnv(name: "test")
    let env2 = ServiceEnv(name: "test")
    let env3 = ServiceEnv(name: "dev")

    #expect(env1 == env2)
    #expect(env1 != env3)

    // Test hash consistency: equal objects must have equal hash values
    var hasher1 = Hasher()
    var hasher2 = Hasher()
    env1.hash(into: &hasher1)
    env2.hash(into: &hasher2)
    #expect(hasher1.finalize() == hasher2.finalize())

    var hasher3 = Hasher()
    env3.hash(into: &hasher3)
    #expect(hasher1.finalize() != hasher3.finalize())
}

@Test("ServiceEnv predefined environments are hashable")
func testPredefinedEnvironmentsHashable() async throws {
    // Test predefined environments
    #expect(ServiceEnv.online == ServiceEnv(name: "online"))
    #expect(ServiceEnv.dev == ServiceEnv(name: "dev"))
    #expect(ServiceEnv.test == ServiceEnv(name: "test"))

    #expect(ServiceEnv.online != ServiceEnv.dev)
    #expect(ServiceEnv.online != ServiceEnv.test)
    #expect(ServiceEnv.dev != ServiceEnv.test)
}

@Test("ServiceEnv can be used in Set")
func testServiceEnvInSet() async throws {
    var environments: Set<ServiceEnv> = []

    environments.insert(ServiceEnv.online)
    environments.insert(ServiceEnv.dev)
    environments.insert(ServiceEnv.test)
    environments.insert(ServiceEnv(name: "custom"))

    #expect(environments.count == 4)

    // Adding duplicate should not increase count
    environments.insert(ServiceEnv(name: "online"))
    #expect(environments.count == 4)

    // Adding another custom with same name should not increase count
    environments.insert(ServiceEnv(name: "custom"))
    #expect(environments.count == 4)
}

@Test("ServiceEnv can be used as Dictionary key")
func testServiceEnvAsDictionaryKey() async throws {
    var configs: [ServiceEnv: String] = [:]

    configs[ServiceEnv.online] = "production"
    configs[ServiceEnv.dev] = "development"
    configs[ServiceEnv.test] = "testing"
    configs[ServiceEnv(name: "staging")] = "staging"

    #expect(configs.count == 4)
    #expect(configs[ServiceEnv.online] == "production")
    #expect(configs[ServiceEnv.dev] == "development")
    #expect(configs[ServiceEnv.test] == "testing")
    #expect(configs[ServiceEnv(name: "staging")] == "staging")

    // Accessing with same name should return same value
    #expect(configs[ServiceEnv(name: "online")] == "production")
    #expect(configs[ServiceEnv(name: "dev")] == "development")
}

@Test("ServiceEnv hashable allows environment comparison in Assembly")
func testServiceEnvHashableInAssembly() async throws {
    // This test demonstrates the use case described in the documentation
    struct TestAssembly: ServiceAssembly {
        func assemble(env: ServiceEnv) {
            if env == .test {
                env.register(String.self) { "mock-value" }
            } else {
                env.register(String.self) { "real-value" }
            }
        }
    }

    // Test with .test environment
    try await ServiceEnv.$current.withValue(.test) { @MainActor in
        await MainActor.run {
            ServiceEnv.current.assemble(TestAssembly())
        }
        let value = try ServiceEnv.current.resolve(String.self)
        #expect(value == "mock-value")
    }

    // Test with .online environment
    try await ServiceEnv.$current.withValue(.online) { @MainActor in
        await MainActor.run {
            ServiceEnv.current.assemble(TestAssembly())
        }
        let value = try ServiceEnv.current.resolve(String.self)
        #expect(value == "real-value")
    }
}
