//
//  Copyright © 2026 Service Contributors. All rights reserved.
//

import Testing

@testable import Service

/// Tests of what belongs to a resolution chain: the nested resolutions on one thread, and nothing else.
@Suite("Resolution Chain Tests")
struct ResolutionChainTests {
    // MARK: Tasks that a factory starts

    // A task inherits the task-local values of the code that starts it. It must not inherit the chain:
    // when the task runs, the factory that started it has returned or runs on another thread.

    @Test func taskStartedInFactoryResolvesTheServiceLater() async throws {
        let env = ServiceEnv(name: "chain-task-own")
        let started = Locked<Task<Probe, any Error>?>()
        let (gate, open) = AsyncStream<Void>.makeStream()
        env.register(Probe.self) {
            let task = Task {
                for await _ in gate { break }
                return try env.resolve(Probe.self)
            }
            started.withLock { $0 = task }
            return Probe()
        }

        let created = try env.resolve(Probe.self)
        open.yield()

        let resolvedInTask = try await #require(started.value).value
        #expect(resolvedInTask === created)
    }

    @Test func taskStartedInDependencyFactoryResolvesTheOwnerLater() async throws {
        let env = ServiceEnv(name: "chain-task-owner")
        let started = Locked<Task<Owner, any Error>?>()
        let (gate, open) = AsyncStream<Void>.makeStream()
        env.register(Probe.self) {
            let task = Task {
                for await _ in gate { break }
                return try env.resolve(Owner.self)
            }
            started.withLock { $0 = task }
            return Probe()
        }
        env.register(Owner.self) {
            Owner(probe: try env.resolve(Probe.self))
        }

        let created = try env.resolve(Owner.self)
        open.yield()

        let resolvedInTask = try await #require(started.value).value
        #expect(resolvedInTask === created)
    }

    @Test @MainActor func taskStartedInMainFactoryResolvesTheServiceLater() async throws {
        let env = ServiceEnv(name: "chain-task-main")
        var started: Task<MainProbe, any Error>?
        env.registerMain(MainProbe.self) {
            started = Task { @MainActor in
                try env.resolveMain(MainProbe.self)
            }
            return MainProbe()
        }

        let created = try env.resolveMain(MainProbe.self)

        let resolvedInTask = try await #require(started).value
        #expect(resolvedInTask === created)
    }

    @Test func taskStartedInFactoryResolvesTransientServiceLater() async throws {
        let env = ServiceEnv(name: "chain-task-transient")
        let started = Locked<Task<Probe, any Error>?>()
        let (gate, open) = AsyncStream<Void>.makeStream()
        env.register(Probe.self, scope: .transient) {
            // Only the first instance starts a task.
            let isFirst = started.withLock { $0 == nil }
            if isFirst {
                let task = Task {
                    for await _ in gate { break }
                    return try env.resolve(Probe.self)
                }
                started.withLock { $0 = task }
            }
            return Probe()
        }

        let created = try env.resolve(Probe.self)
        open.yield()

        let resolvedInTask = try await #require(started.value).value
        #expect(resolvedInTask !== created)
    }

    @Test func taskStartedInFactoryGetsItsOwnGraphInstances() async throws {
        let env = ServiceEnv(name: "chain-task-graph")
        let started = Locked<Task<[Probe], any Error>?>()
        let (gate, open) = AsyncStream<Void>.makeStream()
        env.register(Probe.self, scope: .graph) { Probe() }
        env.register(Owner.self) {
            let task = Task {
                for await _ in gate { break }
                return [try env.resolve(Probe.self), try env.resolve(Probe.self)]
            }
            started.withLock { $0 = task }
            return Owner(probe: try env.resolve(Probe.self))
        }

        let owner = try env.resolve(Owner.self)
        open.yield()

        // Two top-level resolutions in the task are two chains, and neither is the chain of `owner`.
        let resolvedInTask = try await #require(started.value).value
        #expect(resolvedInTask[0] !== resolvedInTask[1])
        #expect(resolvedInTask[0] !== owner.probe)
        #expect(resolvedInTask[1] !== owner.probe)
    }

    // MARK: Another task on the thread of a running factory

    // `Task.immediateDetached` runs its operation on the current thread until the first suspension,
    // and it inherits no task-local values. That is what a nested run loop inside a factory does when
    // it runs another task. The resolution cannot wait for the factory below it on the same thread.

    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    @Test(arguments: [ServiceScope.singleton, .custom("chain")])
    func throwsWhenAnotherTaskOnTheSameThreadResolvesServiceWhileItsFactoryRuns(scope: ServiceScope) async throws {
        let env = ServiceEnv(name: "chain-same-thread")
        let factoryRuns = Locked<Int>(0)
        let started = Locked<Task<ServiceError?, Never>?>()
        env.register(Probe.self, scope: scope) {
            factoryRuns.withLock { $0 += 1 }
            let task = Task.immediateDetached { () -> ServiceError? in
                do throws(ServiceError) {
                    try env.resolve(Probe.self)
                    return nil
                } catch {
                    return error
                }
            }
            started.withLock { $0 = task }
            return Probe()
        }

        let created = try env.resolve(Probe.self)

        let errorInOtherTask = try await #require(started.value).value
        #expect(errorInOtherTask?.isCircularDependency == true)
        #expect(try env.resolve(Probe.self) === created)
        #expect(factoryRuns.value == 1)
    }

    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    @Test(arguments: [ServiceScope.singleton, .custom("chain")])
    @MainActor func throwsWhenAnotherTaskOnTheMainThreadResolvesMainServiceWhileItsFactoryRuns(
        scope: ServiceScope
    ) async throws {
        let env = ServiceEnv(name: "chain-same-thread-main")
        var factoryRuns = 0
        var started: Task<ServiceError?, Never>?
        env.registerMain(MainProbe.self, scope: scope) {
            factoryRuns += 1
            started = Task.immediateDetached { @MainActor () -> ServiceError? in
                do throws(ServiceError) {
                    try env.resolveMain(MainProbe.self)
                    return nil
                } catch {
                    return error
                }
            }
            return MainProbe()
        }

        let created = try env.resolveMain(MainProbe.self)

        let errorInOtherTask = try await #require(started).value
        #expect(errorInOtherTask?.isCircularDependency == true)
        #expect(try env.resolveMain(MainProbe.self) === created)
        #expect(factoryRuns == 1)
    }

    // A transient or graph-scoped registration has no lock, so the other task can create its own
    // instance. Its resolution is a chain of its own.

    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    @Test func anotherTaskOnTheSameThreadResolvesTransientServiceWhileItsFactoryRuns() async throws {
        let env = ServiceEnv(name: "chain-same-thread-transient")
        let factoryRuns = Locked<Int>(0)
        let started = Locked<Task<Probe, any Error>?>()
        env.register(Probe.self, scope: .transient) {
            // Only the first factory run starts the other task. The task runs here, before the
            // factory returns, so it is started outside the lock.
            let isFirstRun = factoryRuns.withLock { runs in
                runs += 1
                return runs == 1
            }
            if isFirstRun {
                let task = Task.immediateDetached { try env.resolve(Probe.self) }
                started.withLock { $0 = task }
            }
            return Probe()
        }

        let created = try env.resolve(Probe.self)

        let createdInOtherTask = try await #require(started.value).value
        #expect(createdInOtherTask !== created)
    }

    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    @Test func anotherTaskOnTheSameThreadGetsItsOwnGraphInstance() async throws {
        let env = ServiceEnv(name: "chain-same-thread-graph")
        let started = Locked<Task<Probe, any Error>?>()
        env.register(Probe.self, scope: .graph) { Probe() }
        env.register(Owner.self) {
            let probe = try env.resolve(Probe.self)
            let task = Task.immediateDetached { try env.resolve(Probe.self) }
            started.withLock { $0 = task }
            return Owner(probe: probe)
        }

        let owner = try env.resolve(Owner.self)

        let resolvedInOtherTask = try await #require(started.value).value
        #expect(resolvedInOtherTask !== owner.probe)
    }

    // MARK: The end of a chain

    @Test func graphInstanceResolvesInDeinitWhenItsChainEnds() throws {
        let env = ServiceEnv(name: "chain-end-deinit")
        let resolvedInDeinit = Locked<[String]>([])
        env.register(Int.self, scope: .transient) { 1 }
        env.register(ResolvesOnDeinit.self, scope: .graph) {
            ResolvesOnDeinit(env: env, results: resolvedInDeinit)
        }
        // The graph cache of the chain holds the only reference to the instance.
        env.register(String.self, scope: .transient) {
            _ = try env.resolve(ResolvesOnDeinit.self)
            return "owner"
        }

        _ = try env.resolve(String.self)

        #expect(resolvedInDeinit.value == ["1"])
        // The thread runs no chain now: the next resolution starts with an empty graph cache.
        _ = try env.resolve(String.self)
        #expect(resolvedInDeinit.value == ["1", "1"])
    }

    // MARK: More than one environment

    @Test func resolvesTheSameTypeFromAnotherEnvironmentInsideFactory() throws {
        let base = ServiceEnv(name: "chain-env-base")
        let overriding = ServiceEnv(name: "chain-env-overriding")
        base.register(String.self) { "base" }
        overriding.register(String.self) { "overriding " + (try base.resolve(String.self)) }

        #expect(try overriding.resolve(String.self) == "overriding base")
        // The instance of `base` is cached now. The result is the same.
        overriding.resetCaches()
        #expect(try overriding.resolve(String.self) == "overriding base")
    }

    @Test func detectsCycleThatCrossesEnvironments() {
        let first = ServiceEnv(name: "chain-env-cycle-first")
        let second = ServiceEnv(name: "chain-env-cycle-second")
        first.register(String.self) { try second.resolve(String.self) }
        second.register(String.self) { try first.resolve(String.self) }

        let error = #expect(throws: ServiceError.self) { try first.resolve(String.self) }
        #expect(error?.isCircularDependency == true)
    }
}

// MARK: - Fixtures

extension ResolutionChainTests {
    final class Probe: Sendable {}

    final class Owner: Sendable {
        let probe: Probe
        init(probe: Probe) { self.probe = probe }
    }

    @MainActor
    final class MainProbe {}

    /// Resolves `Int` from its environment when it is released, and records the value or the error.
    final class ResolvesOnDeinit: Sendable {
        private let env: ServiceEnv
        private let results: Locked<[String]>

        init(env: ServiceEnv, results: Locked<[String]>) {
            self.env = env
            self.results = results
        }

        deinit {
            let result: String
            do {
                result = String(try env.resolve(Int.self))
            } catch {
                result = String(describing: error)
            }
            results.withLock { $0.append(result) }
        }
    }
}
