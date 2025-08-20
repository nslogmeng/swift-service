//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

import Synchronization

/// Thread-safe property wrapper using a mutex for value storage.
/// Provides safe concurrent access to the wrapped value.
/// Used for internal state in service storage and context.
@propertyWrapper
final class Locked<Value: Sendable>: Sendable {
    private let storage: Mutex<Value>

    /// Returns the current value, locking for thread safety.
    var wrappedValue: Value {
        get { storage.withLock { $0 } }
        set { storage.withLock { $0 = newValue } }
    }

    /// Returns the property wrapper itself.
    var projectedValue: Locked<Value> {
        return self
    }

    /// Initializes the wrapper with a default value.
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
