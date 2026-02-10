//
//  Copyright © 2026 Service Contributors. All rights reserved.
//

import Foundation
import Testing

@testable import Service

@Suite("Service Scope Tests")
struct ServiceScopeTests {
    // MARK: - Singleton Scope

    @Suite("Singleton Scope")
    struct SingletonScopeTests {
        @Test func returnsSameInstanceOnMultipleResolves() throws {
            let env = ServiceEnv(name: "scope-singleton-test")
            try ServiceEnv.$current.withValue(env) {
                let counter = Counter()
                ServiceEnv.current.register(String.self, scope: .singleton) {
                    counter.increment()
                    return "singleton-\(counter.value)"
                }

                let first = try ServiceEnv.current.resolve(String.self)
                let second = try ServiceEnv.current.resolve(String.self)
                #expect(first == "singleton-1")
                #expect(second == "singleton-1")
                #expect(counter.value == 1)
            }
        }

        @Test func defaultScopeIsSingleton() throws {
            let env = ServiceEnv(name: "scope-default-test")
            try ServiceEnv.$current.withValue(env) {
                let counter = Counter()
                ServiceEnv.current.register(String.self) {
                    counter.increment()
                    return "default-\(counter.value)"
                }

                let first = try ServiceEnv.current.resolve(String.self)
                let second = try ServiceEnv.current.resolve(String.self)
                #expect(first == "default-1")
                #expect(second == "default-1")
                #expect(counter.value == 1)
            }
        }
    }

    // MARK: - Transient Scope

    @Suite("Transient Scope")
    struct TransientScopeTests {
        @Test func returnsNewInstanceOnEachResolve() throws {
            let env = ServiceEnv(name: "scope-transient-test")
            try ServiceEnv.$current.withValue(env) {
                let counter = Counter()
                ServiceEnv.current.register(String.self, scope: .transient) {
                    counter.increment()
                    return "transient-\(counter.value)"
                }

                let first = try ServiceEnv.current.resolve(String.self)
                let second = try ServiceEnv.current.resolve(String.self)
                let third = try ServiceEnv.current.resolve(String.self)
                #expect(first == "transient-1")
                #expect(second == "transient-2")
                #expect(third == "transient-3")
                #expect(counter.value == 3)
            }
        }

        @Test func transientIgnoresCache() throws {
            let env = ServiceEnv(name: "scope-transient-cache-test")
            try ServiceEnv.$current.withValue(env) {
                let counter = Counter()
                ServiceEnv.current.register(Int.self, scope: .transient) {
                    counter.increment()
                    return counter.value
                }

                let a = try ServiceEnv.current.resolve(Int.self)
                let b = try ServiceEnv.current.resolve(Int.self)
                #expect(a == 1)
                #expect(b == 2)

                // resetCaches should not affect transient behavior
                ServiceEnv.current.resetCaches()
                let c = try ServiceEnv.current.resolve(Int.self)
                #expect(c == 3)
            }
        }
    }

    // MARK: - Graph Scope

    @Suite("Graph Scope")
    struct GraphScopeTests {
        @Test func sharesInstanceWithinSameResolutionGraph() throws {
            let env = ServiceEnv(name: "scope-graph-shared-test")
            try ServiceEnv.$current.withValue(env) {
                let counter = Counter()

                // Register a graph-scoped service
                ServiceEnv.current.register(Int.self, scope: .graph) {
                    counter.increment()
                    return counter.value
                }

                // Register two services that both depend on Int
                ServiceEnv.current.register(String.self) {
                    let id = try ServiceEnv.current.resolve(Int.self)
                    return "string-\(id)"
                }
                ServiceEnv.current.register(Double.self) {
                    let id = try ServiceEnv.current.resolve(Int.self)
                    return Double(id) * 10.0
                }

                // Register a top-level service that depends on both
                ServiceEnv.current.register(Bool.self) {
                    let s = try ServiceEnv.current.resolve(String.self)
                    let d = try ServiceEnv.current.resolve(Double.self)
                    // Both should have used the same Int instance (graph-scoped)
                    return s == "string-1" && d == 10.0
                }

                let result = try ServiceEnv.current.resolve(Bool.self)
                #expect(result == true)
                // The graph-scoped Int factory should have been called only once
                #expect(counter.value == 1)
            }
        }

        @Test func createsNewInstanceForDifferentResolutionGraphs() throws {
            let env = ServiceEnv(name: "scope-graph-independent-test")
            try ServiceEnv.$current.withValue(env) {
                let counter = Counter()
                ServiceEnv.current.register(Int.self, scope: .graph) {
                    counter.increment()
                    return counter.value
                }

                // First resolution graph
                let first = try ServiceEnv.current.resolve(Int.self)
                #expect(first == 1)

                // Second resolution graph - should get a new instance
                let second = try ServiceEnv.current.resolve(Int.self)
                #expect(second == 2)

                #expect(counter.value == 2)
            }
        }

        @Test func graphScopeNestedDependencies() throws {
            let env = ServiceEnv(name: "scope-graph-nested-test")
            try ServiceEnv.$current.withValue(env) {
                let counter = Counter()

                // Graph-scoped shared dependency
                ServiceEnv.current.register(Int.self, scope: .graph) {
                    counter.increment()
                    return counter.value
                }

                // Service A uses the graph-scoped Int
                ServiceEnv.current.register(String.self) {
                    let id = try ServiceEnv.current.resolve(Int.self)
                    return "A-\(id)"
                }

                // Service B uses both Int (graph-scoped) and String
                ServiceEnv.current.register(Double.self) {
                    let id = try ServiceEnv.current.resolve(Int.self)
                    let a = try ServiceEnv.current.resolve(String.self)
                    return Double(id) + (a == "A-\(id)" ? 100.0 : 0.0)
                }

                let result = try ServiceEnv.current.resolve(Double.self)
                // Int called once (graph), String resolves Int (same graph), Double resolves both
                #expect(result == 101.0)
                #expect(counter.value == 1)
            }
        }
    }

    // MARK: - MainActor + Scope

    @Suite("MainActor Scope")
    struct MainActorScopeTests {
        @Test @MainActor func mainActorSingleton() throws {
            let env = ServiceEnv(name: "scope-main-singleton-test")
            try ServiceEnv.$current.withValue(env) {
                var callCount = 0
                ServiceEnv.current.registerMain(ViewModelService.self, scope: .singleton) {
                    callCount += 1
                    let vm = ViewModelService()
                    vm.data = "singleton-\(callCount)"
                    return vm
                }

                let first = try ServiceEnv.current.resolveMain(ViewModelService.self)
                let second = try ServiceEnv.current.resolveMain(ViewModelService.self)
                #expect(first.data == "singleton-1")
                #expect(second.data == "singleton-1")
                #expect(first === second)
                #expect(callCount == 1)
            }
        }

        @Test @MainActor func mainActorTransient() throws {
            let env = ServiceEnv(name: "scope-main-transient-test")
            try ServiceEnv.$current.withValue(env) {
                var callCount = 0
                ServiceEnv.current.registerMain(ViewModelService.self, scope: .transient) {
                    callCount += 1
                    let vm = ViewModelService()
                    vm.data = "transient-\(callCount)"
                    return vm
                }

                let first = try ServiceEnv.current.resolveMain(ViewModelService.self)
                let second = try ServiceEnv.current.resolveMain(ViewModelService.self)
                #expect(first.data == "transient-1")
                #expect(second.data == "transient-2")
                #expect(first !== second)
                #expect(callCount == 2)
            }
        }

        @Test @MainActor func mainActorGraph() throws {
            let env = ServiceEnv(name: "scope-main-graph-test")
            try ServiceEnv.$current.withValue(env) {
                var callCount = 0
                ServiceEnv.current.registerMain(MainActorConfigService.self, scope: .graph) {
                    callCount += 1
                    let svc = MainActorConfigService()
                    svc.config = "graph-\(callCount)"
                    return svc
                }

                // Each top-level resolve creates a new graph
                let first = try ServiceEnv.current.resolveMain(MainActorConfigService.self)
                let second = try ServiceEnv.current.resolveMain(MainActorConfigService.self)
                #expect(first.config == "graph-1")
                #expect(second.config == "graph-2")
                #expect(callCount == 2)
            }
        }
    }

    // MARK: - ServiceKey + Scope

    @Suite("ServiceKey with Scope")
    struct ServiceKeyScopeTests {
        @Test func serviceKeyWithTransientScope() throws {
            let env = ServiceEnv(name: "scope-key-transient-test")
            try ServiceEnv.$current.withValue(env) {
                ServiceEnv.current.register(CountingServiceKey.self, scope: .transient)

                let first = try ServiceEnv.current.resolve(CountingServiceKey.self)
                let second = try ServiceEnv.current.resolve(CountingServiceKey.self)
                // Each resolution creates a new instance via ServiceKey.default
                #expect(first.id != second.id)
            }
        }

        @Test func serviceKeyDefaultsToSingleton() throws {
            let env = ServiceEnv(name: "scope-key-default-test")
            try ServiceEnv.$current.withValue(env) {
                ServiceEnv.current.register(CountingServiceKey.self)

                let first = try ServiceEnv.current.resolve(CountingServiceKey.self)
                let second = try ServiceEnv.current.resolve(CountingServiceKey.self)
                #expect(first.id == second.id)
            }
        }

        @Test @MainActor func mainActorServiceKeyWithScope() throws {
            let env = ServiceEnv(name: "scope-main-key-test")
            try ServiceEnv.$current.withValue(env) {
                ServiceEnv.current.registerMain(MainActorKeyService.self, scope: .transient)

                let first = try ServiceEnv.current.resolveMain(MainActorKeyService.self)
                let second = try ServiceEnv.current.resolveMain(MainActorKeyService.self)
                #expect(first !== second)
            }
        }
    }

    // MARK: - Custom Scope

    @Suite("Custom Scope")
    struct CustomScopeTests {
        @Test func cachesWithinSameScopeName() throws {
            let env = ServiceEnv(name: "scope-custom-cache-test")
            try ServiceEnv.$current.withValue(env) {
                let counter = Counter()
                ServiceEnv.current.register(String.self, scope: .custom("session")) {
                    counter.increment()
                    return "session-\(counter.value)"
                }

                let first = try ServiceEnv.current.resolve(String.self)
                let second = try ServiceEnv.current.resolve(String.self)
                #expect(first == "session-1")
                #expect(second == "session-1")
                #expect(counter.value == 1)
            }
        }

        @Test func differentScopeNamesReturnDifferentInstances() throws {
            let env = ServiceEnv(name: "scope-custom-isolation-test")
            try ServiceEnv.$current.withValue(env) {
                let counter = Counter()
                ServiceEnv.current.register(String.self, scope: .custom("scopeA")) {
                    counter.increment()
                    return "A-\(counter.value)"
                }
                ServiceEnv.current.register(Int.self, scope: .custom("scopeB")) {
                    counter.increment()
                    return counter.value
                }

                let strVal = try ServiceEnv.current.resolve(String.self)
                let intVal = try ServiceEnv.current.resolve(Int.self)
                #expect(strVal == "A-1")
                #expect(intVal == 2)
                #expect(counter.value == 2)
            }
        }

        @Test func resetScopeClearsOnlyTargetScope() throws {
            let env = ServiceEnv(name: "scope-custom-reset-test")
            try ServiceEnv.$current.withValue(env) {
                let counter = Counter()
                ServiceEnv.current.register(String.self, scope: .custom("sessionA")) {
                    counter.increment()
                    return "A-\(counter.value)"
                }
                ServiceEnv.current.register(Int.self, scope: .custom("sessionB")) {
                    counter.increment()
                    return counter.value
                }

                // Resolve both
                let a1 = try ServiceEnv.current.resolve(String.self)
                let b1 = try ServiceEnv.current.resolve(Int.self)
                #expect(a1 == "A-1")
                #expect(b1 == 2)

                // Reset only sessionA
                ServiceEnv.current.resetScope(.custom("sessionA"))

                // sessionA should create a new instance
                let a2 = try ServiceEnv.current.resolve(String.self)
                #expect(a2 == "A-3")

                // sessionB should still return cached instance
                let b2 = try ServiceEnv.current.resolve(Int.self)
                #expect(b2 == 2)
            }
        }

        @Test func resetCachesClearsAllCustomScopes() throws {
            let env = ServiceEnv(name: "scope-custom-resetall-test")
            try ServiceEnv.$current.withValue(env) {
                let counter = Counter()
                ServiceEnv.current.register(String.self, scope: .custom("scope1")) {
                    counter.increment()
                    return "s-\(counter.value)"
                }

                let first = try ServiceEnv.current.resolve(String.self)
                #expect(first == "s-1")

                // resetCaches should clear custom scopes too
                ServiceEnv.current.resetCaches()

                let second = try ServiceEnv.current.resolve(String.self)
                #expect(second == "s-2")
            }
        }

        @Test @MainActor func mainActorCustomScope() throws {
            let env = ServiceEnv(name: "scope-main-custom-test")
            try ServiceEnv.$current.withValue(env) {
                var callCount = 0
                ServiceEnv.current.registerMain(ViewModelService.self, scope: .custom("ui")) {
                    callCount += 1
                    let vm = ViewModelService()
                    vm.data = "custom-\(callCount)"
                    return vm
                }

                let first = try ServiceEnv.current.resolveMain(ViewModelService.self)
                let second = try ServiceEnv.current.resolveMain(ViewModelService.self)
                #expect(first.data == "custom-1")
                #expect(first === second)
                #expect(callCount == 1)

                // Reset the custom scope
                ServiceEnv.current.resetScope(.custom("ui"))

                let third = try ServiceEnv.current.resolveMain(ViewModelService.self)
                #expect(third.data == "custom-2")
                #expect(third !== first)
            }
        }
    }

    // MARK: - Backward Compatibility

    @Suite("Backward Compatibility")
    struct BackwardCompatibilityTests {
        @Test func existingCodeWorksWithoutScopeParameter() throws {
            let env = ServiceEnv(name: "scope-compat-test")
            try ServiceEnv.$current.withValue(env) {
                // Old-style registration without scope parameter
                ServiceEnv.current.register(String.self) { "compatible" }
                ServiceEnv.current.register(Int.self) { 42 }

                let str = try ServiceEnv.current.resolve(String.self)
                let num = try ServiceEnv.current.resolve(Int.self)
                #expect(str == "compatible")
                #expect(num == 42)

                // Should be singleton by default
                let str2 = try ServiceEnv.current.resolve(String.self)
                #expect(str2 == "compatible")
            }
        }

        @Test func instanceRegistrationAlwaysSingleton() throws {
            let env = ServiceEnv(name: "scope-instance-test")
            try ServiceEnv.$current.withValue(env) {
                ServiceEnv.current.register("direct-instance")

                let first = try ServiceEnv.current.resolve(String.self)
                let second = try ServiceEnv.current.resolve(String.self)
                #expect(first == "direct-instance")
                #expect(second == "direct-instance")
            }
        }

        @Test @MainActor func mainActorInstanceRegistrationAlwaysSingleton() throws {
            let env = ServiceEnv(name: "scope-main-instance-test")
            try ServiceEnv.$current.withValue(env) {
                let vm = ViewModelService()
                vm.data = "direct"
                ServiceEnv.current.registerMain(vm)

                let first = try ServiceEnv.current.resolveMain(ViewModelService.self)
                let second = try ServiceEnv.current.resolveMain(ViewModelService.self)
                #expect(first.data == "direct")
                #expect(first === second)
            }
        }
    }
}

// MARK: - Test Helpers

extension ServiceScopeTests {
    final class Counter: @unchecked Sendable {
        var value: Int = 0

        func increment() {
            value += 1
        }
    }
}

struct CountingServiceKey: ServiceKey {
    let id: String

    static var `default`: CountingServiceKey {
        CountingServiceKey(id: UUID().uuidString)
    }
}
