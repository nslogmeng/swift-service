//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

import Foundation
import Testing

@testable import Service

// MARK: - ServiceKey Tests

@Test("ServiceKey protocol can define default services")
func testServiceKeyProtocol() async throws {
    let testEnv = ServiceEnv(name: "test")
    ServiceEnv.$current.withValue(testEnv) {
        // Register service using ServiceKey
        ServiceEnv.current.register(DatabaseServiceKey.self)

        // Verify service can be accessed by type
        let _ = ServiceEnv.current.resolve(DatabaseServiceKey.self)
        // If resolution succeeds, registration and resolution work correctly
    }
}
