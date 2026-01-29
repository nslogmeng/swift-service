//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

import Foundation
import Testing

@testable import Service

@Suite("Concurrency Tests")
struct ConcurrencyTests {
    @Test func maintainsThreadSafetyOnConcurrentAccess() async throws {
        let testEnv = ServiceEnv(name: "concurrency-test")
        await ServiceEnv.$current.withValue(testEnv) {
            ServiceEnv.current.register(String.self) {
                UUID().uuidString
            }

            await withThrowingTaskGroup(of: String.self) { group in
                for _ in 0..<100 {
                    group.addTask {
                        try ServiceEnv.current.resolve(String.self)
                    }
                }

                var resolvedValues: [String] = []
                do {
                    for try await value in group {
                        resolvedValues.append(value)
                    }
                } catch {
                    Issue.record("Unexpected error: \(error)")
                }

                if let firstValue = resolvedValues.first {
                    for value in resolvedValues {
                        #expect(value == firstValue)
                    }
                }
            }
        }
    }

    @Test func handlesConcurrentRegistrationAndResolution() async throws {
        let testEnv = ServiceEnv(name: "concurrent-registration-test")
        try await ServiceEnv.$current.withValue(testEnv) {
            await withTaskGroup(of: Void.self) { group in
                for i in 0..<10 {
                    group.addTask {
                        ServiceEnv.current.register(Int.self) {
                            i
                        }
                    }
                }

                for await _ in group {}
            }

            let resolved = try ServiceEnv.current.resolve(Int.self)
            #expect(resolved >= 0 && resolved < 10)
        }
    }

    @Test func maintainsIsolationAcrossConcurrentTasks() async throws {
        let env1 = ServiceEnv(name: "concurrent-env1")
        let env2 = ServiceEnv(name: "concurrent-env2")

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                ServiceEnv.$current.withValue(env1) {
                    ServiceEnv.current.register(String.self) {
                        "env1-service"
                    }
                }
            }

            group.addTask {
                ServiceEnv.$current.withValue(env2) {
                    ServiceEnv.current.register(String.self) {
                        "env2-service"
                    }
                }
            }

            for await _ in group {}
        }

        try ServiceEnv.$current.withValue(env1) {
            let service1 = try ServiceEnv.current.resolve(String.self)
            #expect(service1 == "env1-service")
        }

        try ServiceEnv.$current.withValue(env2) {
            let service2 = try ServiceEnv.current.resolve(String.self)
            #expect(service2 == "env2-service")
        }
    }
}
