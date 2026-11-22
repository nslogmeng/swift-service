//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

import Dispatch
import Service
import Synchronization

struct Config: Sendable {
    let id: Int
}

protocol Greeter: Sendable {
    func greet() -> Int
}

struct DefaultGreeter: Greeter {
    func greet() -> Int { 1 }
}

struct TransientService: Sendable {
    let id: Int
}

struct GraphService: Sendable {
    let id: Int
}

struct CustomService: Sendable {
    let id: Int
}

struct Leaf: Sendable {
    let id: Int
}

struct Middle: Sendable {
    let leaf: Leaf
}

struct Top: Sendable {
    let middle: Middle
    let leaf: Leaf
}

@MainActor
final class MainConfig {
    let id: Int

    init(id: Int) {
        self.id = id
    }
}

// Property wrappers capture `ServiceEnv.current` in their initializer, so holders are constructed while
// the benchmark environment is bound. Each holder has one wrapper.

struct ServiceHolder: Sendable {
    @Service var config: Config
}

struct ProviderHolder: Sendable {
    @Provider var config: Config
}

@MainActor
struct MainServiceHolder {
    @MainService var config: MainConfig
}

@MainActor
struct MainProviderHolder {
    @MainProvider var config: MainConfig
}

/// Creates a dedicated environment with every fixture registered, except the graph-scoped one.
@MainActor
func makeEnvironment() -> ServiceEnv {
    let env = ServiceEnv(name: "bench")
    env.register(Config.self) { Config(id: 1) }
    env.register((any Greeter).self) { DefaultGreeter() }
    env.register(TransientService.self, scope: .transient) { TransientService(id: 1) }
    env.register(CustomService.self, scope: .custom("bench")) { CustomService(id: 1) }
    env.register(Leaf.self) { Leaf(id: 1) }
    env.register(Middle.self) { Middle(leaf: try env.resolve(Leaf.self)) }
    env.register(Top.self, scope: .transient) {
        Top(middle: try env.resolve(Middle.self), leaf: try env.resolve(Leaf.self))
    }
    env.registerMain(MainConfig.self) { MainConfig(id: 1) }
    return env
}

/// Creates the environment of the graph benchmark. The other benchmarks use an environment that has no
/// graph-scoped registration.
func makeGraphEnvironment() -> ServiceEnv {
    let env = ServiceEnv(name: "bench-graph")
    env.register(GraphService.self, scope: .graph) { GraphService(id: 1) }
    return env
}

/// Resolves `Config` `operationsPerSample` times on each of `threads` threads and returns when all have finished.
func resolveConcurrently(in env: ServiceEnv, threads: Int) {
    DispatchQueue.concurrentPerform(iterations: threads) { _ in
        for _ in 0..<operationsPerSample {
            do {
                _ = try env.resolve(Config.self)
            } catch {
                fatalError("resolve failed: \(error)")
            }
        }
    }
}

/// A lock-protected dictionary lookup and a downcast without `Service`: the lower bound for `resolve`.
final class ControlRegistry: Sendable {
    private let key = ObjectIdentifier(Config.self)
    private let table: Mutex<[ObjectIdentifier: any Sendable]>

    init() {
        table = Mutex([ObjectIdentifier(Config.self): Config(id: 1)])
    }

    /// Returns whether a `Config` is stored under its type.
    func containsConfig() -> Bool {
        table.withLock { $0[key] as? Config } != nil
    }
}
