//
//  Copyright © 2026 Service Contributors. All rights reserved.
//

import Testing

@testable import Service

/// Tests of the resolution that the optional property wrappers use: `nil` for a type without
/// a registration, and the error for a registered type that cannot be created.
@Suite("Optional Resolution Tests")
struct OptionalResolutionTests {
    @Test @MainActor func returnsNilForTypeRegisteredInTheOtherCategory() throws {
        let env = ServiceEnv(name: "optional-other-category")
        env.registerMain(MainOnly.self) { MainOnly() }
        env.register(SendableOnly.self) { SendableOnly() }

        #expect(try env.storage.resolveIfRegistered(MainOnly.self) == nil)
        #expect(try env.storage.resolveMainIfRegistered(SendableOnly.self) == nil)
    }

    // The factory of a registered service needs a service that is not registered. The error names
    // the missing service, and it is not turned into `nil`.

    @Test func throwsWhenDependencyOfRegisteredServiceIsNotRegistered() {
        let env = ServiceEnv(name: "optional-missing-dependency")
        env.register(NeedsDependency.self) {
            NeedsDependency(dependency: try env.resolve(Dependency.self))
        }

        let error = #expect(throws: ServiceError.self) {
            try env.storage.resolveIfRegistered(NeedsDependency.self)
        }
        #expect(error?.missingServiceType == String(describing: Dependency.self))
    }

    @Test @MainActor func throwsWhenDependencyOfRegisteredMainServiceIsNotRegistered() {
        let env = ServiceEnv(name: "optional-missing-dependency-main")
        env.registerMain(MainNeedsDependency.self) {
            MainNeedsDependency(dependency: try env.resolveMain(Dependency.self))
        }

        let error = #expect(throws: ServiceError.self) {
            try env.storage.resolveMainIfRegistered(MainNeedsDependency.self)
        }
        #expect(error?.missingServiceType == String(describing: Dependency.self))
    }
}

// MARK: - Fixtures

extension OptionalResolutionTests {
    struct SendableOnly: Sendable, Equatable {}

    @MainActor
    final class MainOnly {}

    struct Dependency: Sendable {}

    struct NeedsDependency: Sendable {
        let dependency: Dependency
    }

    @MainActor
    final class MainNeedsDependency {
        let dependency: Dependency
        init(dependency: Dependency) { self.dependency = dependency }
    }
}

extension ServiceError {
    /// The service type of a `notRegistered` error. `nil` for the other errors.
    fileprivate var missingServiceType: String? {
        if case .notRegistered(let serviceType) = self {
            return serviceType
        }
        return nil
    }
}
