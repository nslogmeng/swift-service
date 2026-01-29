//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

import Foundation
import Testing

@testable import Service

@Suite("ServiceAssembly Tests")
struct ServiceAssemblyTests {
    // MARK: - Single Assembly

    @Test func registersServicesWithSingleAssembly() async throws {
        let testEnv = ServiceEnv(name: "assembly-test")
        try await ServiceEnv.$current.withValue(testEnv) {
            await MainActor.run {
                ServiceEnv.current.assemble(DatabaseAssembly())
            }

            let database = try ServiceEnv.current.resolve(DatabaseProtocol.self)
            let connectionInfo = database.connect()
            #expect(connectionInfo.contains("sqlite://assembly.db"))
        }
    }

    // MARK: - Multiple Assemblies

    @Test func appliesMultipleAssembliesWithArray() async throws {
        let testEnv = ServiceEnv(name: "multi-assembly-test")
        try await ServiceEnv.$current.withValue(testEnv) { @MainActor in
            await MainActor.run {
                ServiceEnv.current.assemble([
                    DatabaseAssembly(),
                    LoggerAssembly(),
                ])
            }

            let database = try ServiceEnv.current.resolve(DatabaseProtocol.self)
            let logger = try ServiceEnv.current.resolve(LoggerProtocol.self)

            #expect(database.connect().contains("sqlite://assembly.db"))
            logger.info("Testing logger from assembly")
        }
    }

    @Test func appliesMultipleAssembliesWithVariadicArguments() async throws {
        let testEnv = ServiceEnv(name: "variadic-assembly-test")
        try await ServiceEnv.$current.withValue(testEnv) {
            await MainActor.run {
                ServiceEnv.current.assemble(
                    DatabaseAssembly(),
                    LoggerAssembly(),
                    RepositoryAssembly()
                )
            }

            let userRepository = try ServiceEnv.current.resolve(UserRepositoryProtocol.self)
            let user = userRepository.createUser(name: "Assembly User")

            #expect(user.name == "Assembly User")
            #expect(!user.id.isEmpty)
        }
    }

    // MARK: - Dependency Injection

    @Test func supportsDependencyInjectionBetweenAssemblies() async throws {
        let testEnv = ServiceEnv(name: "assembly-di-test")
        try await ServiceEnv.$current.withValue(testEnv) {
            await MainActor.run {
                ServiceEnv.current.assemble(
                    DatabaseAssembly(),
                    LoggerAssembly(),
                    RepositoryAssembly(),
                    NetworkAssembly()
                )
            }

            let networkService = try ServiceEnv.current.resolve(NetworkServiceProtocol.self)
            let userRepository = try ServiceEnv.current.resolve(UserRepositoryProtocol.self)

            let response = try await networkService.get(url: "/test")
            #expect(!response.isEmpty)

            let user = userRepository.createUser(name: "DI Test User")
            #expect(user.name == "DI Test User")
        }
    }

    // MARK: - Environment Isolation

    @Test func isolatesAssembliesAcrossDifferentEnvironments() async throws {
        let env1 = ServiceEnv(name: "env1")
        let env2 = ServiceEnv(name: "env2")

        var service1: DatabaseProtocol?
        var service2: DatabaseProtocol?

        try await ServiceEnv.$current.withValue(env1) {
            await MainActor.run {
                ServiceEnv.current.assemble(DatabaseAssembly())
            }
            service1 = try ServiceEnv.current.resolve(DatabaseProtocol.self)
        }

        try await ServiceEnv.$current.withValue(env2) {
            await MainActor.run {
                ServiceEnv.current.assemble(DatabaseAssembly())
            }
            service2 = try ServiceEnv.current.resolve(DatabaseProtocol.self)
        }

        #expect(service1 != nil)
        #expect(service2 != nil)
        #expect(service1?.connect() == service2?.connect())
    }
}
