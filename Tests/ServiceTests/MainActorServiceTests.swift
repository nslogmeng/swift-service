//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

import Foundation
import Testing
@testable import Service

// MARK: - MainActor Service Tests

@Test("MainActor resolveMain returns same instance on multiple calls")
func testResolveMainReturnsSameInstance() async throws {
    let testEnv = ServiceEnv(name: "resolvemain-same-instance-test")
    await ServiceEnv.$current.withValue(testEnv) {
        await MainActor.run {
            // Register MainActor service
            ServiceEnv.current.registerMain(ViewModelService.self) {
                ViewModelService()
            }
            
            // Resolve multiple times
            let service1 = ServiceEnv.current.resolveMain(ViewModelService.self)
            let service2 = ServiceEnv.current.resolveMain(ViewModelService.self)
            let service3 = ServiceEnv.current.resolveMain(ViewModelService.self)
            
            // All should be the same instance
            service1.loadData()
            #expect(service1.loadCount == 1)
            #expect(service2.loadCount == 1)  // Same instance
            #expect(service3.loadCount == 1)  // Same instance
            
            service2.loadData()
            #expect(service1.loadCount == 2)  // Same instance
            #expect(service2.loadCount == 2)
            #expect(service3.loadCount == 2)  // Same instance
        }
    }
}

@Test("MainActor resolveMain creates new instance after cache clear")
func testResolveMainCreatesNewInstanceAfterCacheClear() async throws {
    let testEnv = ServiceEnv(name: "resolvemain-cache-clear-test")
    await ServiceEnv.$current.withValue(testEnv) {
        await MainActor.run {
            // Register MainActor service
            ServiceEnv.current.registerMain(ViewModelService.self) {
                ViewModelService()
            }
            
            // Resolve and modify
            let service1 = ServiceEnv.current.resolveMain(ViewModelService.self)
            service1.loadData()
            service1.loadData()
            #expect(service1.loadCount == 2)
        }
        
        // Clear cache
        await ServiceEnv.current.resetCaches()
        
        await MainActor.run {
            // Resolve again - should be new instance
            let service2 = ServiceEnv.current.resolveMain(ViewModelService.self)
            #expect(service2.loadCount == 0)  // New instance, not modified
            #expect(service2.data == "initial")
        }
    }
}

@Test("MainActor resolveMain works with different service types")
func testResolveMainWithDifferentTypes() async throws {
    let testEnv = ServiceEnv(name: "resolvemain-different-types-test")
    await ServiceEnv.$current.withValue(testEnv) {
        await MainActor.run {
            @MainActor
            class ServiceA {
                var value: String = "A"
            }
            
            @MainActor
            class ServiceB {
                var value: String = "B"
            }
            
            @MainActor
            class ServiceC {
                var value: String = "C"
            }
            
            // Register multiple different types
            ServiceEnv.current.registerMain(ServiceA.self) {
                ServiceA()
            }
            
            ServiceEnv.current.registerMain(ServiceB.self) {
                ServiceB()
            }
            
            ServiceEnv.current.registerMain(ServiceC.self) {
                ServiceC()
            }
            
            // Resolve each type
            let serviceA = ServiceEnv.current.resolveMain(ServiceA.self)
            let serviceB = ServiceEnv.current.resolveMain(ServiceB.self)
            let serviceC = ServiceEnv.current.resolveMain(ServiceC.self)
            
            #expect(serviceA.value == "A")
            #expect(serviceB.value == "B")
            #expect(serviceC.value == "C")
            
            // Verify they are different instances
            serviceA.value = "Modified A"
            #expect(serviceA.value == "Modified A")
            #expect(serviceB.value == "B")  // Unchanged
            #expect(serviceC.value == "C")  // Unchanged
        }
    }
}

@Test("MainActor service registration and resolution")
func testMainActorServiceRegistration() async throws {
    let testEnv = ServiceEnv(name: "mainactor-test")
    await ServiceEnv.$current.withValue(testEnv) {
        await MainActor.run {
            // Register MainActor service
            ServiceEnv.current.registerMain(ViewModelService.self) {
                ViewModelService()
            }

            // Resolve and verify
            let service = ServiceEnv.current.resolveMain(ViewModelService.self)
            #expect(service.data == "initial")

            // Modify and verify state
            service.loadData()
            #expect(service.data == "loaded")
            #expect(service.loadCount == 1)
        }
    }
}

@Test("MainActor service singleton behavior")
func testMainActorServiceSingleton() async throws {
    let testEnv = ServiceEnv(name: "mainactor-singleton-test")
    await ServiceEnv.$current.withValue(testEnv) {
        await MainActor.run {
            // Register MainActor service
            ServiceEnv.current.registerMain(ViewModelService.self) {
                ViewModelService()
            }

            // Resolve twice - should return same instance
            let service1 = ServiceEnv.current.resolveMain(ViewModelService.self)
            let service2 = ServiceEnv.current.resolveMain(ViewModelService.self)

            // Verify singleton behavior
            service1.loadData()
            #expect(service1.loadCount == 1)
            #expect(service2.loadCount == 1)  // Same instance

            service2.loadData()
            #expect(service1.loadCount == 2)  // Same instance
            #expect(service2.loadCount == 2)
        }
    }
}

@Test("MainActor service with custom factory configuration")
func testMainActorServiceCustomFactory() async throws {
    let testEnv = ServiceEnv(name: "mainactor-factory-test")
    await ServiceEnv.$current.withValue(testEnv) {
        await MainActor.run {
            // Register with a custom factory that configures the service
            ServiceEnv.current.registerMain(MainActorConfigService.self) {
                let service = MainActorConfigService()
                service.config = "custom-config"
                return service
            }

            // Resolve and verify custom configuration
            let service = ServiceEnv.current.resolveMain(MainActorConfigService.self)
            #expect(service.config == "custom-config")
        }
    }
}

@Test("MainActor service direct instance registration")
func testMainActorServiceDirectInstance() async throws {
    let testEnv = ServiceEnv(name: "mainactor-instance-test")
    await ServiceEnv.$current.withValue(testEnv) {
        await MainActor.run {
            // Create instance first
            let instance = ViewModelService()
            instance.data = "pre-configured"

            // Register instance directly
            ServiceEnv.current.registerMain(instance)

            // Resolve and verify it's the same instance
            let resolved = ServiceEnv.current.resolveMain(ViewModelService.self)
            #expect(resolved.data == "pre-configured")
        }
    }
}

@Test("MainService property wrapper")
func testMainServicePropertyWrapper() async throws {
    let testEnv = ServiceEnv(name: "mainservice-wrapper-test")
    await ServiceEnv.$current.withValue(testEnv) {
        await MainActor.run {
            // Register MainActor service
            ServiceEnv.current.registerMain(ViewModelService.self) {
                ViewModelService()
            }

            // Use property wrapper in a MainActor context
            @MainActor
            class TestController {
                @MainService
                var viewModel: ViewModelService
            }

            let controller = TestController()
            #expect(controller.viewModel.data == "initial")

            controller.viewModel.loadData()
            #expect(controller.viewModel.data == "loaded")
        }
    }
}

@Test("MainActor service environment isolation")
func testMainActorServiceIsolation() async throws {
    let env1 = ServiceEnv(name: "mainactor-env1")
    let env2 = ServiceEnv(name: "mainactor-env2")

    // Register different services in different environments
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

    // Verify isolation
    await ServiceEnv.$current.withValue(env1) {
        await MainActor.run {
            let service = ServiceEnv.current.resolveMain(ViewModelService.self)
            #expect(service.data == "env1-data")
        }
    }

    await ServiceEnv.$current.withValue(env2) {
        await MainActor.run {
            let service = ServiceEnv.current.resolveMain(ViewModelService.self)
            #expect(service.data == "env2-data")
        }
    }
}

@Test("Reset clears MainActor service caches")
func testResetClearsMainActorCaches() async throws {
    let testEnv = ServiceEnv(name: "mainactor-reset-test")
    await ServiceEnv.$current.withValue(testEnv) {
        await MainActor.run {
            // Register MainActor service
            ServiceEnv.current.registerMain(ViewModelService.self) {
                ViewModelService()
            }

            // Resolve and modify
            let service1 = ServiceEnv.current.resolveMain(ViewModelService.self)
            service1.loadData()
            #expect(service1.loadCount == 1)
        }

        // Reset caches (async ensures MainActor caches are cleared)
        await ServiceEnv.current.resetCaches()

        await MainActor.run {
            // Resolve again - should be a new instance
            let service2 = ServiceEnv.current.resolveMain(ViewModelService.self)
            #expect(service2.loadCount == 0)  // New instance, not modified
            #expect(service2.data == "initial")
        }
    }
}

@Test("ResetAll clears MainActor service providers")
func testResetAllClearsMainActorProviders() async throws {
    let testEnv = ServiceEnv(name: "mainactor-resetall-test")
    await ServiceEnv.$current.withValue(testEnv) {
        await MainActor.run {
            // Register MainActor service
            ServiceEnv.current.registerMain(ViewModelService.self) {
                ViewModelService()
            }

            // Verify registration works
            let _ = ServiceEnv.current.resolveMain(ViewModelService.self)
        }

        // Reset all (async ensures MainActor storage is cleared)
        await ServiceEnv.current.resetAll()

        await MainActor.run {
            // Re-register service (previous provider was removed)
            ServiceEnv.current.registerMain(ViewModelService.self) {
                let service = ViewModelService()
                service.data = "re-registered"
                return service
            }

            // Verify new registration works
            let service = ServiceEnv.current.resolveMain(ViewModelService.self)
            #expect(service.data == "re-registered")
        }
    }
}

@Test("MainActor service registration using ServiceKey")
func testMainActorServiceWithServiceKey() async throws {
    let testEnv = ServiceEnv(name: "mainactor-servicekey-test")
    await ServiceEnv.$current.withValue(testEnv) {
        await MainActor.run {
            // Define a MainActor service that conforms to ServiceKey
            // Note: ServiceKey requires nonisolated default, so we use @preconcurrency
            @MainActor
            @preconcurrency
            final class MainActorKeyService: ServiceKey {
                var value: String = "default-value"
                
                nonisolated static var `default`: MainActorKeyService {
                    // This is safe because we're creating a new instance
                    MainActorKeyService()
                }
            }
            
            // Register using ServiceKey
            ServiceEnv.current.registerMain(MainActorKeyService.self)
            
            // Resolve and verify
            let service = ServiceEnv.current.resolveMain(MainActorKeyService.self)
            #expect(service.value == "default-value")
            
            // Verify singleton behavior
            let service2 = ServiceEnv.current.resolveMain(MainActorKeyService.self)
            service.value = "modified"
            #expect(service2.value == "modified")  // Same instance
        }
    }
}

@Test("MainService property wrapper with explicit type initializer")
func testMainServicePropertyWrapperExplicitType() async throws {
    let testEnv = ServiceEnv(name: "mainservice-explicit-type-test")
    await ServiceEnv.$current.withValue(testEnv) {
        await MainActor.run {
            // Register MainActor service
            ServiceEnv.current.registerMain(ViewModelService.self) {
                ViewModelService()
            }
            
            // Use explicit type initializer
            @MainActor
            class TestController {
                @MainService(ViewModelService.self)
                var viewModel: ViewModelService
            }
            
            let controller = TestController()
            #expect(controller.viewModel.data == "initial")
            
            controller.viewModel.loadData()
            #expect(controller.viewModel.data == "loaded")
        }
    }
}
