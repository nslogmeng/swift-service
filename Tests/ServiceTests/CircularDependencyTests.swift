//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

import Foundation
import Testing

@testable import Service

// MARK: - Circular Dependency Detection Tests

/// Tests for circular dependency detection functionality.
/// Note: Actual circular dependencies would cause fatalError, which cannot be tested directly.
/// These tests verify that normal resolution works correctly and the resolution stack is managed properly.

@Test("Normal dependency chain resolves without false positives")
func testNormalDependencyChain() async throws {
    let testEnv = ServiceEnv(name: "circular-test-normal")
    ServiceEnv.$current.withValue(testEnv) {
        // Register a chain: String depends on Int
        ServiceEnv.current.register(Int.self) { 42 }
        ServiceEnv.current.register(String.self) {
            let num = ServiceEnv.current.resolve(Int.self)
            return "Value: \(num)"
        }

        // Should resolve the chain correctly without detecting false circular dependency
        let result = ServiceEnv.current.resolve(String.self)
        #expect(result == "Value: 42")
    }
}

@Test("Deep dependency chain resolves correctly")
func testDeepDependencyChain() async throws {
    let testEnv = ServiceEnv(name: "circular-test-deep")
    ServiceEnv.$current.withValue(testEnv) {
        // Register a deeper chain: A -> B -> C -> D
        ServiceEnv.current.register(Int.self) { 1 }
        ServiceEnv.current.register(Double.self) {
            Double(ServiceEnv.current.resolve(Int.self))
        }
        ServiceEnv.current.register(Float.self) {
            Float(ServiceEnv.current.resolve(Double.self))
        }
        ServiceEnv.current.register(String.self) {
            String(ServiceEnv.current.resolve(Float.self))
        }

        // Should resolve the entire chain
        let result = ServiceEnv.current.resolve(String.self)
        #expect(result == "1.0")
    }
}

@Test("Independent services resolve without interference")
func testIndependentServices() async throws {
    let testEnv = ServiceEnv(name: "circular-test-independent")
    ServiceEnv.$current.withValue(testEnv) {
        // Register independent services (no dependencies between them)
        ServiceEnv.current.register(String.self) { "ServiceA" }
        ServiceEnv.current.register(Int.self) { 100 }
        ServiceEnv.current.register(Double.self) { 3.14 }

        // Should resolve all without issues
        let strService = ServiceEnv.current.resolve(String.self)
        let intService = ServiceEnv.current.resolve(Int.self)
        let doubleService = ServiceEnv.current.resolve(Double.self)

        #expect(strService == "ServiceA")
        #expect(intService == 100)
        #expect(doubleService == 3.14)
    }
}

@Test("Same service resolved multiple times returns cached instance")
func testSameServiceMultipleResolutions() async throws {
    let testEnv = ServiceEnv(name: "circular-test-cached")
    ServiceEnv.$current.withValue(testEnv) {
        // Use UUID to verify singleton behavior
        ServiceEnv.current.register(String.self) {
            UUID().uuidString
        }

        // First resolution creates the instance
        let first = ServiceEnv.current.resolve(String.self)

        // Subsequent resolutions return cached instance (no circular dependency false positive)
        let second = ServiceEnv.current.resolve(String.self)
        let third = ServiceEnv.current.resolve(String.self)

        // All resolutions should return the same instance
        #expect(first == second)
        #expect(second == third)
    }
}

@Test("MainActor service dependency chain resolves correctly")
func testMainActorDependencyChain() async throws {
    let testEnv = ServiceEnv(name: "circular-test-mainactor")
    await ServiceEnv.$current.withValue(testEnv) {
        await MainActor.run {
            // Register MainActor services with dependencies
            ServiceEnv.current.registerMain(MainActorConfigService.self) {
                let service = MainActorConfigService()
                service.config = "base-config"
                return service
            }

            ServiceEnv.current.registerMain(ViewModelService.self) {
                // This depends on MainActorConfigService
                let config = ServiceEnv.current.resolveMain(MainActorConfigService.self)
                let vm = ViewModelService()
                vm.data = config.config
                return vm
            }

            // Should resolve the chain correctly
            let viewModel = ServiceEnv.current.resolveMain(ViewModelService.self)
            #expect(viewModel.data == "base-config")
        }
    }
}

@Test("Mixed Sendable and MainActor dependency chain")
func testMixedDependencyChain() async throws {
    let testEnv = ServiceEnv(name: "circular-test-mixed")
    await ServiceEnv.$current.withValue(testEnv) {
        // Register Sendable service
        ServiceEnv.current.register(String.self) { "config-value" }

        await MainActor.run {
            // Register MainActor service that depends on Sendable service
            ServiceEnv.current.registerMain(ViewModelService.self) {
                let config = ServiceEnv.current.resolve(String.self)
                let vm = ViewModelService()
                vm.data = config
                return vm
            }

            // Should resolve correctly
            let viewModel = ServiceEnv.current.resolveMain(ViewModelService.self)
            #expect(viewModel.data == "config-value")
        }
    }
}

// MARK: - Resolution Stack Verification

@Test("Resolution completes cleanly without stack pollution")
func testResolutionStackCleanup() async throws {
    let testEnv = ServiceEnv(name: "circular-test-stack")
    ServiceEnv.$current.withValue(testEnv) {
        ServiceEnv.current.register(String.self) { "test" }

        // Resolve multiple times
        _ = ServiceEnv.current.resolve(String.self)
        _ = ServiceEnv.current.resolve(String.self)
        _ = ServiceEnv.current.resolve(String.self)

        // Stack should be clean after each resolution
        // (If stack wasn't cleaned, we might see false circular dependency errors)
        let result = ServiceEnv.current.resolve(String.self)
        #expect(result == "test")
    }
}

@Test("Nested resolution in different environments")
func testNestedResolutionDifferentEnvironments() async throws {
    let env1 = ServiceEnv(name: "circular-env1")
    let env2 = ServiceEnv(name: "circular-env2")

    ServiceEnv.$current.withValue(env1) {
        ServiceEnv.current.register(String.self) { "env1-value" }

        ServiceEnv.$current.withValue(env2) {
            ServiceEnv.current.register(String.self) { "env2-value" }

            // Should resolve env2's service
            let result = ServiceEnv.current.resolve(String.self)
            #expect(result == "env2-value")
        }

        // Should resolve env1's service
        let result = ServiceEnv.current.resolve(String.self)
        #expect(result == "env1-value")
    }
}
