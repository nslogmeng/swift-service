//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

import Foundation
import Testing

@testable import Service

#if os(macOS) || os(Linux) || os(Windows)
    @Suite("Fatal Error Tests")
    struct FatalErrorTests {
        @Test func testPropertyWrapperUnregisteredType() async {
            await #expect(processExitsWith: .failure) {
                struct TestStruct: Sendable {
                    @Service var value: Int
                }
                _ = TestStruct()
            }
        }

        @Test func testPropertyWrapperCircularDependencies() async {
            await #expect(processExitsWith: .failure) { @MainActor in
                ServiceEnv.current.assemble(FatalErrorTestAssembly())

                struct TestStruct: Sendable {
                    @Service var a: CircularDependencyA
                }
                _ = TestStruct()
            }
        }

        @Test func testPropertyWrapperMaxResolutionDepth() async {
            await #expect(processExitsWith: .failure) { @MainActor in
                ServiceEnv.$maxResolutionDepth.withValue(3) {
                    ServiceEnv.current.assemble(FatalErrorTestAssembly())

                    struct TestStruct: Sendable {
                        @Service var a: DepthLevelA
                    }
                    _ = TestStruct()
                }
            }
        }
    }

    extension FatalErrorTests {
        struct CircularDependencyA: Sendable {
            init(b: CircularDependencyB) {}
        }

        struct CircularDependencyB: Sendable {
            init(c: CircularDependencyC) {}
        }

        struct CircularDependencyC: Sendable {
            init(a: CircularDependencyA) {}
        }

        struct DepthLevelA: Sendable {
            let b: DepthLevelB
        }

        struct DepthLevelB: Sendable {
            let c: DepthLevelC
        }

        struct DepthLevelC: Sendable {
            let d: DepthLevelD
        }

        struct DepthLevelD: Sendable {
            let e: DepthLevelE
        }

        struct DepthLevelE: Sendable {}

        struct FatalErrorTestAssembly: ServiceAssembly {
            func assemble(env: ServiceEnv) {
                // circular dependency
                env.register(CircularDependencyA.self) {
                    let b = try env.resolve(CircularDependencyB.self)
                    return CircularDependencyA(b: b)
                }

                env.register(CircularDependencyB.self) {
                    let c = try env.resolve(CircularDependencyC.self)
                    return CircularDependencyB(c: c)
                }

                env.register(CircularDependencyC.self) {
                    let a = try env.resolve(CircularDependencyA.self)
                    return CircularDependencyC(a: a)
                }

                // resolution depth
                env.register(DepthLevelA.self) {
                    let b = try env.resolve(DepthLevelB.self)
                    return DepthLevelA(b: b)
                }

                env.register(DepthLevelB.self) {
                    let c = try env.resolve(DepthLevelC.self)
                    return DepthLevelB(c: c)
                }

                env.register(DepthLevelC.self) {
                    let d = try env.resolve(DepthLevelD.self)
                    return DepthLevelC(d: d)
                }

                env.register(DepthLevelD.self) {
                    let e = try env.resolve(DepthLevelE.self)
                    return DepthLevelD(e: e)
                }

                env.register(DepthLevelE.self) {
                    return DepthLevelE()
                }
            }
        }
    }
#endif
