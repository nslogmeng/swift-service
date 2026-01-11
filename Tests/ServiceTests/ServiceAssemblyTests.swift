//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

import Foundation
import Testing

@testable import Service

// MARK: - ServiceAssembly Tests

@Test("ServiceAssembly can register services")
func testServiceAssembly() async throws {
    let testEnv = ServiceEnv(name: "assembly-test")
    await ServiceEnv.$current.withValue(testEnv) {
        // Assemble a single assembly
        await MainActor.run {
            ServiceEnv.current.assemble(DatabaseAssembly())
        }

        // Verify service is registered
        let database = ServiceEnv.current.resolve(DatabaseProtocol.self)
        let connectionInfo = database.connect()
        #expect(connectionInfo.contains("sqlite://assembly.db"))
    }
}

@Test("ServiceAssembly can apply multiple assemblies")
func testMultipleAssemblies() async throws {
    let testEnv = ServiceEnv(name: "multi-assembly-test")
    await ServiceEnv.$current.withValue(testEnv) { @MainActor in
        // Assemble multiple assemblies using array
        await MainActor.run {
            ServiceEnv.current.assemble([
                DatabaseAssembly(),
                LoggerAssembly(),
            ])
        }

        // Verify both services are registered
        let database = ServiceEnv.current.resolve(DatabaseProtocol.self)
        let logger = ServiceEnv.current.resolve(LoggerProtocol.self)

        #expect(database.connect().contains("sqlite://assembly.db"))
        logger.info("Testing logger from assembly")
    }
}

@Test("ServiceAssembly can apply multiple assemblies using variadic arguments")
func testVariadicAssemblies() async throws {
    let testEnv = ServiceEnv(name: "variadic-assembly-test")
    await ServiceEnv.$current.withValue(testEnv) {
        // Assemble multiple assemblies using variadic arguments
        await MainActor.run {
            ServiceEnv.current.assemble(
                DatabaseAssembly(),
                LoggerAssembly(),
                RepositoryAssembly()
            )
        }

        // Verify all services are registered and can work together
        let userRepository = ServiceEnv.current.resolve(UserRepositoryProtocol.self)
        let user = userRepository.createUser(name: "Assembly User")

        #expect(user.name == "Assembly User")
        #expect(!user.id.isEmpty)
    }
}

@Test("ServiceAssembly supports dependency injection between assemblies")
func testAssemblyDependencyInjection() async throws {
    let testEnv = ServiceEnv(name: "assembly-di-test")
    try await ServiceEnv.$current.withValue(testEnv) {
        // Assemble assemblies in order (dependencies first)
        await MainActor.run {
            ServiceEnv.current.assemble(
                DatabaseAssembly(),
                LoggerAssembly(),
                RepositoryAssembly(),
                NetworkAssembly()
            )
        }

        // Verify services with dependencies work correctly
        let networkService = ServiceEnv.current.resolve(NetworkServiceProtocol.self)
        let userRepository = ServiceEnv.current.resolve(UserRepositoryProtocol.self)

        // Test network service (depends on logger)
        let response = try await networkService.get(url: "/test")
        #expect(!response.isEmpty)

        // Test user repository (depends on database and logger)
        let user = userRepository.createUser(name: "DI Test User")
        #expect(user.name == "DI Test User")
    }
}

@Test("ServiceAssembly can be used with different environments")
func testAssemblyWithDifferentEnvironments() async throws {
    let env1 = ServiceEnv(name: "env1")
    let env2 = ServiceEnv(name: "env2")

    var service1: DatabaseProtocol?
    var service2: DatabaseProtocol?

    await ServiceEnv.$current.withValue(env1) {
        await MainActor.run {
            ServiceEnv.current.assemble(DatabaseAssembly())
        }
        service1 = ServiceEnv.current.resolve(DatabaseProtocol.self)
    }

    await ServiceEnv.$current.withValue(env2) {
        await MainActor.run {
            ServiceEnv.current.assemble(DatabaseAssembly())
        }
        service2 = ServiceEnv.current.resolve(DatabaseProtocol.self)
    }

    // Verify services are isolated per environment
    #expect(service1 != nil)
    #expect(service2 != nil)
    #expect(service1?.connect() == service2?.connect())  // Same implementation
}
