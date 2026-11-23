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
- `@Service<S: Sendable>` / `@MainService<S>` — resolve on first access and keep the instance
- `@Provider<S: Sendable>` / `@MainProvider<S>` — resolve on every access. The registered scope decides what is cached
- Each wrapper captures `ServiceEnv.current` when it is initialized

**Service Environment** (`ServiceEnv.swift`)
- A value that refers to one `ServiceStorage`. `ServiceEnv.current` is task-local
- `==` and `hash(into:)` use the identity of the storage. `name` is not unique and does not identify an environment
- `resetCaches()` and `resetScope(_:)` empty caches. `resetAll()` also removes the registrations

**Registration & Resolution** (`ServiceEnv+Register.swift`, `ServiceEnv+Resolver.swift`)
- `register` / `resolve` for Sendable services, `registerMain` / `resolveMain` for MainActor services
- The overloads that register an existing instance take the `instance:` label. Do not add an overload whose unlabeled parameter is generic over the argument (`_ instance: Service`): a metatype is a value, so `register(X.self)` without a factory would select that overload and register `X.Type`

**Service Storage** (`ServiceStorage.swift`) — the registrations of one environment and the instances that they cache

**Service Context** (`ServiceContext.swift`) — the resolution stack and the graph cache of the current resolution chain. Both are task-local

**Assembly** (`ServiceAssembly.swift`) — `ServiceAssembly` protocol for modular registration. `@MainActor`

**ServiceKey** (`ServiceKey.swift`) — `static var default: Self`, for registration without a factory. For Sendable services only: `ServiceKey` inherits `Sendable` and `default` is nonisolated, so `registerMain` has no `ServiceKey` overload

**Utility Types** (`Utils/`)
- `Locked<Value: Sendable>` (`Lock.swift`) — a value behind a lock that is not recursive. One implementation for each platform: `OSAllocatedUnfairLock` on Apple platforms, `Synchronization.Mutex` on Linux and Android, no lock on Wasm, which runs on one thread
- `CacheBox<Value>` (`CacheBox.swift`) — immutable box for one cached instance. Caches store it as its base class `AnyCacheBox`
- `Box<Value>` (`Box.swift`) — mutable reference storage for `@MainService`, protected by `@MainActor`

### Thread Safety Model

Sendable services and shared state are behind locks. MainActor services are created and read on the main actor.

**Sendable conformances**
- Never mark a public type `@unchecked Sendable`
- Use `@unchecked Sendable` on an internal type only if the compiler cannot check it, and state in its comment what makes it safe. Today: `Locked`, `Box`, `AnyCacheBox`, `CacheBox`, `PendingBox`
- Put new shared mutable state into a `Locked` that is stored in a `let`. Change it only inside `withLock`. `value` has no setter, because a get followed by a set is two critical sections and loses concurrent changes

**Registry** (`ServiceStorage.registry`)
- One `Locked` dictionary from `ObjectIdentifier(Service.self)` to an entry. Use the static type for the key, never the `type` argument: it can be the metatype of a subclass
- An entry holds the scope, the factory, and for singleton and custom scopes a cache slot. The factory is `.sendable` or `.main`, so a type has one registration of one category
- While the registry lock is held: lock no slot, run no factory, release no entry. Releasing an entry can run a `deinit` that calls back into the storage. A critical section returns what it removes, and the caller passes it to `withExtendedLifetime` after the lock. An optimized build releases an unused result inside the critical section
- Registering a type again replaces its entry. The new entry keeps the slot if the scope and the category are the same, so a cached instance stays until a reset
- `resetCaches()` and `resetScope(_:)` give entries new slots, and `resetAll()` removes the entries. None of them waits for a running factory. A resolution that holds an old slot returns the instance created there, and that instance is not cached

**Cache slot** (`Locked<AnyCacheBox?>`, one for each singleton or custom-scoped entry)
- It holds `nil` until a factory succeeds, then the `CacheBox<S>` of the instance, with `S` the service type of the key. Read the instance back with a class cast to `CacheBox<S>`
- A factory that throws leaves the slot empty, and the next resolution runs the factory again
- Sendable entry: `resolveWithScope` holds the slot lock while the factory runs. Concurrent first resolutions wait, and the factory runs once
- The slot lock is not recursive. Locking it again on the same thread stops the process. Two rules prevent that within one task: the fast path skips the slot if `ServiceContext.isResolving` is true, and `resolveWithScope` runs only inside `withResolutionTracking`, which throws `circularDependency`. Another task on the same thread, run by a nested run loop inside the factory, is not covered
- MainActor entry: `resolveMainWithScope` holds the slot lock only to read or write the slot, because the main actor serializes creation. The slot holds `PendingBox.shared` while the factory runs. A resolution that finds the marker throws `circularDependency`

**Resolution** (`ServiceStorage.resolve` / `resolveMain`)
- Fast path: a cached instance is returned without `withResolutionTracking`, so without a cycle check and a depth count
- No instance on the resolution path is optional. `Optional<Service>` as a generic argument or result costs a metadata lookup at run time on every call, because this code is not specialized for the types of the caller

**Graph cache** (`ServiceContext.GraphCacheBox`)
- The first tracked resolution of a chain creates it and binds it task-locally
- A key is the storage and the service type, because a chain can resolve from more than one environment. The key retains the storage
- No lock is held while a factory runs. A replaced box is released after the lock

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
