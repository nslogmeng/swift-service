//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

import Testing

@testable import Service

@Suite("ServiceError Tests", .serialized)
struct ServiceErrorTests {
    init() async {
        await ServiceEnv.current.resetAll()
    }

    // MARK: - NotRegistered Error

    @Suite("NotRegistered Error")
    struct NotRegisteredTests {
        init() async {
            await ServiceEnv.current.resetAll()
        }

        @Test func throwsForUnregisteredService() throws {
            #expect(throws: ServiceError.self) {
                try ServiceEnv.current.resolve(Int.self)
            }
        }

        @Test @MainActor func throwsForUnregisteredMainService() throws {
            #expect(throws: ServiceError.self) {
                try ServiceEnv.current.resolveMain(String.self)
            }
        }

        @Test func containsCorrectServiceType() throws {
            do {
                try ServiceEnv.current.resolve(Int.self)
                Issue.record("Expected error to be thrown")
            } catch {
                switch error {
                case .notRegistered(let serviceType):
                    #expect(serviceType == "Int")
                default:
                    Issue.record("Expected notRegistered error")
                }
            }
        }
    }

    // MARK: - Circular Dependency Error

    @Suite("Circular Dependency Error")
    struct CircularDependencyErrorTests {
        init() async {
            await ServiceEnv.current.resetAll()
        }

        @Test @MainActor func throwsForCircularDependencies() throws {
            ServiceEnv.current.assemble(CircularDependencyAssembly())

            #expect(throws: ServiceError.self) {
                try ServiceEnv.current.resolve(CircularA.self)
            }
        }

        @Test @MainActor func containsCorrectChain() throws {
            ServiceEnv.current.assemble(CircularDependencyAssembly())

            do {
                try ServiceEnv.current.resolve(CircularA.self)
                Issue.record("Expected error to be thrown")
            } catch {
                switch error {
                case .circularDependency(let serviceType, let chain):
                    #expect(serviceType == "CircularA")
                    #expect(chain.count == 4)
                    #expect(chain.first == "CircularA")
                    #expect(chain.last == "CircularA")
                default:
                    Issue.record("Expected circularDependency error")
                }
            }
        }
    }

    // MARK: - Max Depth Exceeded Error

    @Suite("Max Depth Exceeded Error")
    struct MaxDepthExceededTests {
        init() async {
            await ServiceEnv.current.resetAll()
        }

        @Test @MainActor func throwsWhenDepthLimitExceeded() throws {
            ServiceEnv.current.assemble(DeepDependencyAssembly())

            ServiceContext.$maxResolutionDepth.withValue(2) {
                #expect(throws: ServiceError.self) {
                    try ServiceEnv.current.resolve(DepthA.self)
                }
            }
        }

        @Test @MainActor func containsCorrectDepth() throws {
            ServiceEnv.current.assemble(DeepDependencyAssembly())

            ServiceContext.$maxResolutionDepth.withValue(2) {
                do {
                    try ServiceEnv.current.resolve(DepthA.self)
                    Issue.record("Expected error to be thrown")
                } catch let error as ServiceError {
                    switch error {
                    case .maxDepthExceeded(let depth, let chain):
                        #expect(depth == 2)
                        #expect(chain.count == 2)
                    default:
                        Issue.record("Expected maxDepthExceeded error")
                    }
                } catch {
                    Issue.record("Unexpected error type: \(error)")
                }
            }
        }
    }

    // MARK: - Factory Failed Error

    @Suite("Factory Failed Error")
    struct FactoryFailedTests {
        init() async {
            await ServiceEnv.current.resetAll()
        }

        @Test func throwsWhenFactoryThrowsNonServiceError() throws {
            ServiceEnv.current.register(String.self) {
                throw TestError.customError
            }

            #expect(throws: ServiceError.self) {
                try ServiceEnv.current.resolve(String.self)
            }
        }

        @Test func containsCorrectServiceTypeAndUnderlyingError() throws {
            ServiceEnv.current.register(String.self) {
                throw TestError.customError
            }

            do {
                try ServiceEnv.current.resolve(String.self)
                Issue.record("Expected error to be thrown")
            } catch {
                switch error {
                case .factoryFailed(let serviceType, let underlyingError):
                    #expect(serviceType == "String")
                    #expect(underlyingError is TestError)
                default:
                    Issue.record("Expected factoryFailed error, got \(error)")
                }
            }
        }

        @Test func propagatesServiceErrorDirectly() throws {
            ServiceEnv.current.register(String.self) {
                throw ServiceError.notRegistered(serviceType: "CustomDependency")
            }

            do {
                try ServiceEnv.current.resolve(String.self)
                Issue.record("Expected error to be thrown")
            } catch {
                switch error {
                case .notRegistered(let serviceType):
                    #expect(serviceType == "CustomDependency")
                default:
                    Issue.record("Expected notRegistered error, got \(error)")
                }
            }
        }

        @Test @MainActor func throwsForMainServiceFactoryError() throws {
            ServiceEnv.current.registerMain(String.self) {
                throw TestError.customError
            }

            do {
                try ServiceEnv.current.resolveMain(String.self)
                Issue.record("Expected error to be thrown")
            } catch {
                switch error {
                case .factoryFailed(let serviceType, let underlyingError):
                    #expect(serviceType == "String")
                    #expect(underlyingError is TestError)
                default:
                    Issue.record("Expected factoryFailed error, got \(error)")
                }
            }
        }
    }

    // MARK: - Successful Resolution

    @Suite("Successful Resolution")
    struct SuccessfulResolutionTests {
        init() async {
            await ServiceEnv.current.resetAll()
        }

        @Test func resolvesRegisteredService() throws {
            ServiceEnv.current.register(Int.self) { 42 }

            let value = try ServiceEnv.current.resolve(Int.self)
            #expect(value == 42)
        }

        @Test @MainActor func resolvesRegisteredMainService() throws {
            ServiceEnv.current.registerMain(String.self) { "Hello" }

            let value = try ServiceEnv.current.resolveMain(String.self)
            #expect(value == "Hello")
        }
    }

    // MARK: - Error Description

    @Suite("Error Description")
    struct ErrorDescriptionTests {
        @Test func formatsDescriptionsCorrectly() {
            let notRegistered = ServiceError.notRegistered(serviceType: "MyService")
            #expect(notRegistered.description.contains("MyService"))
            #expect(notRegistered.description.contains("not registered"))

            let circular = ServiceError.circularDependency(
                serviceType: "ServiceA",
                chain: ["ServiceA", "ServiceB", "ServiceA"]
            )
            #expect(circular.description.contains("Circular dependency"))
            #expect(circular.description.contains("ServiceA -> ServiceB -> ServiceA"))

            let maxDepth = ServiceError.maxDepthExceeded(
                depth: 100,
                chain: ["A", "B", "C"]
            )
            #expect(maxDepth.description.contains("100"))
            #expect(maxDepth.description.contains("A -> B -> C"))

            let factoryFailed = ServiceError.factoryFailed(
                serviceType: "MyService",
                underlyingError: TestError.customError
            )
            #expect(factoryFailed.description.contains("MyService"))
            #expect(factoryFailed.description.contains("Factory failed"))
        }
    }
}

// MARK: - Test Types

extension ServiceErrorTests {
    enum TestError: Error {
        case customError
    }

    struct CircularA: Sendable {
        init(b: CircularB) {}
    }

    struct CircularB: Sendable {
        init(c: CircularC) {}
    }

    struct CircularC: Sendable {
        init(a: CircularA) {}
    }

    struct DepthA: Sendable {
        let b: DepthB
    }

    struct DepthB: Sendable {
        let c: DepthC
    }

    struct DepthC: Sendable {
        let d: DepthD
    }

    struct DepthD: Sendable {}

    struct CircularDependencyAssembly: ServiceAssembly {
        func assemble(env: ServiceEnv) {
            env.register(CircularA.self) {
                let b = try env.resolve(CircularB.self)
                return CircularA(b: b)
            }

            env.register(CircularB.self) {
                let c = try env.resolve(CircularC.self)
                return CircularB(c: c)
            }

            env.register(CircularC.self) {
                let a = try env.resolve(CircularA.self)
                return CircularC(a: a)
            }
        }
    }

    struct DeepDependencyAssembly: ServiceAssembly {
        func assemble(env: ServiceEnv) {
            env.register(DepthA.self) {
                let b = try env.resolve(DepthB.self)
                return DepthA(b: b)
            }

            env.register(DepthB.self) {
                let c = try env.resolve(DepthC.self)
                return DepthB(c: c)
            }

            env.register(DepthC.self) {
                let d = try env.resolve(DepthD.self)
                return DepthC(d: d)
            }

            env.register(DepthD.self) {
                return DepthD()
            }
        }
    }
}
