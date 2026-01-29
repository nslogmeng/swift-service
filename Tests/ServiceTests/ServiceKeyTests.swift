//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

import Foundation
import Testing

@testable import Service

@Suite("ServiceKey Tests")
struct ServiceKeyTests {
    @Test func registersAndResolvesServiceWithServiceKey() async throws {
        let testEnv = ServiceEnv(name: "servicekey-test")
        try ServiceEnv.$current.withValue(testEnv) {
            ServiceEnv.current.register(DatabaseServiceKey.self)

            _ = try ServiceEnv.current.resolve(DatabaseServiceKey.self)
        }
    }

    @Test func registersAndResolvesLoggerServiceKey() async throws {
        let testEnv = ServiceEnv(name: "servicekey-logger-test")
        try ServiceEnv.$current.withValue(testEnv) {
            ServiceEnv.current.register(LoggerServiceKey.self)

            _ = try ServiceEnv.current.resolve(LoggerServiceKey.self)
        }
    }

    @Test func maintainsSingletonBehavior() async throws {
        let testEnv = ServiceEnv(name: "servicekey-singleton-test")
        try ServiceEnv.$current.withValue(testEnv) {
            ServiceEnv.current.register(DatabaseServiceKey.self)

            _ = try ServiceEnv.current.resolve(DatabaseServiceKey.self)
            _ = try ServiceEnv.current.resolve(DatabaseServiceKey.self)
        }
    }
}
