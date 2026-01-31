//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

import Foundation
import Testing

@testable import Service

@Suite("MainActor Service Tests")
struct MainActorServiceTests {
    // MARK: - Singleton Behavior

    @Suite("Singleton Behavior")
    struct SingletonTests {
        @Test func returnsSameInstanceOnMultipleCalls() async throws {
            let testEnv = ServiceEnv(name: "resolvemain-same-instance-test")
            try await ServiceEnv.$current.withValue(testEnv) {
                try await MainActor.run {
                    ServiceEnv.current.registerMain(ViewModelService.self) {
                        ViewModelService()
                    }

                    let service1 = try ServiceEnv.current.resolveMain(ViewModelService.self)
                    let service2 = try ServiceEnv.current.resolveMain(ViewModelService.self)
                    let service3 = try ServiceEnv.current.resolveMain(ViewModelService.self)

                    service1.loadData()
                    #expect(service1.loadCount == 1)
                    #expect(service2.loadCount == 1)
                    #expect(service3.loadCount == 1)

                    service2.loadData()
                    #expect(service1.loadCount == 2)
                    #expect(service2.loadCount == 2)
                    #expect(service3.loadCount == 2)
                }
            }
        }

        @Test func createsNewInstanceAfterCacheClear() async throws {
            let testEnv = ServiceEnv(name: "resolvemain-cache-clear-test")
            try await ServiceEnv.$current.withValue(testEnv) {
                try await MainActor.run {
                    ServiceEnv.current.registerMain(ViewModelService.self) {
                        ViewModelService()
                    }

                    let service1 = try ServiceEnv.current.resolveMain(ViewModelService.self)
                    service1.loadData()
                    service1.loadData()
                    #expect(service1.loadCount == 2)
                }

                await ServiceEnv.current.resetCaches()

                try await MainActor.run {
                    let service2 = try ServiceEnv.current.resolveMain(ViewModelService.self)
                    #expect(service2.loadCount == 0)
                    #expect(service2.data == "initial")
                }
            }
        }
    }

    // MARK: - Multiple Types

    @Suite("Multiple Types")
    struct MultipleTypesTests {
        @Test func resolvesMultipleServiceTypes() async throws {
            let testEnv = ServiceEnv(name: "resolvemain-different-types-test")
            try await ServiceEnv.$current.withValue(testEnv) {
                try await MainActor.run {
                    ServiceEnv.current.registerMain(ServiceA.self) { ServiceA() }
                    ServiceEnv.current.registerMain(ServiceB.self) { ServiceB() }
                    ServiceEnv.current.registerMain(ServiceC.self) { ServiceC() }

                    let serviceA = try ServiceEnv.current.resolveMain(ServiceA.self)
                    let serviceB = try ServiceEnv.current.resolveMain(ServiceB.self)
                    let serviceC = try ServiceEnv.current.resolveMain(ServiceC.self)

                    #expect(serviceA.value == "A")
                    #expect(serviceB.value == "B")
                    #expect(serviceC.value == "C")

                    serviceA.value = "Modified A"
                    #expect(serviceA.value == "Modified A")
                    #expect(serviceB.value == "B")
                    #expect(serviceC.value == "C")
                }
            }
        }
    }

    // MARK: - Registration and Resolution

    @Suite("Registration")
    struct RegistrationTests {
        @Test func registersAndResolvesService() async throws {
            let testEnv = ServiceEnv(name: "mainactor-test")
            try await ServiceEnv.$current.withValue(testEnv) {
                try await MainActor.run {
                    ServiceEnv.current.registerMain(ViewModelService.self) {
                        ViewModelService()
                    }

                    let service = try ServiceEnv.current.resolveMain(ViewModelService.self)
                    #expect(service.data == "initial")

                    service.loadData()
                    #expect(service.data == "loaded")
                    #expect(service.loadCount == 1)
                }
            }
        }

        @Test func supportsCustomFactoryConfiguration() async throws {
            let testEnv = ServiceEnv(name: "mainactor-factory-test")
            try await ServiceEnv.$current.withValue(testEnv) {
                try await MainActor.run {
                    ServiceEnv.current.registerMain(MainActorConfigService.self) {
                        let service = MainActorConfigService()
                        service.config = "custom-config"
                        return service
                    }

                    let service = try ServiceEnv.current.resolveMain(MainActorConfigService.self)
                    #expect(service.config == "custom-config")
                }
            }
        }

        @Test func supportsDirectInstanceRegistration() async throws {
            let testEnv = ServiceEnv(name: "mainactor-instance-test")
            try await ServiceEnv.$current.withValue(testEnv) {
                try await MainActor.run {
                    let instance = ViewModelService()
                    instance.data = "pre-configured"

                    ServiceEnv.current.registerMain(instance)

                    let resolved = try ServiceEnv.current.resolveMain(ViewModelService.self)
                    #expect(resolved.data == "pre-configured")
                }
            }
        }

        @Test func supportsServiceKeyRegistration() async throws {
            let testEnv = ServiceEnv(name: "mainactor-servicekey-test")
            try await ServiceEnv.$current.withValue(testEnv) {
                try await MainActor.run {
                    ServiceEnv.current.registerMain(MainActorKeyService.self)

                    let service = try ServiceEnv.current.resolveMain(MainActorKeyService.self)
                    #expect(service.value == "default-value")

                    let service2 = try ServiceEnv.current.resolveMain(MainActorKeyService.self)
                    service.value = "modified"
                    #expect(service2.value == "modified")
                }
            }
        }
    }

    // MARK: - Property Wrapper

    @Suite("MainService Property Wrapper")
    struct PropertyWrapperTests {
        @Test func resolvesWithPropertyWrapper() async throws {
            let testEnv = ServiceEnv(name: "mainservice-wrapper-test")
            await ServiceEnv.$current.withValue(testEnv) {
                await MainActor.run {
                    ServiceEnv.current.registerMain(ViewModelService.self) {
                        ViewModelService()
                    }

                    let controller = TestController()
                    #expect(controller.viewModel.data == "initial")

                    controller.viewModel.loadData()
                    #expect(controller.viewModel.data == "loaded")
                }
            }
        }

        @Test func supportsExplicitTypeInitializer() async throws {
            let testEnv = ServiceEnv(name: "mainservice-explicit-type-test")
            await ServiceEnv.$current.withValue(testEnv) {
                await MainActor.run {
                    ServiceEnv.current.registerMain(ViewModelService.self) {
                        ViewModelService()
                    }

                    let controller = TestControllerWithExplicitType()
                    #expect(controller.viewModel.data == "initial")

                    controller.viewModel.loadData()
                    #expect(controller.viewModel.data == "loaded")
                }
            }
        }
    }

    // MARK: - Environment Isolation

    @Suite("Environment Isolation")
    struct IsolationTests {
        @Test func isolatesServicesAcrossEnvironments() async throws {
            let env1 = ServiceEnv(name: "mainactor-env1")
            let env2 = ServiceEnv(name: "mainactor-env2")

            await ServiceEnv.$current.withValue(env1) {
                await MainActor.run {
                    ServiceEnv.current.registerMain(ViewModelService.self) {
                        let service = ViewModelService()
                        service.data = "env1-data"
                        return service
                    }
                }
            }

            await ServiceEnv.$current.withValue(env2) {
                await MainActor.run {
                    ServiceEnv.current.registerMain(ViewModelService.self) {
                        let service = ViewModelService()
                        service.data = "env2-data"
                        return service
                    }
                }
            }

            try await ServiceEnv.$current.withValue(env1) {
                try await MainActor.run {
                    let service = try ServiceEnv.current.resolveMain(ViewModelService.self)
                    #expect(service.data == "env1-data")
                }
            }

            try await ServiceEnv.$current.withValue(env2) {
                try await MainActor.run {
                    let service = try ServiceEnv.current.resolveMain(ViewModelService.self)
                    #expect(service.data == "env2-data")
                }
            }
        }
    }

    // MARK: - Reset Behavior

    @Suite("Reset Behavior")
    struct ResetTests {
        @Test func resetCachesClearsServiceCaches() async throws {
            let testEnv = ServiceEnv(name: "mainactor-reset-test")
            try await ServiceEnv.$current.withValue(testEnv) {
                try await MainActor.run {
                    ServiceEnv.current.registerMain(ViewModelService.self) {
                        ViewModelService()
                    }

                    let service1 = try ServiceEnv.current.resolveMain(ViewModelService.self)
                    service1.loadData()
                    #expect(service1.loadCount == 1)
                }

                await ServiceEnv.current.resetCaches()

                try await MainActor.run {
                    let service2 = try ServiceEnv.current.resolveMain(ViewModelService.self)
                    #expect(service2.loadCount == 0)
                    #expect(service2.data == "initial")
                }
            }
        }

        @Test func resetAllClearsServiceProviders() async throws {
            let testEnv = ServiceEnv(name: "mainactor-resetall-test")
            try await ServiceEnv.$current.withValue(testEnv) {
                try await MainActor.run {
                    ServiceEnv.current.registerMain(ViewModelService.self) {
                        ViewModelService()
                    }

                    _ = try ServiceEnv.current.resolveMain(ViewModelService.self)
                }

                await ServiceEnv.current.resetAll()

                try await MainActor.run {
                    ServiceEnv.current.registerMain(ViewModelService.self) {
                        let service = ViewModelService()
                        service.data = "re-registered"
                        return service
                    }

                    let service = try ServiceEnv.current.resolveMain(ViewModelService.self)
                    #expect(service.data == "re-registered")
                }
            }
        }
    }
}

// MARK: - Test Types

extension MainActorServiceTests {
    @MainActor
    final class TestController {
        @MainService
        var viewModel: ViewModelService
    }

    @MainActor
    final class TestControllerWithExplicitType {
        @MainService(ViewModelService.self)
        var viewModel: ViewModelService
    }

    @MainActor
    final class TestControllerWithOptional {
        @MainService var analytics: ViewModelService?
    }
}

// MARK: - Lazy Behavior Tests

extension MainActorServiceTests {
    @Suite("Lazy Behavior")
    struct LazyBehaviorTests {
        @Test func resolvesLazilyOnFirstAccess() async throws {
            let testEnv = ServiceEnv(name: "mainservice-lazy-test")
            await ServiceEnv.$current.withValue(testEnv) {
                await MainActor.run {
                    ServiceEnv.current.registerMain(ViewModelService.self) {
                        ViewModelService()
                    }

                    let controller = TestControllerForLazy()

                    // First access triggers resolution
                    let vm1 = controller.viewModel
                    #expect(vm1.data == "initial")

                    // Modify and verify same instance
                    vm1.data = "modified"
                    let vm2 = controller.viewModel
                    #expect(vm2.data == "modified", "Should return cached instance")
                }
            }
        }

        @Test func capturesEnvironmentAtInitTime() async throws {
            let env1 = ServiceEnv(name: "mainservice-env1")
            let env2 = ServiceEnv(name: "mainservice-env2")

            await ServiceEnv.$current.withValue(env1) {
                await MainActor.run {
                    ServiceEnv.current.registerMain(ViewModelService.self) {
                        let vm = ViewModelService()
                        vm.data = "env1-value"
                        return vm
                    }
                }
            }

            await ServiceEnv.$current.withValue(env2) {
                await MainActor.run {
                    ServiceEnv.current.registerMain(ViewModelService.self) {
                        let vm = ViewModelService()
                        vm.data = "env2-value"
                        return vm
                    }
                }
            }

            // Create controller in env1
            var controller: TestControllerForLazy!
            await ServiceEnv.$current.withValue(env1) {
                await MainActor.run {
                    controller = TestControllerForLazy()
                }
            }

            // Access in env2 - should still get env1 value
            await ServiceEnv.$current.withValue(env2) {
                await MainActor.run {
                    let value = controller.viewModel.data
                    #expect(value == "env1-value", "Should use environment captured at init")
                }
            }
        }
    }

    @MainActor
    final class TestControllerForLazy {
        @MainService var viewModel: ViewModelService
    }
}

// MARK: - Optional MainService Tests

extension MainActorServiceTests {
    @Suite("Optional MainService")
    struct OptionalMainServiceTests {
        @Test func optionalServiceReturnsNilWhenNotRegistered() async throws {
            let testEnv = ServiceEnv(name: "mainservice-optional-nil-test")
            await ServiceEnv.$current.withValue(testEnv) {
                await MainActor.run {
                    let controller = TestControllerWithOptional()
                    #expect(controller.analytics == nil, "Should return nil for unregistered service")
                }
            }
        }

        @Test func optionalServiceReturnsValueWhenRegistered() async throws {
            let testEnv = ServiceEnv(name: "mainservice-optional-value-test")
            await ServiceEnv.$current.withValue(testEnv) {
                await MainActor.run {
                    ServiceEnv.current.registerMain(ViewModelService.self) {
                        let vm = ViewModelService()
                        vm.data = "optional-registered"
                        return vm
                    }

                    let controller = TestControllerWithOptional()
                    #expect(controller.analytics?.data == "optional-registered")
                }
            }
        }
    }
}
