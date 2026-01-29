//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

import Foundation
import Testing

@testable import Service

// MARK: - MainActor Registration Tests

@Test("MainActor service can register and resolve value types")
func testMainActorRegisterValueTypes() async throws {
    let testEnv = ServiceEnv(name: "mainactor-value-types-test")
    try await ServiceEnv.$current.withValue(testEnv) {
        try await MainActor.run {
            // Register Int
            ServiceEnv.current.registerMain(Int.self) {
                100
            }

            // Register String
            ServiceEnv.current.registerMain(String.self) {
                "main-actor-string"
            }

            // Resolve and verify
            let intValue = try ServiceEnv.current.resolveMain(Int.self)
            let stringValue = try ServiceEnv.current.resolveMain(String.self)

            #expect(intValue == 100)
            #expect(stringValue == "main-actor-string")
        }
    }
}

@Test("MainActor service can register and resolve struct types")
func testMainActorRegisterStructTypes() async throws {
    let testEnv = ServiceEnv(name: "mainactor-struct-types-test")
    try await ServiceEnv.$current.withValue(testEnv) {
        try await MainActor.run {
            // Register struct
            ServiceEnv.current.registerMain(MainConfig.self) {
                MainConfig(theme: "dark", fontSize: 16)
            }

            // Resolve and verify
            let config = try ServiceEnv.current.resolveMain(MainConfig.self)
            #expect(config.theme == "dark")
            #expect(config.fontSize == 16)
        }
    }
}

@Test("MainActor service can register instance directly")
func testMainActorRegisterInstanceDirectly() async throws {
    let testEnv = ServiceEnv(name: "mainactor-instance-direct-test")
    try await ServiceEnv.$current.withValue(testEnv) {
        try await MainActor.run {
            // Create instance
            let state = MainState()
            state.count = 5
            state.message = "configured"

            // Register instance directly
            ServiceEnv.current.registerMain(state)

            // Resolve and verify
            let resolved = try ServiceEnv.current.resolveMain(MainState.self)
            #expect(resolved.count == 5)
            #expect(resolved.message == "configured")
        }
    }
}

@Test("MainActor service factory can access environment during creation")
func testMainActorFactoryAccessesEnvironment() async throws {
    let testEnv = ServiceEnv(name: "mainactor-factory-env-test")
    try await ServiceEnv.$current.withValue(testEnv) {
        try await MainActor.run {
            // Register service that depends on environment
            ServiceEnv.current.registerMain(String.self) {
                "MainActor service for \(ServiceEnv.current.name)"
            }

            // Resolve and verify
            let service = try ServiceEnv.current.resolveMain(String.self)
            #expect(service == "MainActor service for mainactor-factory-env-test")
        }
    }
}

@Test("MainActor service can register multiple services of same type")
func testMainActorRegisterMultipleSameType() async throws {
    let testEnv = ServiceEnv(name: "mainactor-multiple-same-test")
    try await ServiceEnv.$current.withValue(testEnv) {
        try await MainActor.run {
            // Register first service
            ServiceEnv.current.registerMain(String.self) {
                "first-main-service"
            }

            let service1 = try ServiceEnv.current.resolveMain(String.self)
            #expect(service1 == "first-main-service")

            // Register second service (overrides)
            ServiceEnv.current.registerMain(String.self) {
                "second-main-service"
            }

            // Cached instance still returns first
            let service2 = try ServiceEnv.current.resolveMain(String.self)
            #expect(service2 == "first-main-service")
        }

        // After cache clear, should use new factory
        await ServiceEnv.current.resetCaches()

        try await MainActor.run {
            let service3 = try ServiceEnv.current.resolveMain(String.self)
            #expect(service3 == "second-main-service")
        }
    }
}

@Test("MainActor service can register with nested dependencies")
func testMainActorRegisterWithNestedDependencies() async throws {
    let testEnv = ServiceEnv(name: "mainactor-nested-deps-test")
    try await ServiceEnv.$current.withValue(testEnv) {
        try await MainActor.run {
            // Register services in dependency order
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

            // Resolve and verify
            let serviceC = try ServiceEnv.current.resolveMain(MainServiceC.self)
            #expect(serviceC.value == "C")
            #expect(serviceC.serviceB.value == "B")
            #expect(serviceC.serviceB.serviceA.value == "A")
        }
    }
}

@Test("MainActor service can register optional types")
func testMainActorRegisterOptionalTypes() async throws {
    let testEnv = ServiceEnv(name: "mainactor-optional-test")
    try await ServiceEnv.$current.withValue(testEnv) {
        try await MainActor.run {
            // Register optional String - wrap in Optional
            ServiceEnv.current.registerMain(OptionalString.self) {
                OptionalString(value: "optional-main-value")
            }

            // Resolve and verify
            let optionalString = try ServiceEnv.current.resolveMain(OptionalString.self)
            #expect(optionalString.value == "optional-main-value")

            // Register nil optional
            ServiceEnv.current.registerMain(OptionalInt.self) {
                OptionalInt(value: nil)
            }

            let optionalInt = try ServiceEnv.current.resolveMain(OptionalInt.self)
            #expect(optionalInt.value == nil)
        }
    }
}
