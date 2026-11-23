//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

// `Locked` has one implementation for each platform. Each provides `init(_:)` and `withLock(_:)`.
// The extension at the end of the file builds on these two.

#if canImport(os)
import os

/// A value that is read and changed only while a lock is held. The lock is not recursive.
///
/// Safety: `_value` is accessed only inside `withLock`, while `_lock` is held.
final class Locked<Value: Sendable>: @unchecked Sendable {
    private let _lock = OSAllocatedUnfairLock()
    nonisolated(unsafe) private var _value: Value

    init(_ value: Value) { unsafe _value = value }

    /// Runs `body` with exclusive access to the value.
    func withLock<R>(_ body: (inout sending Value) throws -> sending R) rethrows -> R {
        _lock.lock()
        defer { _lock.unlock() }
        return try unsafe body(&_value)
    }
}

#elseif canImport(WASILibc)

/// A value that is read and changed only inside `withLock`.
///
/// Safety: WebAssembly runs on one thread, so there is no lock.
final class Locked<Value: Sendable>: @unchecked Sendable {
    private var _value: Value

    init(_ value: Value) { _value = value }

    /// Runs `body` with exclusive access to the value.
    func withLock<R>(_ body: (inout sending Value) throws -> sending R) rethrows -> R {
        try body(&_value)
    }
}

#else
import Synchronization

/// A value that is read and changed only while a lock is held. The lock is not recursive.
///
/// Safety: `Mutex` guards the value.
final class Locked<Value: Sendable>: @unchecked Sendable {
    private let mutex: Mutex<Value>

    init(_ value: Value) { mutex = Mutex(value) }

    /// Runs `body` with exclusive access to the value.
    func withLock<R>(_ body: (inout sending Value) throws -> sending R) rethrows -> R {
        try mutex.withLock(body)
    }
}
#endif

extension Locked {
    /// The current value.
    ///
    /// There is no setter. A get followed by a set is two critical sections, so concurrent changes
    /// can overwrite each other. Use `withLock` to change the value.
    var value: Value {
        withLock { $0 }
    }

    /// Creates a lock around an empty dictionary.
    convenience init() where Value: ExpressibleByDictionaryLiteral {
        self.init([:])
    }

    /// Creates a lock around `nil`.
    convenience init() where Value: ExpressibleByNilLiteral {
        self.init(nil)
    }
}
