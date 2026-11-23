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

    @Test func keepsEveryRegistrationMadeByConcurrentThreads() {
        // Every thread registers its own family of distinct types, so no registration replaces another one.
        let seeds: [any ServiceFamily.Type] = [
            Nested<Int>.self, Nested<String>.self, Nested<Bool>.self, Nested<Double>.self,
            Nested<UInt8>.self, Nested<Int16>.self, Nested<Float>.self, Nested<Character>.self,
        ]
        let typesPerThread = 20

        for _ in 0..<20 {
            let env = ServiceEnv(name: "concurrent-distinct-registration-test")
            DispatchQueue.concurrentPerform(iterations: seeds.count) { index in
                seeds[index].registerFamily(count: typesPerThread, in: env)
            }

            for seed in seeds {
                #expect(throws: Never.self) {
                    try seed.resolveFamily(count: typesPerThread, in: env)
                }
            }
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

// MARK: - Singleton Creation

extension ConcurrencyTests {
    /// Resolutions that can wait for another thread run on their own threads through `ThreadResult`, and
    /// the suite has a time limit. A regression that leaves such a resolver blocked then fails the test
    /// instead of stalling the run.
    @Suite("Singleton Creation", .timeLimit(.minutes(1)))
    struct SingletonCreationTests {
        // MARK: Factory runs once

        @Test(arguments: [ServiceScope.singleton, .custom("once")])
        func runsFactoryOnceForConcurrentFirstResolutions(scope: ServiceScope) async throws {
            // A resolver that reaches the cache after the first factory run has finished cannot expose a
            // second run. Repeating the race keeps the test sensitive without relying on timing.
            let rounds = 10
            let resolverCount = 8
            var factoryRunsPerRound: [Int] = []
            var instancesPerRound: [Int] = []

            for _ in 0..<rounds {
                let env = ServiceEnv(name: "once-concurrent")
                let allResolversStarted = Latch(count: resolverCount)
                let factoryRuns = Locked<Int>(0)

                env.register(Probe.self, scope: scope) {
                    let run = factoryRuns.increment()
                    // Keeps the factory running until every resolver is in flight.
                    allResolversStarted.wait()
                    return Probe(id: run)
                }

                let resolvers = (0..<resolverCount).map { _ in
                    ThreadResult {
                        allResolversStarted.countDown()
                        return try env.resolve(Probe.self)
                    }
                }
                var instances: Set<ObjectIdentifier> = []
                for resolver in resolvers {
                    instances.insert(ObjectIdentifier(try await resolver.value))
                }

                factoryRunsPerRound.append(factoryRuns.value)
                instancesPerRound.append(instances.count)
            }

            #expect(factoryRunsPerRound == Array(repeating: 1, count: rounds))
            #expect(instancesPerRound == Array(repeating: 1, count: rounds))
        }

        @Test func resolvesOtherKeysWhileFactoryIsRunning() async throws {
            let env = ServiceEnv(name: "once-independent-keys")
            let slowFactoryEntered = Latch()
            let releaseSlowFactory = Latch()

            env.register(SlowProbe.self) {
                slowFactoryEntered.countDown()
                releaseSlowFactory.wait()
                return SlowProbe()
            }
            env.register(Probe.self) { Probe(id: 1) }

            let slow = ThreadResult { try env.resolve(SlowProbe.self) }
            let other = ThreadResult {
                slowFactoryEntered.wait()
                return try env.resolve(Probe.self)
            }

            // The slow factory stays blocked until the latch opens below,
            // so this returns only if resolving `Probe` does not wait for it.
            _ = try await other.value
            releaseSlowFactory.countDown()
            _ = try await slow.value
        }

        // MARK: Failure and reset

        @Test func retriesFactoryAfterItThrows() throws {
            let env = ServiceEnv(name: "once-retry")
            let factoryRuns = Locked<Int>(0)

            env.register(Probe.self) {
                let run = factoryRuns.increment()
                if run == 1 {
                    throw FactoryError.firstRunFails
                }
                return Probe(id: run)
            }

            #expect(throws: ServiceError.self) { try env.resolve(Probe.self) }

            let retried = try env.resolve(Probe.self)
            let cached = try env.resolve(Probe.self)
            #expect(retried.id == 2)
            #expect(cached === retried)
            #expect(factoryRuns.value == 2)
        }

        @Test(arguments: ResetOperation.allCases)
        func resetDuringCreationKeepsInFlightInstanceOutOfCache(operation: ResetOperation) async throws {
            let env = ServiceEnv(name: "once-reset")
            let factoryRuns = Locked<Int>(0)
            let firstFactoryEntered = Latch()
            let releaseFirstFactory = Latch()
            let register: @Sendable () -> Void = {
                env.register(Probe.self) {
                    let run = factoryRuns.increment()
                    if run == 1 {
                        firstFactoryEntered.countDown()
                        releaseFirstFactory.wait()
                    }
                    return Probe(id: run)
                }
            }
            register()

            let inFlight = ThreadResult { try env.resolve(Probe.self) }
            let afterReset = ThreadResult {
                firstFactoryEntered.wait()
                operation.apply(to: env)
                if operation == .all {
                    register()
                }
                return try env.resolve(Probe.self)
            }

            // The first factory stays blocked until the latch opens below,
            // so this returns only if the reset and the next resolution do not wait for it.
            let fresh = try await afterReset.value
            releaseFirstFactory.countDown()
            let original = try await inFlight.value

            #expect(original.id == 1)
            #expect(fresh.id == 2)
            #expect(try env.resolve(Probe.self) === fresh)
            #expect(factoryRuns.value == 2)
        }

        // On the main actor, a reset can run during a factory only from inside the factory.
        @Test(arguments: ResetOperation.allCases)
        @MainActor func resetInsideMainFactoryKeepsInFlightInstanceOutOfCache(operation: ResetOperation) throws {
            let env = ServiceEnv(name: "once-reset-main")
            var factoryRuns = 0
            func register() {
                env.registerMain(MainProbe.self) {
                    factoryRuns += 1
                    if factoryRuns == 1 {
                        operation.apply(to: env)
                        if operation == .all {
                            register()
                        }
                    }
                    return MainProbe()
                }
            }
            register()

            let original = try env.resolveMain(MainProbe.self)
            let fresh = try env.resolveMain(MainProbe.self)

            #expect(fresh !== original)
            #expect(try env.resolveMain(MainProbe.self) === fresh)
            #expect(factoryRuns == 2)
        }

        // MARK: Re-entrant resolution

        // A factory that reaches its own key again must fail with `circularDependency` before the storage
        // is reached. The lock that guards a key's creation is not recursive, so locking it again on the
        // same thread crashes the process.

        @Test(arguments: [ServiceScope.singleton, .custom("reentrant")])
        func throwsWhenFactoryResolvesItsOwnKey(scope: ServiceScope) {
            let env = ServiceEnv(name: "once-reentrant-direct")
            env.register(Probe.self, scope: scope) {
                try env.resolve(Probe.self)
            }

            let error = #expect(throws: ServiceError.self) { try env.resolve(Probe.self) }
            #expect(error?.isCircularDependency == true)
        }

        @Test(arguments: [ServiceScope.singleton, .custom("reentrant")])
        func throwsWhenFactoryResolvesItsOwnKeyThroughDependency(scope: ServiceScope) {
            let env = ServiceEnv(name: "once-reentrant-indirect")
            env.register(Probe.self, scope: scope) {
                try env.resolve(ProbeOwner.self).probe
            }
            env.register(ProbeOwner.self, scope: scope) {
                ProbeOwner(probe: try env.resolve(Probe.self))
            }

            let error = #expect(throws: ServiceError.self) { try env.resolve(Probe.self) }
            #expect(error?.isCircularDependency == true)
        }

        @Test(arguments: [ServiceScope.singleton, .custom("reentrant")])
        @MainActor func throwsWhenMainFactoryResolvesItsOwnKey(scope: ServiceScope) {
            let env = ServiceEnv(name: "once-reentrant-main-direct")
            env.registerMain(MainProbe.self, scope: scope) {
                try env.resolveMain(MainProbe.self)
            }

            let error = #expect(throws: ServiceError.self) { try env.resolveMain(MainProbe.self) }
            #expect(error?.isCircularDependency == true)
        }

        @Test(arguments: [ServiceScope.singleton, .custom("reentrant")])
        @MainActor func throwsWhenMainFactoryResolvesItsOwnKeyThroughDependency(scope: ServiceScope) {
            let env = ServiceEnv(name: "once-reentrant-main-indirect")
            env.registerMain(MainProbe.self, scope: scope) {
                try env.resolveMain(MainProbeOwner.self).probe
            }
            env.registerMain(MainProbeOwner.self, scope: scope) {
                MainProbeOwner(probe: try env.resolveMain(MainProbe.self))
            }

            let error = #expect(throws: ServiceError.self) { try env.resolveMain(MainProbe.self) }
            #expect(error?.isCircularDependency == true)
        }

        @Test @MainActor func retriesMainFactoryAfterItThrows() throws {
            let env = ServiceEnv(name: "once-retry-main")
            var factoryRuns = 0
            env.registerMain(MainProbe.self) {
                factoryRuns += 1
                if factoryRuns == 1 {
                    throw FactoryError.firstRunFails
                }
                return MainProbe()
            }

            #expect(throws: ServiceError.self) { try env.resolveMain(MainProbe.self) }

            let retried = try env.resolveMain(MainProbe.self)
            #expect(try env.resolveMain(MainProbe.self) === retried)
            #expect(factoryRuns == 2)
        }
    }
}

// MARK: - Instance Release

extension ConcurrencyTests {
    /// The `deinit` of a cached instance can call back into its environment. If the storage released
    /// the instance inside one of its locks, that call would lock again on the same thread and crash
    /// the process.
    @Suite("Instance Release")
    struct InstanceReleaseTests {
        @Test(arguments: SingletonCreationTests.ResetOperation.allCases)
        func releasesCachedInstanceOutsideLocksOnReset(operation: SingletonCreationTests.ResetOperation) throws {
            let env = ServiceEnv(name: "release-on-reset")
            let deinitCount = Locked<Int>(0)
            env.register(ReentrantOnDeinit.self) {
                ReentrantOnDeinit(env: env, deinitCount: deinitCount)
            }
            try env.resolve(ReentrantOnDeinit.self)

            operation.apply(to: env)

            #expect(deinitCount.value == 1)
        }

        @Test func releasesCachedInstanceOutsideLocksOnRegistrationWithAnotherScope() throws {
            let env = ServiceEnv(name: "release-on-scope-change")
            let deinitCount = Locked<Int>(0)
            env.register(ReentrantOnDeinit.self) {
                ReentrantOnDeinit(env: env, deinitCount: deinitCount)
            }
            try env.resolve(ReentrantOnDeinit.self)

            env.register(ReentrantOnDeinit.self, scope: .custom("other")) {
                ReentrantOnDeinit(env: env, deinitCount: deinitCount)
            }

            #expect(deinitCount.value == 1)
        }
    }
}

extension ConcurrencyTests.InstanceReleaseTests {
    /// A service whose `deinit` registers a service in its environment.
    final class ReentrantOnDeinit: Sendable {
        private let env: ServiceEnv
        private let deinitCount: Locked<Int>

        init(env: ServiceEnv, deinitCount: Locked<Int>) {
            self.env = env
            self.deinitCount = deinitCount
        }

        deinit {
            env.register(Int.self) { 0 }
            _ = deinitCount.increment()
        }
    }
}

// MARK: - Singleton Creation Test Types

extension ConcurrencyTests.SingletonCreationTests {
    final class Probe: Sendable {
        /// The factory run that created this instance.
        let id: Int

        init(id: Int) {
            self.id = id
        }
    }

    final class SlowProbe: Sendable {}

    struct ProbeOwner: Sendable {
        let probe: Probe
    }

    @MainActor
    final class MainProbe {}

    @MainActor
    final class MainProbeOwner {
        let probe: MainProbe

        init(probe: MainProbe) {
            self.probe = probe
        }
    }

    enum FactoryError: Error {
        case firstRunFails
    }

    enum ResetOperation: CaseIterable, Sendable {
        case caches
        case scope
        case all

        func apply(to env: ServiceEnv) {
            switch self {
            case .caches: env.resetCaches()
            case .scope: env.resetScope(.singleton)
            case .all: env.resetAll()
            }
        }
    }
}

// MARK: - Distinct Service Types

/// A type that names a family of distinct service types: `Nested<Self>`, `Nested<Nested<Self>>`, and so on.
private protocol ServiceFamily: Sendable {}

/// A service type that is distinct for every `T`.
private struct Nested<T>: ServiceFamily {}

extension ServiceFamily {
    /// Registers the first `count` service types of the family.
    fileprivate static func registerFamily(count: Int, in env: ServiceEnv) {
        env.register(Nested<Self>.self) { Nested<Self>() }
        if count > 1 {
            Nested<Self>.registerFamily(count: count - 1, in: env)
        }
    }

    /// Resolves the first `count` service types of the family.
    fileprivate static func resolveFamily(count: Int, in env: ServiceEnv) throws(ServiceError) {
        try env.resolve(Nested<Self>.self)
        if count > 1 {
            try Nested<Self>.resolveFamily(count: count - 1, in: env)
        }
    }
}

// MARK: - Blocking Test Support

/// A countdown latch for synchronous code. `wait()` blocks until `countDown()` has been called `count` times,
/// and returns immediately after that.
private final class Latch: @unchecked Sendable {
    private let condition = NSCondition()

    /// Guarded by `condition`.
    private var remaining: Int

    init(count: Int = 1) {
        remaining = count
    }

    func countDown() {
        condition.lock()
        defer { condition.unlock() }
        remaining -= 1
        if remaining == 0 {
            condition.broadcast()
        }
    }

    func wait() {
        condition.lock()
        defer { condition.unlock() }
        while remaining > 0 {
            condition.wait()
        }
    }
}

/// The eventual result of synchronous work that runs on its own thread.
///
/// Resolving a service can block the calling thread, so these tests keep it off the cooperative thread pool.
/// `value` stops waiting when the awaiting task is cancelled, so a time limit ends a test whose thread
/// stays blocked.
private struct ThreadResult<Value: Sendable>: Sendable {
    private let stream: AsyncThrowingStream<Value, any Error>

    /// Starts `body` on a new thread.
    init(_ body: @escaping @Sendable () throws -> Value) {
        stream = AsyncThrowingStream { continuation in
            Thread.detachNewThread {
                continuation.yield(with: Result { try body() })
                continuation.finish()
            }
        }
    }

    /// The value returned by the thread. Await it at most once.
    ///
    /// - Throws: The error thrown by the thread, or `CancellationError` if the task is cancelled first.
    var value: Value {
        get async throws {
            for try await value in stream {
                return value
            }
            throw CancellationError()
        }
    }
}

extension Locked<Int> {
    /// Adds one and returns the new value.
    fileprivate func increment() -> Int {
        withLock { value in
            value += 1
            return value
        }
    }
}

extension ServiceError {
    fileprivate var isCircularDependency: Bool {
        if case .circularDependency = self {
            return true
        }
        return false
    }
}
