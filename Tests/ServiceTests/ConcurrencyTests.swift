//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

import Foundation
import Testing

@testable import Service

// MARK: - Concurrency Tests

@Test("ServiceEnv is thread-safe for concurrent access")
func testConcurrentServiceAccess() async throws {
    let testEnv = ServiceEnv(name: "concurrency-test")
    try await ServiceEnv.$current.withValue(testEnv) {
        // Register a service
        ServiceEnv.current.register(String.self) {
            UUID().uuidString
        }

        // Create multiple tasks that concurrently resolve the service
        await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    try ServiceEnv.current.resolve(String.self)
                }
            }

            // Collect all resolved values
            var resolvedValues: [String] = []
            do {
                for try await value in group {
                    resolvedValues.append(value)
                }
            } catch {
                Issue.record("Unexpected error: \(error)")
            }

            // All values should be the same (singleton behavior)
            if let firstValue = resolvedValues.first {
                for value in resolvedValues {
                    #expect(value == firstValue)
                }
            }
        }
    }
}

@Test("ServiceEnv handles concurrent registration and resolution")
func testConcurrentRegistrationAndResolution() async throws {
    let testEnv = ServiceEnv(name: "concurrent-registration-test")
    try await ServiceEnv.$current.withValue(testEnv) {
        // Concurrently register different services
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    ServiceEnv.current.register(Int.self) {
                        i
                    }
                }
            }

            // Wait for all registrations to complete
            for await _ in group {}
        }

        // The last registration should win (but we can't predict which)
        // Just verify that resolution doesn't crash
        let resolved = try ServiceEnv.current.resolve(Int.self)
        #expect(resolved >= 0 && resolved < 10)
    }
}

@Test("ServiceEnv maintains isolation across concurrent tasks")
func testConcurrentEnvironmentIsolation() async throws {
    let env1 = ServiceEnv(name: "concurrent-env1")
    let env2 = ServiceEnv(name: "concurrent-env2")

    // Register different services in different environments concurrently
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

    // Verify isolation
    try ServiceEnv.$current.withValue(env1) {
        let service1 = try ServiceEnv.current.resolve(String.self)
        #expect(service1 == "env1-service")
    }

    try ServiceEnv.$current.withValue(env2) {
        let service2 = try ServiceEnv.current.resolve(String.self)
        #expect(service2 == "env2-service")
    }
}
