//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

/// A thread-safe property wrapper using a mutex for value storage.
/// Provides safe concurrent access to the wrapped value.
/// Used for internal state in service storage and context.
@propertyWrapper
final class Locked<Value: Sendable>: @unchecked Sendable {
    private let storage: _MutexBox<Value>

    /// Returns the current value, locking for thread safety.
    var wrappedValue: Value {
        get {
            return _getValue()
        }
        set {
            _setValue(newValue)
        }
    }

    /// Internal helper to get value with proper version-specific handling
    private func _getValue() -> Value {
        #if compiler(<6.1)
            return storage.withLock { $0 }
        #else
            return storage.withLock { (value: inout sending Value) -> sending Value in
                return value
            }
        #endif
    }

    /// Internal helper to set value with proper version-specific handling
    private func _setValue(_ newValue: Value) {
        #if compiler(<6.1)
            storage.withLock { $0 = newValue }
        #else
            storage.withLock { (value: inout sending Value) -> sending Void in
                value = newValue
            }
        #endif
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
    #if compiler(<6.1)
        func withLock<R>(_ body: (inout Value) throws -> R) rethrows -> R {
            return try storage.withLock(body)
        }
    #else
        func withLock<R>(_ body: (inout Value) throws -> R) rethrows -> R {
            // Adapt closure to match Synchronization.Mutex's sending signature
            return try storage.withLock { (value: inout sending Value) -> sending R in
                return try body(&value)
            }
        }
    #endif

    /// Initializes the wrapper with a default value.
    ///
    /// - Parameter default: The default value.
    init(default: Value) {
        self.storage = _MutexBox(`default`)
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

// work around for Swift 6.0 Compiler Bug
#if compiler(<6.1)
    #if canImport(Glibc)
        import Glibc
    #endif

    #if canImport(Darwin)
        import Darwin
    #endif

    /// Minimal mutex box for Linux Swift 6.0.x workaround
    final class _MutexBox<Value>: @unchecked Sendable {
        private var value: Value
        private var mutex = pthread_mutex_t()

        init(_ value: Value) {
            self.value = value
            pthread_mutex_init(&mutex, nil)
        }

        deinit {
            pthread_mutex_destroy(&mutex)
        }

        @inline(__always)
        func withLock<R>(_ body: (inout Value) throws -> R) rethrows -> R {
            pthread_mutex_lock(&mutex)
            defer { pthread_mutex_unlock(&mutex) }
            return try body(&value)
        }
    }

#else
    import Synchronization
    typealias _MutexBox<Value> = Mutex<Value>
#endif
