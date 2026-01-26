//
//  Copyright © 2025 Service Contributors. All rights reserved.
//


import Foundation
import Testing
@testable import Service

#if os(macOS) || os(Linux) || os(Windows)
@Suite("Fatal Error Tests")
struct FatalErrorTests {
    @Test func testResolveUnregisteredType() async {
        await #expect(processExitsWith: .failure) {
            ServiceEnv.current.resolve(Int.self)
        }
    }

    @Test func testCircularDependencies() async {
        await #expect(processExitsWith: .failure) { @MainActor in
            ServiceEnv.current.assemble(FatalErrorTestAssembly())
            ServiceEnv.current.resolve(CircularDependencyA.self)
        }

        await #expect(processExitsWith: .failure) { @MainActor in
            ServiceEnv.current.assemble(FatalErrorTestAssembly())
            ServiceEnv.current.resolve(CircularDependencyB.self)
        }

        await #expect(processExitsWith: .failure) { @MainActor in
            ServiceEnv.current.assemble(FatalErrorTestAssembly())
            ServiceEnv.current.resolve(CircularDependencyC.self)
        }
    }

    @Test func testMaxResolutionDepth() async {
        await #expect(processExitsWith: .failure) { @MainActor in
            ServiceContext.$maxResolutionDepth.withValue(3) {
                ServiceEnv.current.assemble(FatalErrorTestAssembly())
                ServiceEnv.current.resolve(DepthLevelA.self)
            }
        }

        await #expect(processExitsWith: .failure) { @MainActor in
            ServiceContext.$maxResolutionDepth.withValue(3) {
                ServiceEnv.current.assemble(FatalErrorTestAssembly())
                ServiceEnv.current.resolve(DepthLevelB.self)
            }
        }

        await #expect(processExitsWith: .success) { @MainActor in
            ServiceContext.$maxResolutionDepth.withValue(3) {
                ServiceEnv.current.assemble(FatalErrorTestAssembly())
                ServiceEnv.current.resolve(DepthLevelC.self)
            }
        }

        await #expect(processExitsWith: .success) { @MainActor in
            ServiceContext.$maxResolutionDepth.withValue(3) {
                ServiceEnv.current.assemble(FatalErrorTestAssembly())
                ServiceEnv.current.resolve(DepthLevelD.self)
            }
        }

        await #expect(processExitsWith: .success) { @MainActor in
            ServiceContext.$maxResolutionDepth.withValue(3) {
                ServiceEnv.current.assemble(FatalErrorTestAssembly())
                ServiceEnv.current.resolve(DepthLevelE.self)
            }
        }
    }
}

extension FatalErrorTests {
    struct CircularDependencyA {
        init(b: CircularDependencyB) {}
    }

    struct CircularDependencyB {
        init(c: CircularDependencyC) {}
    }

    struct CircularDependencyC {
        init(a: CircularDependencyA) {}
    }

    struct DepthLevelA {
        let b: DepthLevelB
    }

    struct DepthLevelB {
        let c: DepthLevelC
    }

    struct DepthLevelC {
        let d: DepthLevelD
    }

    struct DepthLevelD {
        let e: DepthLevelE
    }

    struct DepthLevelE {}

    struct FatalErrorTestAssembly: ServiceAssembly {
        func assemble(env: ServiceEnv) {
            // circular dependency
            env.register(CircularDependencyA.self) {
                let b = env.resolve(CircularDependencyB.self)
                return CircularDependencyA(b: b)
            }

            env.register(CircularDependencyB.self) {
                let c = env.resolve(CircularDependencyC.self)
                return CircularDependencyB(c: c)
            }

            env.register(CircularDependencyC.self) {
                let a = env.resolve(CircularDependencyA.self)
                return CircularDependencyC(a: a)
            }

            // resolution depth
            env.register(DepthLevelA.self) {
                let b = env.resolve(DepthLevelB.self)
                return DepthLevelA(b: b)
            }

            env.register(DepthLevelB.self) {
                let c = env.resolve(DepthLevelC.self)
                return DepthLevelB(c: c)
            }

            env.register(DepthLevelC.self) {
                let d = env.resolve(DepthLevelD.self)
                return DepthLevelC(d: d)
            }

            env.register(DepthLevelD.self) {
                let e = env.resolve(DepthLevelE.self)
                return DepthLevelD(e: e)
            }

            env.register(DepthLevelE.self) {
                return DepthLevelE()
            }
        }
    }
}
#endif
