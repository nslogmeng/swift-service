//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

/// The type-erased base class of `CacheBox`. Cache slots and graph caches store this type.
class AnyCacheBox: @unchecked Sendable {}

/// An immutable box that holds one cached service instance.
///
/// A cache stores an instance of service type `S` only in a `CacheBox<S>`. Reading the instance back is
/// a class cast to `CacheBox<S>`, not a dynamic cast from `Any`.
///
/// Safety: `value` never changes after `init`. The box of a Sendable service holds a `Sendable` value.
/// The box of a MainActor service is created and read only by `@MainActor` methods of `ServiceStorage`.
final class CacheBox<Value>: AnyCacheBox, @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
