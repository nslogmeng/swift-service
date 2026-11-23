# AGENTS.md

This file provides guidance to AI coding assistants when working with code in this repository.

## Project Overview

Swift dependency injection framework with zero external dependencies. Supports Swift 6.2+ with strict concurrency model. Multi-platform: iOS 16+, macOS 13+, watchOS 9+, tvOS 16+, visionOS 1+, Linux, Wasm, Android.

## Commands

```bash
# Build
swift build

# Run all tests
swift test

# Run all tests in an optimized build (CI runs both configurations)
swift test -c release -Xswiftc -enable-testing

# Run benchmarks (separate package, see Benchmarks/README.md)
swift run -c release --package-path Benchmarks ServiceBenchmarks

# Format code (uses .swift-format config)
swift format format --in-place --recursive ./

# Build documentation (all languages)
./scripts/build-docc.sh --all

# Build documentation (single language, faster)
./scripts/build-docc.sh --lang en

# Preview docs locally
python3 -m http.server 8000 --directory .build/docs
```

## Swift Versions

- Policy: the package supports the latest Swift release and the two minor releases before it. Currently Swift 6.2, 6.3, and 6.4. Both READMEs state this policy.
- Minimum: Swift 6.2, set by `swift-tools-version` in `Package.swift` and `Benchmarks/Package.swift`. Code that needs a newer compiler must be guarded with `#if compiler(>=...)`.
- `main` must build and pass tests on every supported Swift release. `build.yml` and `test.yml` run that matrix on Linux and macOS. `test.yml` runs the tests in the debug and the release configuration.
- When a new Swift release ships, add it to both matrices. Each macOS entry pins a runner image and an Xcode version; the macOS READMEs in `actions/runner-images` list the Xcode versions each image carries.
- Then drop the oldest release in the next minor version of the package, not in a patch version: raise both `swift-tools-version` lines, remove its matrix entries, and update the versions named in this section, in both READMEs, and in the Benchmarks READMEs.

## Architecture

### Core Components

**Property Wrappers** (`Service.swift`, `Provider.swift`)
- `@Service<S: Sendable>` — Cached, thread-safe injection via `Locked<S?>`
- `@MainService<S>` — Cached, MainActor-isolated injection via `Box<S?>`
- `@Provider<S: Sendable>` — Uncached, resolves on every access (scope-driven caching)
- `@MainProvider<S>` — Uncached, MainActor-isolated, resolves on every access

**Utility Types** (`Utils/`)
- `Locked<Value: Sendable>` (`Lock.swift`) — Thread-safe wrapper using platform-specific locking via `LockStorage` (`LockStorage.swift`)
- `Box<Value>` (`Box.swift`) — Reference-type wrapper for interior mutability, `@unchecked Sendable`. Thread safety is **not** provided by Box itself; callers must guarantee safety via external synchronization
- `CacheBox<Value>` (`CacheBox.swift`) — Immutable box for one cached service instance. Caches store it as its type-erased base class `AnyCacheBox`

**Service Environment** (`ServiceEnv.swift`)
- Manages service registrations per environment (`online`, `test`, `dev`)
- Uses `@TaskLocal` for task-based environment isolation
- `==` and `hash(into:)` use the identity of `storage`: two values are equal only if they share a registry. `name` is not unique and does not identify an environment
- `resetCaches()` clears cached instances, `resetAll()` clears everything

**Service Storage** (`ServiceStorage.swift`)
- Dual storage: Sendable services use mutex-based `@Locked`, MainActor services use actor isolation
- Implements singleton caching behavior: the factory runs at most once per cached instance (see Thread Safety Model)

**Registration & Resolution** (`ServiceEnv+Register.swift`, `ServiceEnv+Resolver.swift`)
- `register<Service: Sendable>` / `registerMain<S>` for registration
- The overloads that register an existing instance take the `instance:` label. Do not add an overload whose unlabeled parameter is generic over the argument (`_ instance: Service`): a metatype is a value, so `register(X.self)` without a factory would select that overload and register `X.Type`
- `resolve<Service: Sendable>` / `resolveMain<S>` for resolution
- Automatic circular dependency detection via TaskLocal resolution stack

**Assembly Pattern** (`ServiceAssembly.swift`)
- `ServiceAssembly` protocol for modular service registration
- All assembly operations are `@MainActor` constrained

**ServiceKey Protocol** (`ServiceKey.swift`)
- Types conforming provide `static var default: Self` for simple registration
- For Sendable services only: `ServiceKey` inherits `Sendable` and `default` is nonisolated. `registerMain` has no `ServiceKey` overload

### Thread Safety Model

The framework uses two isolation models. Every `@unchecked Sendable` internal type relies on exactly one:

**Lock isolation** (for Sendable services and shared state):
- `Locked<Value>` / `@Locked` — wraps `LockStorage`, a platform-specific lock abstraction:
  - Apple: `OSAllocatedUnfairLock` (iOS 16+ / macOS 13+)
  - Linux / Android: `Synchronization.Mutex`
  - Wasm: no-op (single-threaded)
- `@Service` uses `Locked<S?>` — check-and-set is fully atomic within `withLock`
- `ServiceStorage` — all state is in `registry`, one `@Locked` struct for the Sendable and the MainActor registrations
- `GraphCacheBox` — cache dictionary is `@Locked`

**Per-registration once in `ServiceStorage`** (singleton and custom scopes):
- `registry` is one `@Locked` struct with two dictionaries, `providers` and `mainProviders`. Both map `ObjectIdentifier(Service.self)` to an entry. Use the static type for the key, never the `type` argument: it can be the metatype of a subclass
- An entry holds the scope, the factory, and for singleton and custom scopes a cache slot (`Locked<AnyCacheBox?>`) with its own lock. A slot holds `nil` until a factory succeeds, then the instance's `CacheBox`
- Resolution copies the entry under the registry lock and releases that lock. Fast path: `cachedBox` reads the slot and returns a cached box without resolution tracking. Otherwise, inside `ServiceContext.withResolutionTracking`, `resolveWithScope` runs `slot.withLock { return the cached box, or run the factory and store its box }`. The factory runs at most once per cached instance; concurrent first resolvers of the same service block until it finishes. Semantics match `swift_once`
- Lock order: never acquire a slot lock or run a factory while holding the registry lock. Holding a slot lock while taking the registry lock is allowed (nested resolution of another service, reset inside a factory)
- Never release an entry, a slot, or a `CacheBox` while holding the registry lock or a graph cache lock. A `deinit` of a cached instance, or of an object that a factory captured, can call back into the storage. A critical section returns what it replaces or removes, and the caller passes it to `withExtendedLifetime` after the lock. Discarding the result with `_ =` is not enough: an optimized build can release it inside the critical section
- Slot locks are not recursive: re-locking on the same thread crashes the process (`OSAllocatedUnfairLock` aborts, `Mutex` traps on Linux). Two rules keep one task from re-locking a slot: the fast path reads a slot only when `ServiceContext.isResolving` is `false` for the type, and `resolveWithScope` is called only inside `ServiceContext.withResolutionTracking`, which throws `circularDependency` for re-entrance within one task. The resolution stack is task-local, so a different task that runs on the same thread before the factory returns (e.g. from a nested run loop inside the factory) is not rejected and hits the slot lock
- A factory that throws or returns `nil` leaves the slot empty, so the next resolution runs it again
- `resetCaches()` / `resetScope(_:)` give the affected entries new slots, and `resetAll()` removes the entries. They take only the registry lock and never wait for a running factory. Resolutions that already hold an old slot (the one running the factory and those waiting on it) return the instance created in that slot; later resolutions use the new slot
- Registering a type again replaces its entry. The new entry keeps the slot if the scope is unchanged, so a cached instance stays until a reset; with another scope it starts with an empty slot
- Use only `withLock` on slots. It is the one operation shared by all three `LockStorage` implementations
- `ServiceStorage.resolve` / `resolveMain` and `withResolutionTracking` return a non-optional instance. Do not pass `Optional<Service>` through them as a generic argument or result: unspecialized generic code looks up that metadata at run time on every call

**MainActor isolation** (for services created and used on the main actor; no `Sendable` requirement):
- `@MainService` / `@MainProvider` — struct-level `@MainActor`, compiler-enforced serial access
- `@MainService` uses `Box<S?>` for interior mutability without mutating getter; safe because all access is on MainActor

**Boxes:**
- `Box<Value>` — mutable storage. Used only by `@MainService`, protected by `@MainActor`
- `CacheBox<Value>` — immutable (`let value`). `ServiceStorage` cache slots and the `GraphCacheBox` dictionary store it as `AnyCacheBox`. A cache stores an instance of service type `S` only as `CacheBox<S>` and reads it back with a class cast to `CacheBox<S>`. A cache slot is assigned at most once (`nil` → box)

**Rules for modifying or adding code:**
- New concurrent mutable state → use `Locked<Value>` (Value must be `Sendable`)
- Change `@Locked` state only inside `withLock`. `wrappedValue` is read-only: a get followed by a set is two critical sections and loses concurrent updates
- Interior mutability in `@MainActor` context → use `Box<Value>`
- `@unchecked Sendable` → internal types only; always document which isolation mechanism guarantees safety
- Cached service instances → store in `CacheBox<S>`, with `S` the service type that the cache is keyed by. Do not cache instances in `Box`
- Never mark public types as `@unchecked Sendable` — this framework's design philosophy explicitly avoids exposing unchecked Sendable in public API

### Test Targets

- `ServiceTests` — behavior tests for the library
- `DefaultMainActorIsolationTests` — compiled with `.defaultIsolation(MainActor.self)`, the setting of new Xcode app targets. Its fixtures carry only the annotations that the MainActorServices article requires in such modules. The target fails to compile when a public API stops working there, so add a fixture when adding public API

### Documentation

DocC documentation in `/Sources/Service/Documentation.docc/` with multi-language support (en, zh-Hans). Build with `./scripts/build-docc.sh`.

## Multi-language Documentation

All public documentation must provide multi-language versions. Currently supported languages: **en**, **zh-Hans**.

- **README**: `README.md` (English), `README.zh-Hans.md` (Chinese)
- **DocC Articles**: Each article in `Documentation.docc/Articles/` has both `.md` (English) and `.zh-Hans.md` versions
- **Scripts README**: `scripts/README.md` and `scripts/README.zh-Hans.md`
- **Benchmarks README**: `Benchmarks/README.md` and `Benchmarks/README.zh-Hans.md`

When adding or modifying documentation, ensure all language versions are updated.

## Code Style

Line length: 120 characters. Uses swift-format with:
- FileScopedDeclarationPrivacy (private by default)
- NoBlockComments, NeverUseForceTry, NeverUseImplicitlyUnwrappedOptionals
- OrderedImports, UseTripleSlashForDocumentationComments
