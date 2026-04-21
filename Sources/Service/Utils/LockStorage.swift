//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

#if canImport(os)
import os

/// Apple platforms: OSAllocatedUnfairLock (iOS 16+ / macOS 13+)
/// Uses the stateless variant to avoid `@Sendable` closure requirement
/// of the stateful `withLock`, preserving `sending` parameter support.
final class LockStorage<Value: Sendable>: @unchecked Sendable {
    private let _lock = OSAllocatedUnfairLock()
    nonisolated(unsafe) private var _value: Value

    // The `unsafe` expression marker required by SE-0458 on reads/writes
    // of `_value` is intentionally omitted so the source parses on Swift 6.0
    // toolchains — Linux 6.0.3 does not fully skip-parse `#if compiler(>=6.2)`
    // branches that contain the `unsafe` keyword. Strict-memory-safety on 6.2
    // surfaces these two accesses as warnings; the `nonisolated(unsafe)`
    // annotation still declares the intent and runtime semantics are unchanged.
    init(_ value: Value) { _value = value }

    func withLock<R>(_ body: (inout sending Value) throws -> sending R) rethrows -> R {
        _lock.lock()
        defer { _lock.unlock() }
        return try body(&_value)
    }
}

#elseif canImport(WASILibc)

/// Wasm: single-threaded environment, no locking needed.
/// The standard wasm32-unknown-wasi target does not support threading,
/// so direct access is safe without synchronization.
final class LockStorage<Value: Sendable>: @unchecked Sendable {
    private var _value: Value

    init(_ value: Value) { _value = value }

    func withLock<R>(_ body: (inout sending Value) throws -> sending R) rethrows -> R {
        try body(&_value)
    }
}

#else
import Synchronization

/// Linux / Android: Synchronization.Mutex from Swift stdlib.
/// No OS version restriction on non-Apple platforms.
final class LockStorage<Value: Sendable>: @unchecked Sendable {
    private let mutex: Mutex<Value>

    init(_ value: Value) { mutex = Mutex(value) }

    func withLock<R>(_ body: (inout sending Value) throws -> sending R) rethrows -> R {
        try mutex.withLock(body)
    }
}
#endif
