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

- Minimum: Swift 6.2, set by `swift-tools-version` in `Package.swift`. Code that needs a newer compiler must be guarded with `#if compiler(>=...)`.
- `main` must build and pass tests on every Swift release from the minimum to the latest. `build.yml` and `test.yml` run that matrix on Linux and macOS.
- When a new Swift release ships, add it to both matrices. Each macOS entry pins a runner image and an Xcode version; the macOS READMEs in `actions/runner-images` list the Xcode versions each image carries.

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

**Service Environment** (`ServiceEnv.swift`)
- Manages service registrations per environment (`online`, `test`, `dev`)
- Uses `@TaskLocal` for task-based environment isolation
- `resetCaches()` clears cached instances, `resetAll()` clears everything

**Service Storage** (`ServiceStorage.swift`)
- Dual storage: Sendable services use mutex-based `@Locked`, MainActor services use actor isolation
- Implements singleton caching behavior: the factory runs at most once per cached instance (see Thread Safety Model)

**Registration & Resolution** (`ServiceEnv+Register.swift`, `ServiceEnv+Resolver.swift`)
- `register<Service: Sendable>` / `registerMain<S>` for registration
- `resolve<Service: Sendable>` / `resolveMain<S>` for resolution
- Automatic circular dependency detection via TaskLocal resolution stack

**Assembly Pattern** (`ServiceAssembly.swift`)
- `ServiceAssembly` protocol for modular service registration
- All assembly operations are `@MainActor` constrained

**ServiceKey Protocol** (`ServiceKey.swift`)
- Types conforming provide `static var default: Self` for simple registration

### Thread Safety Model

The framework uses two isolation models. Every `@unchecked Sendable` internal type relies on exactly one:

**Lock isolation** (for Sendable services and shared state):
- `Locked<Value>` / `@Locked` — wraps `LockStorage`, a platform-specific lock abstraction:
  - Apple: `OSAllocatedUnfairLock` (iOS 16+ / macOS 13+)
  - Linux / Android: `Synchronization.Mutex`
  - Wasm: no-op (single-threaded)
- `@Service` uses `Locked<S?>` — check-and-set is fully atomic within `withLock`
- `ServiceStorage` — all state (`caches`, `providers`, `mainProviders`) is `@Locked`
- `GraphCacheBox` — cache dictionary is `@Locked`

**Per-key once in `ServiceStorage`** (singleton and custom scopes):
- `caches` is `[CacheKey: Locked<Box<Any>?>]`. Each key has one slot with its own lock. A slot holds `nil` until a factory succeeds, then the instance's `Box`
- Resolution gets or inserts the slot under the dictionary lock, releases that lock, then runs `slot.withLock { return the cached box, or run the factory and store its box }`. The factory runs at most once per cached instance; concurrent first resolvers of the same key block until it finishes. Semantics match `swift_once`
- Lock order: never acquire a slot lock or run a factory while holding the dictionary lock. Holding a slot lock while taking the dictionary lock is allowed (nested resolution of another key, reset inside a factory)
- Slot locks are not recursive: re-locking on the same thread crashes the process (`OSAllocatedUnfairLock` aborts, `Mutex` traps on Linux). `ServiceEnv.resolve` / `resolveMain` must call storage inside `ServiceContext.withResolutionTracking`, which throws `circularDependency` for re-entrance within one task before storage is reached. The resolution stack is task-local, so a different task that runs on the same thread before the factory returns (e.g. from a nested run loop inside the factory) is not rejected and hits the slot lock
- A factory that throws or returns `nil` leaves the slot empty, so the next resolution runs it again
- `resetCaches()` / `resetScope(_:)` / `resetAll()` take only the dictionary lock and never wait for a running factory. Resolutions that already hold a removed slot (the one running the factory and those waiting on it) return the instance created in that slot; later resolutions insert a new slot
- Use only `withLock` on slots. It is the one operation shared by all three `LockStorage` implementations

**MainActor isolation** (for services created and used on the main actor; no `Sendable` requirement):
- `@MainService` / `@MainProvider` — struct-level `@MainActor`, compiler-enforced serial access
- `@MainService` uses `Box<S?>` for interior mutability without mutating getter; safe because all access is on MainActor

**`Box<Value>` conventions:**
- In `@MainService`: mutable storage, protected by `@MainActor`
- In `ServiceStorage` cache slots and the `GraphCacheBox` dictionary: stored in `@Locked` state as **write-once** — `Box` is initialized with its final value and `box.value` must **never** be mutated after it is stored. A cache slot is assigned at most once (`nil` → `Box`). This invariant is by convention, not enforced by the type system

**Rules for modifying or adding code:**
- New concurrent mutable state → use `Locked<Value>` (Value must be `Sendable`)
- Interior mutability in `@MainActor` context → use `Box<Value>`
- `@unchecked Sendable` → internal types only; always document which isolation mechanism guarantees safety
- Never mutate `Box.value` on instances retrieved from `@Locked` dictionaries or cache slots
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
