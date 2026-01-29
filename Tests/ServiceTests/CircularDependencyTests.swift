//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

import Foundation
import Testing

@testable import Service

@Suite("Circular Dependency Detection Tests")
struct CircularDependencyTests {
    // MARK: - Normal Resolution

    @Test func resolvesNormalDependencyChain() async throws {
        let testEnv = ServiceEnv(name: "circular-test-normal")
        try ServiceEnv.$current.withValue(testEnv) {
            ServiceEnv.current.register(Int.self) { 42 }
            ServiceEnv.current.register(String.self) {
                let num = try ServiceEnv.current.resolve(Int.self)
                return "Value: \(num)"
            }

            let result = try ServiceEnv.current.resolve(String.self)
            #expect(result == "Value: 42")
        }
    }

    @Test func resolvesDeepDependencyChain() async throws {
        let testEnv = ServiceEnv(name: "circular-test-deep")
        try ServiceEnv.$current.withValue(testEnv) {
            ServiceEnv.current.register(Int.self) { 1 }
            ServiceEnv.current.register(Double.self) {
                Double(try ServiceEnv.current.resolve(Int.self))
            }
            ServiceEnv.current.register(Float.self) {
                Float(try ServiceEnv.current.resolve(Double.self))
            }
            ServiceEnv.current.register(String.self) {
                String(try ServiceEnv.current.resolve(Float.self))
            }

            let result = try ServiceEnv.current.resolve(String.self)
            #expect(result == "1.0")
        }
    }

    @Test func resolvesIndependentServicesWithoutInterference() async throws {
        let testEnv = ServiceEnv(name: "circular-test-independent")
        try ServiceEnv.$current.withValue(testEnv) {
            ServiceEnv.current.register(String.self) { "ServiceA" }
            ServiceEnv.current.register(Int.self) { 100 }
            ServiceEnv.current.register(Double.self) { 3.14 }

            let strService = try ServiceEnv.current.resolve(String.self)
            let intService = try ServiceEnv.current.resolve(Int.self)
            let doubleService = try ServiceEnv.current.resolve(Double.self)

            #expect(strService == "ServiceA")
            #expect(intService == 100)
            #expect(doubleService == 3.14)
        }
    }

    // MARK: - Caching Behavior

    @Test func returnsCachedInstanceOnMultipleResolutions() async throws {
        let testEnv = ServiceEnv(name: "circular-test-cached")
        try ServiceEnv.$current.withValue(testEnv) {
            ServiceEnv.current.register(String.self) {
                UUID().uuidString
            }

            let first = try ServiceEnv.current.resolve(String.self)
            let second = try ServiceEnv.current.resolve(String.self)
            let third = try ServiceEnv.current.resolve(String.self)

            #expect(first == second)
            #expect(second == third)
        }
    }

    // MARK: - MainActor Dependencies

    @Test func resolvesMainActorDependencyChain() async throws {
        let testEnv = ServiceEnv(name: "circular-test-mainactor")
        try await ServiceEnv.$current.withValue(testEnv) {
            try await MainActor.run {
                ServiceEnv.current.registerMain(MainActorConfigService.self) {
                    let service = MainActorConfigService()
                    service.config = "base-config"
                    return service
                }

                ServiceEnv.current.registerMain(ViewModelService.self) {
                    let config = try ServiceEnv.current.resolveMain(MainActorConfigService.self)
                    let vm = ViewModelService()
                    vm.data = config.config
                    return vm
                }

                let viewModel = try ServiceEnv.current.resolveMain(ViewModelService.self)
                #expect(viewModel.data == "base-config")
            }
        }
    }

    @Test func resolvesMixedSendableAndMainActorDependencyChain() async throws {
        let testEnv = ServiceEnv(name: "circular-test-mixed")
        try await ServiceEnv.$current.withValue(testEnv) {
            ServiceEnv.current.register(String.self) { "config-value" }

            try await MainActor.run {
                ServiceEnv.current.registerMain(ViewModelService.self) {
                    let config = try ServiceEnv.current.resolve(String.self)
                    let vm = ViewModelService()
                    vm.data = config
                    return vm
                }

                let viewModel = try ServiceEnv.current.resolveMain(ViewModelService.self)
                #expect(viewModel.data == "config-value")
            }
        }
    }

    // MARK: - Stack Cleanup

    @Test func cleansResolutionStackAfterCompletion() async throws {
        let testEnv = ServiceEnv(name: "circular-test-stack")
        try ServiceEnv.$current.withValue(testEnv) {
            ServiceEnv.current.register(String.self) { "test" }

            try ServiceEnv.current.resolve(String.self)
            try ServiceEnv.current.resolve(String.self)
            try ServiceEnv.current.resolve(String.self)

            let result = try ServiceEnv.current.resolve(String.self)
            #expect(result == "test")
        }
    }

    @Test func isolatesResolutionAcrossNestedEnvironments() async throws {
        let env1 = ServiceEnv(name: "circular-env1")
        let env2 = ServiceEnv(name: "circular-env2")

        try ServiceEnv.$current.withValue(env1) {
            ServiceEnv.current.register(String.self) { "env1-value" }

            try ServiceEnv.$current.withValue(env2) {
                ServiceEnv.current.register(String.self) { "env2-value" }

                let result = try ServiceEnv.current.resolve(String.self)
                #expect(result == "env2-value")
            }

            let result = try ServiceEnv.current.resolve(String.self)
            #expect(result == "env1-value")
        }
    }
}
