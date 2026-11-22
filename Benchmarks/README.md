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
| Library | `main` with #20 |

```
benchmark                                   wall p50 (ns)  wall min (ns)   instructions
resolve singleton (concrete)                         58.0           52.3           1380
resolve singleton (existential)                      55.8           51.1           1370
resolve transient                                   249.8          238.3           5937
resolve graph                                       365.6          345.1           8980
resolve custom scope                                 54.3           53.6           1331
resolve nested (transient + 2 hits)                 378.9          345.5           8820
@Service cached                                      10.5           10.4            248
@Service first access                               199.1          187.1           5370
@Provider                                            56.3           54.0           1374
resolve singleton (8 threads)                      2155.3         1874.8          26626
resolveMain singleton                                53.8           52.0           1372
@MainService cached                                  26.1           25.4            766
@MainProvider                                        60.9           56.5           1424
control: mutex + dictionary + downcast               15.2           15.0            483
```
