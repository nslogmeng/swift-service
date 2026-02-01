//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

import Foundation
import Testing

@testable import Service

@Suite("MainActor Registration Tests")
struct MainActorRegistrationTests {
    // MARK: - Value Types

    @Test func registersAndResolvesValueTypes() async throws {
        let testEnv = ServiceEnv(name: "mainactor-value-types-test")
        try await ServiceEnv.$current.withValue(testEnv) {
            try await MainActor.run {
                ServiceEnv.current.registerMain(Int.self) { 100 }
                ServiceEnv.current.registerMain(String.self) { "main-actor-string" }

                let intValue = try ServiceEnv.current.resolveMain(Int.self)
                let stringValue = try ServiceEnv.current.resolveMain(String.self)

                #expect(intValue == 100)
                #expect(stringValue == "main-actor-string")
            }
        }
    }

    // MARK: - Struct Types

    @Test func registersAndResolvesStructTypes() async throws {
        let testEnv = ServiceEnv(name: "mainactor-struct-types-test")
        try await ServiceEnv.$current.withValue(testEnv) {
            try await MainActor.run {
                ServiceEnv.current.registerMain(MainConfig.self) {
                    MainConfig(theme: "dark", fontSize: 16)
                }

                let config = try ServiceEnv.current.resolveMain(MainConfig.self)
                #expect(config.theme == "dark")
                #expect(config.fontSize == 16)
            }
        }
    }

    // MARK: - Direct Instance Registration

    @Test func registersInstanceDirectly() async throws {
        let testEnv = ServiceEnv(name: "mainactor-instance-direct-test")
        try await ServiceEnv.$current.withValue(testEnv) {
            try await MainActor.run {
                let state = MainState()
                state.count = 5
                state.message = "configured"

                ServiceEnv.current.registerMain(state)

                let resolved = try ServiceEnv.current.resolveMain(MainState.self)
                #expect(resolved.count == 5)
                #expect(resolved.message == "configured")
            }
        }
    }

    // MARK: - Factory Environment Access

    @Test func factoryCanAccessEnvironmentDuringCreation() async throws {
        let testEnv = ServiceEnv(name: "mainactor-factory-env-test")
        try await ServiceEnv.$current.withValue(testEnv) {
            try await MainActor.run {
                ServiceEnv.current.registerMain(String.self) {
                    "MainActor service for \(ServiceEnv.current.name)"
                }

                let service = try ServiceEnv.current.resolveMain(String.self)
                #expect(service == "MainActor service for mainactor-factory-env-test")
            }
        }
    }

    // MARK: - Override Registration

    @Test func overridesRegistrationAfterCacheClear() async throws {
        let testEnv = ServiceEnv(name: "mainactor-multiple-same-test")
        try await ServiceEnv.$current.withValue(testEnv) {
            try await MainActor.run {
                ServiceEnv.current.registerMain(String.self) { "first-main-service" }

                let service1 = try ServiceEnv.current.resolveMain(String.self)
                #expect(service1 == "first-main-service")

                ServiceEnv.current.registerMain(String.self) { "second-main-service" }

                let service2 = try ServiceEnv.current.resolveMain(String.self)
                #expect(service2 == "first-main-service")
            }

            ServiceEnv.current.resetCaches()

            try await MainActor.run {
                let service3 = try ServiceEnv.current.resolveMain(String.self)
                #expect(service3 == "second-main-service")
            }
        }
    }

    // MARK: - Nested Dependencies

    @Test func resolvesNestedDependencies() async throws {
        let testEnv = ServiceEnv(name: "mainactor-nested-deps-test")
        try await ServiceEnv.$current.withValue(testEnv) {
            try await MainActor.run {
                ServiceEnv.current.registerMain(MainServiceA.self) {
                    MainServiceA()
                }

                ServiceEnv.current.registerMain(MainServiceB.self) {
                    let a = try ServiceEnv.current.resolveMain(MainServiceA.self)
                    return MainServiceB(serviceA: a)
                }

                ServiceEnv.current.registerMain(MainServiceC.self) {
                    let b = try ServiceEnv.current.resolveMain(MainServiceB.self)
                    return MainServiceC(serviceB: b)
                }

                let serviceC = try ServiceEnv.current.resolveMain(MainServiceC.self)
                #expect(serviceC.value == "C")
                #expect(serviceC.serviceB.value == "B")
                #expect(serviceC.serviceB.serviceA.value == "A")
            }
        }
    }

    // MARK: - Optional Types

    @Test func registersOptionalTypes() async throws {
        let testEnv = ServiceEnv(name: "mainactor-optional-test")
        try await ServiceEnv.$current.withValue(testEnv) {
            try await MainActor.run {
                ServiceEnv.current.registerMain(OptionalString.self) {
                    OptionalString(value: "optional-main-value")
                }

                let optionalString = try ServiceEnv.current.resolveMain(OptionalString.self)
                #expect(optionalString.value == "optional-main-value")

                ServiceEnv.current.registerMain(OptionalInt.self) {
                    OptionalInt(value: nil)
                }

                let optionalInt = try ServiceEnv.current.resolveMain(OptionalInt.self)
                #expect(optionalInt.value == nil)
            }
        }
    }
}
