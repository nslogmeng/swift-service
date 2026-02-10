//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

/// A reference-type wrapper that provides interior mutability for stored values.
///
/// Used by property wrappers to enable non-mutating lazy access, and by internal
/// storage as a type-erased container in synchronized collections.
///
/// Thread safety is guaranteed by the caller's synchronization mechanism
/// (`@Locked`, `@MainActor`, or `Mutex`), not by `Box` itself.
final class Box<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}
