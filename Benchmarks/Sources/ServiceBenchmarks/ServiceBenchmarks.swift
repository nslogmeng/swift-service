//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

import Service

/// Usage: `ServiceBenchmarks [filter]`
///
/// Runs the benchmarks whose name contains `filter`, or all of them without an argument.
@main
enum ServiceBenchmarks {
    @MainActor
    static func main() throws {
        let runner = BenchmarkRunner(filter: CommandLine.arguments.dropFirst().first)
        let env = makeEnvironment()
        runner.printHeader()
        try runSendableBenchmarks(with: runner, in: env)
        try runMainActorBenchmarks(with: runner, in: env)
        runControlBenchmark(with: runner)
    }
}

// The benchmarks for the Sendable APIs and the control are nonisolated functions. A closure formed in
// main-actor-isolated code checks its executor each time it runs, which would add cost to every operation
// that takes a closure.

private func runSendableBenchmarks(with runner: BenchmarkRunner, in env: ServiceEnv) throws {
    try runner.measure("resolve singleton (concrete)") {
        for _ in 0..<operationsPerSample { _ = try env.resolve(Config.self) }
    }

    try runner.measure("resolve singleton (existential)") {
        for _ in 0..<operationsPerSample { _ = try env.resolve((any Greeter).self) }
    }

    try runner.measure("resolve transient") {
        for _ in 0..<operationsPerSample { _ = try env.resolve(TransientService.self) }
    }

    let graphEnv = makeGraphEnvironment()
    try runner.measure("resolve graph") {
        for _ in 0..<operationsPerSample { _ = try graphEnv.resolve(GraphService.self) }
    }

    try runner.measure("resolve custom scope") {
        for _ in 0..<operationsPerSample { _ = try env.resolve(CustomService.self) }
    }

    try runner.measure("resolve nested (transient + 2 hits)") {
        for _ in 0..<operationsPerSample { _ = try env.resolve(Top.self) }
    }

    let serviceHolder = ServiceEnv.$current.withValue(env) { ServiceHolder() }
    runner.measure("@Service cached") {
        for _ in 0..<operationsPerSample { _ = serviceHolder.config }
    }

    runner.measure("@Service first access") {
        ServiceEnv.$current.withValue(env) {
            for _ in 0..<operationsPerSample {
                let holder = ServiceHolder()
                _ = holder.config
            }
        }
    }

    let providerHolder = ServiceEnv.$current.withValue(env) { ProviderHolder() }
    runner.measure("@Provider") {
        for _ in 0..<operationsPerSample { _ = providerHolder.config }
    }

    runner.measure("resolve singleton (8 threads)", samples: 200) {
        resolveConcurrently(in: env, threads: 8)
    }
}

@MainActor
private func runMainActorBenchmarks(with runner: BenchmarkRunner, in env: ServiceEnv) throws {
    try runner.measure("resolveMain singleton") {
        for _ in 0..<operationsPerSample { _ = try env.resolveMain(MainConfig.self) }
    }

    let serviceHolder = ServiceEnv.$current.withValue(env) { MainServiceHolder() }
    runner.measure("@MainService cached") {
        for _ in 0..<operationsPerSample { _ = serviceHolder.config }
    }

    let providerHolder = ServiceEnv.$current.withValue(env) { MainProviderHolder() }
    runner.measure("@MainProvider") {
        for _ in 0..<operationsPerSample { _ = providerHolder.config }
    }
}

private func runControlBenchmark(with runner: BenchmarkRunner) {
    let control = ControlRegistry()
    runner.measure("control: mutex + dictionary + downcast") {
        // The check depends on every lookup, so the optimizer cannot remove the lookups.
        var hits = 0
        for _ in 0..<operationsPerSample where control.containsConfig() {
            hits &+= 1
        }
        precondition(hits == operationsPerSample)
    }
}
