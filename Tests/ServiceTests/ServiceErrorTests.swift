//
//  Created by Meng on 2025.
//  Copyright © 2025 Service Contributors. All rights reserved.
//

import Testing

@testable import Service

@Suite("Service Error Tests", .serialized)
struct ServiceErrorTests {
    init() async {
        await ServiceEnv.current.resetAll()
    }

    // MARK: - NotRegistered Error Tests

    @Test("resolve throws notRegistered for unregistered service")
    func testResolveUnregisteredThrows() throws {
        #expect(throws: ServiceError.self) {
            try ServiceEnv.current.resolve(Int.self)
        }
    }

    @Test("resolveMain throws notRegistered for unregistered service")
    @MainActor
    func testResolveMainUnregisteredThrows() throws {
        #expect(throws: ServiceError.self) {
            try ServiceEnv.current.resolveMain(String.self)
        }
    }

    @Test("notRegistered error contains correct service type")
    func testNotRegisteredErrorMessage() throws {
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

    // MARK: - Circular Dependency Error Tests

    @Test("resolve throws circularDependency for circular dependencies")
    @MainActor
    func testCircularDependencyThrows() throws {
        ServiceEnv.current.assemble(CircularDependencyAssembly())

        #expect(throws: ServiceError.self) {
            try ServiceEnv.current.resolve(CircularA.self)
        }
    }

    @Test("circularDependency error contains correct chain")
    @MainActor
    func testCircularDependencyErrorMessage() throws {
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

    // MARK: - Max Depth Exceeded Error Tests

    @Test("resolve throws maxDepthExceeded when depth limit is exceeded")
    @MainActor
    func testMaxDepthExceededThrows() throws {
        ServiceEnv.current.assemble(DeepDependencyAssembly())

        ServiceContext.$maxResolutionDepth.withValue(2) {
            #expect(throws: ServiceError.self) {
                try ServiceEnv.current.resolve(DepthA.self)
            }
        }
    }

    @Test("maxDepthExceeded error contains correct depth")
    @MainActor
    func testMaxDepthExceededErrorMessage() throws {
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

    // MARK: - Successful Resolution Tests

    @Test("resolve succeeds for registered service")
    func testResolveSucceeds() throws {
        ServiceEnv.current.register(Int.self) { 42 }

        let value = try ServiceEnv.current.resolve(Int.self)
        #expect(value == 42)
    }

    @Test("resolveMain succeeds for registered MainActor service")
    @MainActor
    func testResolveMainSucceeds() throws {
        ServiceEnv.current.registerMain(String.self) { "Hello" }

        let value = try ServiceEnv.current.resolveMain(String.self)
        #expect(value == "Hello")
    }

    // MARK: - Factory Failed Error Tests

    @Test("resolve throws factoryFailed when factory throws non-ServiceError")
    func testFactoryFailedThrows() throws {
        ServiceEnv.current.register(String.self) {
            throw TestError.customError
        }

        #expect(throws: ServiceError.self) {
            try ServiceEnv.current.resolve(String.self)
        }
    }

    @Test("factoryFailed error contains correct service type and underlying error")
    func testFactoryFailedErrorMessage() throws {
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

    @Test("factory can throw ServiceError and it propagates directly")
    func testFactoryThrowsServiceError() throws {
        ServiceEnv.current.register(String.self) {
            throw ServiceError.notRegistered(serviceType: "CustomDependency")
        }

        do {
            try ServiceEnv.current.resolve(String.self)
            Issue.record("Expected error to be thrown")
        } catch {
            switch error {
            case .notRegistered(let serviceType):
                // ServiceError is propagated directly, not wrapped in factoryFailed
                #expect(serviceType == "CustomDependency")
            default:
                Issue.record("Expected notRegistered error, got \(error)")
            }
        }
    }

    @Test("resolveMain throws factoryFailed when factory throws non-ServiceError")
    @MainActor
    func testResolveMainFactoryFailedThrows() throws {
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

    // MARK: - Error Description Tests

    @Test("ServiceError.description is correctly formatted")
    func testErrorDescriptions() {
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

// MARK: - Test Errors

private enum TestError: Error {
    case customError
}

// MARK: - Test Types

private struct CircularA: Sendable {
    init(b: CircularB) {}
}

private struct CircularB: Sendable {
    init(c: CircularC) {}
}

private struct CircularC: Sendable {
    init(a: CircularA) {}
}

private struct DepthA: Sendable {
    let b: DepthB
}

private struct DepthB: Sendable {
    let c: DepthC
}

private struct DepthC: Sendable {
    let d: DepthD
}

private struct DepthD: Sendable {}

// MARK: - Test Assemblies

private struct CircularDependencyAssembly: ServiceAssembly {
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

private struct DeepDependencyAssembly: ServiceAssembly {
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
