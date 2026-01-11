//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

import Synchronization

/// A thread-safe property wrapper using a mutex for value storage.
/// Provides safe concurrent access to the wrapped value.
/// Used for internal state in service storage and context.
@propertyWrapper
final class Locked<Value: Sendable>: @unchecked Sendable {
    private let storage: Mutex<Value>

    /// Returns the current value, locking for thread safety.
    var wrappedValue: Value {
        get { storage.withLock({ $0 }) }
        set { storage.withLock({ $0 = newValue }) }
    }

    /// Returns the property wrapper itself.
    var projectedValue: Locked<Value> {
        return self
    }

    /// Executes a closure with exclusive access to the wrapped value.
    /// This is useful for performing atomic operations that require multiple steps.
    ///
    /// - Parameter body: A closure that receives an inout reference to the wrapped value.
    /// - Returns: The result of the closure.
    func withLock<R>(_ body: (inout sending Value) throws -> sending R) rethrows -> R {
        return try storage.withLock(body)
    }

    /// Initializes the wrapper with a default value.
    ///
    /// - Parameter default: The default value.
    init(default: Value) {
        self.storage = Mutex(`default`)
    }

    /// Convenience initializer for array literal values.
    convenience init() where Value: ExpressibleByArrayLiteral {
        self.init(default: [])
    }

    /// Convenience initializer for dictionary literal values.
    convenience init() where Value: ExpressibleByDictionaryLiteral {
        self.init(default: [:])
    }

    /// Convenience initializer for nil literal values.
    convenience init() where Value: ExpressibleByNilLiteral {
        self.init(default: nil)
    }
}
