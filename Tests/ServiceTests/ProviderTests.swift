//
//  Copyright © 2026 Service Contributors. All rights reserved.
//

import Testing

@testable import Service

@Suite("Provider Tests")
struct ProviderTests {
    // MARK: - @Provider

    @Suite("@Provider")
    struct SendableProviderTests {
        @Test func transientReturnsNewInstanceEachAccess() {
            let env = ServiceEnv(name: "provider-transient-test")
            ServiceEnv.$current.withValue(env) {
                let counter = ProviderCounter()
                ServiceEnv.current.register(String.self, scope: .transient) {
                    counter.increment()
                    return "value-\(counter.value)"
                }

                let container = TransientContainer()
                let first = container.service
                let second = container.service
                let third = container.service
                #expect(first == "value-1")
                #expect(second == "value-2")
                #expect(third == "value-3")
            }
        }

        @Test func singletonReturnsSameInstanceEachAccess() {
            let env = ServiceEnv(name: "provider-singleton-test")
            ServiceEnv.$current.withValue(env) {
                let counter = ProviderCounter()
                ServiceEnv.current.register(String.self, scope: .singleton) {
                    counter.increment()
                    return "singleton-\(counter.value)"
                }

                let container = TransientContainer()
                let first = container.service
                let second = container.service
                #expect(first == "singleton-1")
                #expect(second == "singleton-1")
                #expect(counter.value == 1)
            }
        }

        @Test func optionalReturnsNilWhenNotRegistered() {
            let env = ServiceEnv(name: "provider-optional-test")
            ServiceEnv.$current.withValue(env) {
                let container = OptionalProviderContainer()
                let value = container.service
                #expect(value == nil)
            }
        }

        @Test func optionalReturnsValueWhenRegistered() {
            let env = ServiceEnv(name: "provider-optional-registered-test")
            ServiceEnv.$current.withValue(env) {
                ServiceEnv.current.register(String.self) { "hello" }

                let container = OptionalProviderContainer()
                let value = container.service
                #expect(value == "hello")
            }
        }

        @Test func withExplicitType() {
            let env = ServiceEnv(name: "provider-explicit-type-test")
            ServiceEnv.$current.withValue(env) {
                ServiceEnv.current.register(String.self, scope: .transient) { "explicit" }

                let container = ExplicitTypeProviderContainer()
                let value = container.service
                #expect(value == "explicit")
            }
        }

        @Test func customScopeRespectsCache() {
            let env = ServiceEnv(name: "provider-custom-scope-test")
            ServiceEnv.$current.withValue(env) {
                let counter = ProviderCounter()
                ServiceEnv.current.register(String.self, scope: .custom("session")) {
                    counter.increment()
                    return "session-\(counter.value)"
                }

                let container = TransientContainer()
                let first = container.service
                let second = container.service
                #expect(first == "session-1")
                #expect(second == "session-1")

                // Reset the scope, should get new instance
                ServiceEnv.current.resetScope(.custom("session"))
                let third = container.service
                #expect(third == "session-2")
            }
        }
    }

    // MARK: - @MainProvider

    @Suite("@MainProvider")
    struct MainProviderTests {
        @Test @MainActor func basicResolution() {
            let env = ServiceEnv(name: "main-provider-basic-test")
            ServiceEnv.$current.withValue(env) {
                var callCount = 0
                ServiceEnv.current.registerMain(ViewModelService.self, scope: .transient) {
                    callCount += 1
                    let vm = ViewModelService()
                    vm.data = "main-\(callCount)"
                    return vm
                }

                let container = MainProviderContainer()
                let first = container.viewModel
                let second = container.viewModel
                #expect(first.data == "main-1")
                #expect(second.data == "main-2")
                #expect(first !== second)
            }
        }

        @Test @MainActor func singletonReturnsSameInstance() {
            let env = ServiceEnv(name: "main-provider-singleton-test")
            ServiceEnv.$current.withValue(env) {
                var callCount = 0
                ServiceEnv.current.registerMain(ViewModelService.self, scope: .singleton) {
                    callCount += 1
                    let vm = ViewModelService()
                    vm.data = "singleton-\(callCount)"
                    return vm
                }

                let container = MainProviderContainer()
                let first = container.viewModel
                let second = container.viewModel
                #expect(first.data == "singleton-1")
                #expect(first === second)
                #expect(callCount == 1)
            }
        }

        @Test @MainActor func optionalReturnsNilWhenNotRegistered() {
            let env = ServiceEnv(name: "main-provider-optional-test")
            ServiceEnv.$current.withValue(env) {
                let container = OptionalMainProviderContainer()
                let value = container.viewModel
                #expect(value == nil)
            }
        }

        @Test @MainActor func optionalReturnsValueWhenRegistered() {
            let env = ServiceEnv(name: "main-provider-optional-registered-test")
            ServiceEnv.$current.withValue(env) {
                ServiceEnv.current.registerMain(ViewModelService.self) {
                    let vm = ViewModelService()
                    vm.data = "optional-found"
                    return vm
                }

                let container = OptionalMainProviderContainer()
                let value = container.viewModel
                #expect(value != nil)
                #expect(value?.data == "optional-found")
            }
        }
    }
}

// MARK: - Test Helpers

extension ProviderTests {
    fileprivate final class ProviderCounter: @unchecked Sendable {
        var value: Int = 0

        func increment() {
            value += 1
        }
    }

    fileprivate struct TransientContainer {
        @Provider var service: String
    }

    fileprivate struct OptionalProviderContainer {
        @Provider var service: String?
    }

    fileprivate struct ExplicitTypeProviderContainer {
        @Provider(String.self) var service: String
    }

    @MainActor
    fileprivate struct MainProviderContainer {
        @MainProvider var viewModel: ViewModelService
    }

    @MainActor
    fileprivate struct OptionalMainProviderContainer {
        @MainProvider var viewModel: ViewModelService?
    }
}
