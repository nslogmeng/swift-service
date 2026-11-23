//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

import Service
import Testing

@Suite("Default MainActor Isolation")
struct DefaultMainActorIsolationTests {
    // MARK: - MainActor track

    @Test func singletonReturnsSameInstance() throws {
        let env = ServiceEnv(name: "dmi-singleton")
        env.registerMain(CounterModel.self) { CounterModel() }
        let first = try env.resolveMain(CounterModel.self)
        let second = try env.resolveMain(CounterModel.self)
        #expect(first === second)
    }

    @Test func transientReturnsDistinctInstances() throws {
        let env = ServiceEnv(name: "dmi-transient")
        env.registerMain(CounterModel.self, scope: .transient) { CounterModel() }
        let first = try env.resolveMain(CounterModel.self)
        let second = try env.resolveMain(CounterModel.self)
        #expect(first !== second)
    }

    @Test func protocolExistentialWithoutSendableResolvesAndFactoryResolvesDependency() throws {
        let env = ServiceEnv(name: "dmi-existential")
        env.registerMain((any Store).self) { MemoryStore() }
        env.registerMain(ScreenModel.self) {
            ScreenModel(store: try env.resolveMain((any Store).self))
        }
        let screen = try env.resolveMain(ScreenModel.self)
        #expect(screen.store.name == "memory")
    }

    @Test func mainWrappersReturnRegisteredInstances() {
        let env = ServiceEnv(name: "dmi-main-wrappers")
        ServiceEnv.$current.withValue(env) {
            let counter = CounterModel()
            env.registerMain(instance: counter)
            env.registerMain((any Store).self) { MemoryStore() }
            env.registerMain(TransientModel.self, scope: .transient) { TransientModel() }

            let holder = MainHolder()
            #expect(holder.store.name == "memory")
            #expect(holder.missing == nil)
            #expect(holder.counter === counter)

            let provider = MainProviderHolder()
            #expect(provider.model !== provider.model)
        }
    }

    @Test func assemblyRegistersServices() throws {
        let env = ServiceEnv(name: "dmi-assembly")
        env.assemble(MainAssembly())
        #expect(try env.resolveMain((any Store).self).name == "memory")
        #expect(try env.resolveMain(CounterModel.self).count == 0)
    }

    // MARK: - Sendable track

    @Test func sendableServicesAreCreatedAndUsedOffMainActor() async throws {
        let env = ServiceEnv(name: "dmi-off-main")
        env.register((any Logger).self) { PrefixLogger(prefix: "app") }
        env.register(Config.self)
        env.register(Cache.self) { Cache(capacity: 100) }

        let result = try await useSendableServicesOffMainActor(env: env)
        #expect(result.line == "app: ready")
        #expect(result.endpoint == "https://example.com")
        #expect(result.capacity == 100)
    }

    @Test func serviceWrapperInjectsSendableServices() {
        let env = ServiceEnv(name: "dmi-service-wrapper")
        ServiceEnv.$current.withValue(env) {
            env.register((any Logger).self) { PrefixLogger(prefix: "app") }
            env.register(Config.self)
            let holder = SendableHolder()
            #expect(holder.logger.line("ready") == "app: ready")
            #expect(holder.config.endpoint == "https://example.com")
        }
    }
}
