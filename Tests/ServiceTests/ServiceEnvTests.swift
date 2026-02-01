//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

import Foundation
import Testing

@testable import Service

@Suite("ServiceEnv Tests")
struct ServiceEnvTests {
    // MARK: - Environment Configuration

    @Test func providesEnvironments() async throws {
        #expect(ServiceEnv.online.name == "online")
        #expect(ServiceEnv.dev.name == "dev")
        #expect(ServiceEnv.test.name == "test")

        let customEnv = ServiceEnv(name: "custom")
        #expect(customEnv.name == "custom")
    }

    @Test func switchesContexts() async throws {
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

    // MARK: - Registration and Resolution

    @Test func registersAndResolvesServices() async throws {
        let testEnv = ServiceEnv(name: "test")
        try ServiceEnv.$current.withValue(testEnv) {
            ServiceEnv.current.register(DatabaseProtocol.self) {
                DatabaseService(connectionString: "sqlite://test.db")
            }
            ServiceEnv.current.register(LoggerProtocol.self) {
                LoggerService(level: "DEBUG")
            }

            let database = try ServiceEnv.current.resolve(DatabaseProtocol.self)
            let logger = try ServiceEnv.current.resolve(LoggerProtocol.self)

            let connectionInfo = database.connect()
            #expect(connectionInfo.contains("sqlite://test.db"))

            logger.info("Testing logger service")
        }
    }

    @Test func registersSendableInstanceDirectly() async throws {
        let testEnv = ServiceEnv(name: "direct-instance-test")
        try ServiceEnv.$current.withValue(testEnv) {
            let instance = DatabaseService(connectionString: "sqlite://direct.db")

            ServiceEnv.current.register(DatabaseProtocol.self) { instance }

            let resolved = try ServiceEnv.current.resolve(DatabaseProtocol.self)
            let connectionInfo = resolved.connect()
            #expect(connectionInfo.contains("sqlite://direct.db"))

            let resolved2 = try ServiceEnv.current.resolve(DatabaseProtocol.self)
            #expect(connectionInfo == resolved2.connect())
        }
    }

    // MARK: - Singleton Behavior

    @Test func maintainsSingletonBehavior() async throws {
        let testEnv = ServiceEnv(name: "singleton-test")
        try ServiceEnv.$current.withValue(testEnv) {
            ServiceEnv.current.register(String.self) {
                UUID().uuidString
            }

            let service1 = try ServiceEnv.current.resolve(String.self)
            let service2 = try ServiceEnv.current.resolve(String.self)

            #expect(service1 == service2)
        }
    }

    // MARK: - Reset Behavior

    @Test func resetAllClearsProvidersAndCaches() async throws {
        let env = ServiceEnv(name: "reset-all-test")
        try await ServiceEnv.$current.withValue(env) {
            var serviceId1: String?
            var serviceId2: String?

            ServiceEnv.current.register(String.self) {
                UUID().uuidString
            }

            serviceId1 = try ServiceEnv.current.resolve(String.self)

            ServiceEnv.current.resetAll()

            ServiceEnv.current.register(String.self) {
                UUID().uuidString
            }

            serviceId2 = try ServiceEnv.current.resolve(String.self)

            #expect(serviceId1 != serviceId2)
        }
    }

    @Test func resetCachesClearsOnlyCaches() async throws {
        let env = ServiceEnv(name: "reset-caches-test")
        try await ServiceEnv.$current.withValue(env) {
            var serviceId1: String?
            var serviceId2: String?
            var serviceId3: String?

            ServiceEnv.current.register(String.self) {
                UUID().uuidString
            }

            serviceId1 = try ServiceEnv.current.resolve(String.self)
            serviceId2 = try ServiceEnv.current.resolve(String.self)
            #expect(serviceId1 == serviceId2)

            ServiceEnv.current.resetCaches()

            serviceId3 = try ServiceEnv.current.resolve(String.self)

            #expect(serviceId1 != serviceId3)
            #expect(serviceId2 != serviceId3)

            let serviceId4 = try ServiceEnv.current.resolve(String.self)
            #expect(!serviceId4.isEmpty)
        }
    }

    @Test func resetCachesDiffersFromResetAll() async throws {
        let env = ServiceEnv(name: "reset-comparison-test")
        try await ServiceEnv.$current.withValue(env) {
            ServiceEnv.current.register(String.self) {
                UUID().uuidString
            }

            let service1 = try ServiceEnv.current.resolve(String.self)

            ServiceEnv.current.resetCaches()
            let service2 = try ServiceEnv.current.resolve(String.self)
            #expect(service1 != service2)

            ServiceEnv.current.resetAll()

            ServiceEnv.current.register(String.self) {
                UUID().uuidString
            }
            let service3 = try ServiceEnv.current.resolve(String.self)
            #expect(!service3.isEmpty)
        }
    }

    // MARK: - Override Registration

    @Test func reRegistersServicesToOverride() async throws {
        let testEnv = ServiceEnv(name: "re-registration-test")
        try await ServiceEnv.$current.withValue(testEnv) {
            ServiceEnv.current.register(String.self) {
                "first-registration"
            }

            let service1 = try ServiceEnv.current.resolve(String.self)
            #expect(service1 == "first-registration")

            ServiceEnv.current.register(String.self) {
                "second-registration"
            }

            let service2 = try ServiceEnv.current.resolve(String.self)
            #expect(service2 == "first-registration")

            ServiceEnv.current.resetCaches()
            let service3 = try ServiceEnv.current.resolve(String.self)
            #expect(service3 == "second-registration")
        }
    }

    // MARK: - Hashable Tests

    @Suite("Hashable")
    struct HashableTests {
        @Test func conformsToHashable() async throws {
            let env1 = ServiceEnv(name: "test")
            let env2 = ServiceEnv(name: "test")
            let env3 = ServiceEnv(name: "dev")

            #expect(env1 == env2)
            #expect(env1 != env3)

            var hasher1 = Hasher()
            var hasher2 = Hasher()
            env1.hash(into: &hasher1)
            env2.hash(into: &hasher2)
            #expect(hasher1.finalize() == hasher2.finalize())

            var hasher3 = Hasher()
            env3.hash(into: &hasher3)
            #expect(hasher1.finalize() != hasher3.finalize())
        }

        @Test func predefinedEnvironmentsAreHashable() async throws {
            #expect(ServiceEnv.online == ServiceEnv(name: "online"))
            #expect(ServiceEnv.dev == ServiceEnv(name: "dev"))
            #expect(ServiceEnv.test == ServiceEnv(name: "test"))

            #expect(ServiceEnv.online != ServiceEnv.dev)
            #expect(ServiceEnv.online != ServiceEnv.test)
            #expect(ServiceEnv.dev != ServiceEnv.test)
        }

        @Test func canBeUsedInSet() async throws {
            var environments: Set<ServiceEnv> = []

            environments.insert(ServiceEnv.online)
            environments.insert(ServiceEnv.dev)
            environments.insert(ServiceEnv.test)
            environments.insert(ServiceEnv(name: "custom"))

            #expect(environments.count == 4)

            environments.insert(ServiceEnv(name: "online"))
            #expect(environments.count == 4)

            environments.insert(ServiceEnv(name: "custom"))
            #expect(environments.count == 4)
        }

        @Test func canBeUsedAsDictionaryKey() async throws {
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

            #expect(configs[ServiceEnv(name: "online")] == "production")
            #expect(configs[ServiceEnv(name: "dev")] == "development")
        }

        @Test func allowsEnvironmentComparisonInAssembly() async throws {
            try await ServiceEnv.$current.withValue(.test) { @MainActor in
                await MainActor.run {
                    ServiceEnv.current.assemble(EnvironmentAwareAssembly())
                }
                let value = try ServiceEnv.current.resolve(String.self)
                #expect(value == "mock-value")
            }

            try await ServiceEnv.$current.withValue(.online) { @MainActor in
                await MainActor.run {
                    ServiceEnv.current.assemble(EnvironmentAwareAssembly())
                }
                let value = try ServiceEnv.current.resolve(String.self)
                #expect(value == "real-value")
            }
        }
    }
}

// MARK: - Test Types

extension ServiceEnvTests {
    struct EnvironmentAwareAssembly: ServiceAssembly {
        func assemble(env: ServiceEnv) {
            if env == .test {
                env.register(String.self) { "mock-value" }
            } else {
                env.register(String.self) { "real-value" }
            }
        }
    }
}
