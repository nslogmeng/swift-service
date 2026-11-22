//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

/// A reference-type wrapper that provides interior mutability for stored values.
///
/// Used by `@MainService` to enable non-mutating lazy access.
///
/// Thread safety is guaranteed by the caller's isolation (`@MainActor`), not by `Box` itself.
final class Box<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}
