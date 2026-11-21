//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

import Service

// This module builds with default MainActor isolation. Declarations below carry an isolation
// annotation only where the MainActorServices article requires one for such modules.

// MARK: - MainActor track (isolation inferred as @MainActor)

protocol Store {
    var name: String { get }
}

final class MemoryStore: Store {
    var name = "memory"
}

final class CounterModel {
    var count = 0
}

final class ScreenModel {
    let store: any Store
    init(store: any Store) { self.store = store }
}

final class UnregisteredModel {}

final class TransientModel {}

struct MainHolder {
    @MainService var store: any Store
    @MainService var counter: CounterModel
    @MainService var missing: UnregisteredModel?
}

final class MainProviderHolder {
    @MainProvider var model: TransientModel
}

struct MainAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.registerMain((any Store).self) { MemoryStore() }
        env.registerMain(CounterModel.self) { CounterModel() }
    }
}

// MARK: - Sendable track

// Types that conform to a nonisolated protocol inheriting Sendable are inferred nonisolated.
nonisolated protocol Logger: Sendable {
    func line(_ message: String) -> String
}

struct PrefixLogger: Logger {
    let prefix: String

    init(prefix: String) {
        self.prefix = prefix
    }

    func line(_ message: String) -> String {
        "\(prefix): \(message)"
    }
}

// ServiceKey is nonisolated and inherits Sendable.
struct Config: ServiceKey {
    let endpoint: String

    init(endpoint: String) {
        self.endpoint = endpoint
    }

    static var `default`: Config { Config(endpoint: "https://example.com") }
}

// A concrete type registered without a protocol opts out of the default isolation itself.
nonisolated final class Cache: Sendable {
    let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
    }
}

struct SendableHolder {
    @Service var logger: any Logger
    @Service var config: Config
}

@concurrent
func useSendableServicesOffMainActor(env: ServiceEnv) async throws -> (line: String, endpoint: String, capacity: Int) {
    let logger = try env.resolve((any Logger).self)
    let config = try env.resolve(Config.self)
    let cache = try env.resolve(Cache.self)
    return (logger.line("ready"), config.endpoint, cache.capacity)
}
