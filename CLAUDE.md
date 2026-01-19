# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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

**Property Wrappers** (`Service.swift`)
- `@Service<S: Sendable>` - Thread-safe service injection
- `@MainService<S>` - MainActor-isolated service injection (for UI components)

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

### Thread Safety

- `@Locked` property wrapper (`Utils/Lock.swift`) uses Swift's `Synchronization.Mutex`
- Sendable services: mutex-based thread-safe access
- MainActor services: actor isolation (no locking needed)

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
