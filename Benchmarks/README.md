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

Registration and the first resolution that fills the cache happen before measurement starts. All benchmarks share one `ServiceEnv(name: "bench")`.

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
| Library | `main` with #16 |

```
benchmark                                   wall p50 (ns)  wall min (ns)   instructions
resolve singleton (concrete)                        323.5          273.1           7130
resolve singleton (existential)                     318.4          275.4           7183
resolve transient                                   265.8          240.0           5937
resolve graph                                       419.1          368.9           9325
resolve custom scope                                330.5          275.1           7269
resolve nested (transient + 2 hits)                 723.0          638.4          15317
@Service cached                                      11.3           10.0            248
@Service first access                               467.8          426.5          11014
@Provider                                           321.5          289.0           7184
resolve singleton (8 threads)                      4424.9         2874.9          84690
resolveMain singleton                               333.8          314.4           7212
@MainService cached                                  29.6           28.3            765
@MainProvider                                       342.5          282.8           7264
control: mutex + dictionary + downcast               17.5           15.5            482
```
