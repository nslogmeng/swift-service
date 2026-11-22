# Benchmarks

<div align="center">
    <strong>English</strong> | <a href="./README.zh-Hans.md"><strong>简体中文</strong></a>
</div>
<br/>

Benchmarks for the resolution paths of `Service`. This is a separate package that depends only on `Service`. It uses the public API and the Swift standard library.

## Running

Run from the repository root. Requires Swift 6.2+ and macOS 15+ or Linux.

```bash
# Run all benchmarks
swift run -c release --package-path Benchmarks ServiceBenchmarks

# Run the benchmarks whose name contains the argument
swift run -c release --package-path Benchmarks ServiceBenchmarks "resolve singleton"
```

One sample performs 1,000 operations. Each benchmark runs one warm-up sample and then 1,000 samples (200 for the 8-thread row). Every column is per operation:

| Column | Meaning |
|--------|---------|
| `wall p50 (ns)` | Median wall clock time of the samples |
| `wall min (ns)` | Wall clock time of the fastest sample |
| `instructions` | Median number of retired instructions, read with `proc_pid_rusage`. macOS only; other platforms print `-` |

To compare two versions of the library, run the benchmarks on each and compare the output. Compare `instructions` first, because it does not depend on machine load. Wall clock does: close other builds before measuring, and compare only runs from the same machine.

## Benchmarks

Registration and the first resolution that fills the cache happen before measurement starts. All benchmarks share one `ServiceEnv(name: "bench")`, except `resolve graph`. That benchmark uses its own environment, so the shared one has no graph-scoped registration.

| Benchmark | Measures |
|-----------|----------|
| `resolve singleton (concrete)` | `resolve` of a cached `.singleton` struct |
| `resolve singleton (existential)` | `resolve` of a cached `.singleton` registered as `any Greeter` (`Greeter: Sendable`) |
| `resolve transient` | `resolve` of a `.transient` service with a trivial factory |
| `resolve graph` | Top-level `resolve` of a `.graph` service |
| `resolve custom scope` | `resolve` of a cached `.custom("bench")` service |
| `resolve nested (transient + 2 hits)` | `resolve` of a `.transient` service whose factory calls `resolve` for two cached singletons: three `resolve` calls, resolution stack depth 2 |
| `@Service cached` | Property read on a `@Service` that already holds its value |
| `@Service first access` | Constructing a holder with a `@Service` property and reading it once; the service is already cached in the environment |
| `@Provider` | Property read on a `@Provider` for a `.singleton` service |
| `resolve singleton (8 threads)` | 8 threads resolving the same cached singleton, 1,000 times each per sample. Wall clock is the time in which each thread completes one `resolve`. The instruction counter covers the whole process, so `instructions` is the cost of 8 operations |
| `resolveMain singleton` | `resolveMain` of a cached `.singleton`, on the main actor |
| `@MainService cached` | Property read on a `@MainService` that already holds its value |
| `@MainProvider` | Property read on a `@MainProvider` for a `.singleton` service |
| `control: mutex + dictionary + downcast` | `Mutex`-protected `[ObjectIdentifier: any Sendable]` lookup and `as?` cast, without `Service`. Lower bound for the `resolve` rows |

`resolve singleton (8 threads)` indicates lock contention. It varies more between runs than the other rows and depends on the core count of the machine.

## Baseline

| Item | Value |
|------|-------|
| Machine | Apple M4 Max, 16 cores, 128 GB |
| OS | macOS 27.0.1 (26A434) |
| Swift | 6.4.2 (swiftlang-6.4.2.1.9) |
| Library | `main` with #21 |

```
benchmark                                   wall p50 (ns)  wall min (ns)   instructions
resolve singleton (concrete)                         56.7           51.8           1392
resolve singleton (existential)                      56.3           54.6           1392
resolve transient                                   143.2          139.2           3348
resolve graph                                       363.4          341.7           8994
resolve custom scope                                 56.8           55.4           1356
resolve nested (transient + 2 hits)                 259.0          245.4           6118
@Service cached                                      10.0            9.9            248
@Service first access                               197.3          185.3           5382
@Provider                                            56.3           54.5           1386
resolve singleton (8 threads)                      2176.0         1816.3          26354
resolveMain singleton                                54.1           52.5           1384
@MainService cached                                  24.8           24.5            766
@MainProvider                                        56.3           55.1           1436
control: mutex + dictionary + downcast               15.1           15.0            483
```
