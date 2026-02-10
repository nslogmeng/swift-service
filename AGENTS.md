# AGENTS.md

This file provides guidance to AI coding assistants when working with code in this repository.

## Project Overview

Swift dependency injection framework with zero external dependencies. Supports Swift 6.2+ with strict concurrency model. Multi-platform: iOS 18+, macOS 15+, watchOS 11+, tvOS 18+, visionOS 2+.

## Commands

```bash
# Build
swift build

# Run all tests
swift test

# Format code (uses .swift-format config)
swift format format --in-place --recursive ./

# Build documentation (all languages)
./scripts/build-docc.sh --all

# Build documentation (single language, faster)
./scripts/build-docc.sh --lang en

# Preview docs locally
python3 -m http.server 8000 --directory .build/docs
```

## Architecture

### Core Components

**Property Wrappers** (`Service.swift`, `Provider.swift`)
- `@Service<S: Sendable>` — Cached, thread-safe injection via `Locked<S?>`
- `@MainService<S>` — Cached, MainActor-isolated injection via `Box<S?>`
- `@Provider<S: Sendable>` — Uncached, resolves on every access (scope-driven caching)
- `@MainProvider<S>` — Uncached, MainActor-isolated, resolves on every access

**Utility Types** (`Utils/`)
- `Locked<Value: Sendable>` (`Lock.swift`) — Mutex-based thread-safe wrapper using `Synchronization.Mutex`
- `Box<Value>` (`Box.swift`) — Reference-type wrapper for interior mutability, `@unchecked Sendable`. Thread safety is **not** provided by Box itself; callers must guarantee safety via external synchronization

**Service Environment** (`ServiceEnv.swift`)
- Manages service registrations per environment (`online`, `test`, `dev`)
- Uses `@TaskLocal` for task-based environment isolation
- `resetCaches()` clears cached instances, `resetAll()` clears everything

**Service Storage** (`ServiceStorage.swift`)
- Dual storage: Sendable services use mutex-based `@Locked`, MainActor services use actor isolation
- Implements singleton caching behavior

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

**Mutex isolation** (for Sendable services and shared state):
- `Locked<Value>` / `@Locked` — wraps `Synchronization.Mutex`, the primary synchronization primitive
- `@Service` uses `Locked<S?>` — check-and-set is fully atomic within `withLock`
- `ServiceStorage` — all state (`caches`, `providers`, `mainProviders`) is `@Locked`
- `GraphCacheBox` — cache dictionary is `@Locked`

**MainActor isolation** (for non-Sendable UI services):
- `@MainService` / `@MainProvider` — struct-level `@MainActor`, compiler-enforced serial access
- `@MainService` uses `Box<S?>` for interior mutability without mutating getter; safe because all access is on MainActor

**`Box<Value>` conventions:**
- In `@MainService`: mutable storage, protected by `@MainActor`
- In `ServiceStorage` / `GraphCacheBox`: stored in `@Locked` dictionaries as **write-once** — `Box` is initialized with its final value and `box.value` must **never** be mutated after insertion into the dictionary. This invariant is by convention, not enforced by the type system

**Rules for modifying or adding code:**
- New concurrent mutable state → use `Locked<Value>` (Value must be `Sendable`)
- Interior mutability in `@MainActor` context → use `Box<Value>`
- `@unchecked Sendable` → internal types only; always document which isolation mechanism guarantees safety
- Never mutate `Box.value` on instances retrieved from `@Locked` dictionaries
- Never mark public types as `@unchecked Sendable` — this framework's design philosophy explicitly avoids exposing unchecked Sendable in public API

### Documentation

DocC documentation in `/Sources/Service/Documentation.docc/` with multi-language support (en, zh-Hans). Build with `./scripts/build-docc.sh`.

## Multi-language Documentation

All public documentation must provide multi-language versions. Currently supported languages: **en**, **zh-Hans**.

- **README**: `README.md` (English), `README.zh-Hans.md` (Chinese)
- **DocC Articles**: Each article in `Documentation.docc/Articles/` has both `.md` (English) and `.zh-Hans.md` versions
- **Scripts README**: `scripts/README.md` and `scripts/README.zh-Hans.md`

When adding or modifying documentation, ensure all language versions are updated.

## Code Style

Line length: 120 characters. Uses swift-format with:
- FileScopedDeclarationPrivacy (private by default)
- NoBlockComments, NeverUseForceTry, NeverUseImplicitlyUnwrappedOptionals
- OrderedImports, UseTripleSlashForDocumentationComments
