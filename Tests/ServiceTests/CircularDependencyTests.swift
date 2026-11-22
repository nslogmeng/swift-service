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

    @Test func detectsCycleWhenResolvingThroughSubclassMetatype() {
        let env = ServiceEnv(name: "circular-test-subclass-metatype")
        env.register(BaseClassService.self) {
            try env.resolve(BaseClassService.self)
        }

        // The metatype value names the subclass, and the resolution runs the factory of the base class.
        let metatype: BaseClassService.Type = SubclassService.self
        let error = #expect(throws: ServiceError.self) { try env.resolve(metatype) }
        guard case .circularDependency(let serviceType, _) = error else {
            Issue.record("Expected circularDependency, got \(String(describing: error))")
            return
        }
        #expect(serviceType == "BaseClassService")
    }

    @Test func resolvesCachedDependencyAtDepthLimit() throws {
        let env = ServiceEnv(name: "circular-test-cached-at-depth-limit")
        env.register(Int.self) { 42 }
        env.register(String.self, scope: .transient) {
            "Value: \(try env.resolve(Int.self))"
        }
        try env.resolve(Int.self)

        // With a limit of 1, the factory of `String` uses the whole depth.
        // The cached `Int` needs no factory, so resolving it adds no depth.
        let value = try ServiceEnv.$maxResolutionDepth.withValue(1) {
            try env.resolve(String.self)
        }
        #expect(value == "Value: 42")

        // After a reset, the factory of `Int` has to run inside the factory of `String`.
        env.resetCaches()
        ServiceEnv.$maxResolutionDepth.withValue(1) {
            let error = #expect(throws: ServiceError.self) { try env.resolve(String.self) }
            guard case .maxDepthExceeded = error else {
                Issue.record("Expected maxDepthExceeded, got \(String(describing: error))")
                return
            }
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

    // MARK: - Same Short Name, Different Types

    @Test func resolvesDistinctTypesSharingShortName() async throws {
        let testEnv = ServiceEnv(name: "circular-test-same-name")
        try ServiceEnv.$current.withValue(testEnv) {
            ServiceEnv.current.register(NamespaceA.Config.self) { NamespaceA.Config(value: "a") }
            ServiceEnv.current.register(NamespaceB.Config.self) {
                NamespaceB.Config(a: try ServiceEnv.current.resolve(NamespaceA.Config.self))
            }

            let result = try ServiceEnv.current.resolve(NamespaceB.Config.self)
            #expect(result.a.value == "a")
        }
    }

    @Test func resolvesMainActorDistinctTypesSharingShortName() async throws {
        let testEnv = ServiceEnv(name: "circular-test-same-name-main")
        try await ServiceEnv.$current.withValue(testEnv) {
            try await MainActor.run {
                ServiceEnv.current.registerMain(NamespaceA.MainConfig.self) {
                    let service = NamespaceA.MainConfig()
                    service.value = "a"
                    return service
                }
                ServiceEnv.current.registerMain(NamespaceB.MainConfig.self) {
                    let service = NamespaceB.MainConfig()
                    service.value = try ServiceEnv.current.resolveMain(NamespaceA.MainConfig.self).value
                    return service
                }

                let result = try ServiceEnv.current.resolveMain(NamespaceB.MainConfig.self)
                #expect(result.value == "a")
            }
        }
    }

    @Test func detectsCycleBetweenTypesSharingShortName() async throws {
        let testEnv = ServiceEnv(name: "circular-test-same-name-cycle")
        ServiceEnv.$current.withValue(testEnv) {
            ServiceEnv.current.register(NamespaceA.CyclicConfig.self) {
                _ = try ServiceEnv.current.resolve(NamespaceB.CyclicConfig.self)
                return NamespaceA.CyclicConfig()
            }
            ServiceEnv.current.register(NamespaceB.CyclicConfig.self) {
                _ = try ServiceEnv.current.resolve(NamespaceA.CyclicConfig.self)
                return NamespaceB.CyclicConfig()
            }

            do {
                _ = try ServiceEnv.current.resolve(NamespaceA.CyclicConfig.self)
                Issue.record("Expected circularDependency to be thrown")
            } catch ServiceError.circularDependency(let serviceType, let chain) {
                #expect(serviceType == "CyclicConfig")
                #expect(chain == ["CyclicConfig", "CyclicConfig", "CyclicConfig"])
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }
}

// MARK: - Fixtures

private enum NamespaceA {
    struct Config: Sendable {
        let value: String
    }

    @MainActor final class MainConfig {
        var value = ""
    }

    struct CyclicConfig: Sendable {}
}

private enum NamespaceB {
    struct Config: Sendable {
        let a: NamespaceA.Config
    }

    @MainActor final class MainConfig {
        var value = ""
    }

    struct CyclicConfig: Sendable {}
}
