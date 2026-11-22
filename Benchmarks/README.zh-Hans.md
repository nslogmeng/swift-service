# Benchmarks

<div align="center">
    <a href="./README.md"><strong>English</strong></a> | <strong>简体中文</strong>
</div>
<br/>

`Service` 解析路径的性能基准。本目录是独立的 package，只依赖 `Service`。它只使用公开 API 和 Swift 标准库。

## 运行

在仓库根目录执行。需要 Swift 6.2+，以及 macOS 15+ 或 Linux。

```bash
# 运行全部 benchmark
swift run -c release --package-path Benchmarks ServiceBenchmarks

# 只运行名称包含该参数的 benchmark
swift run -c release --package-path Benchmarks ServiceBenchmarks "resolve singleton"
```

一个样本执行 1000 次操作。每个 benchmark 先执行一个预热样本，再执行 1000 个样本（8 线程一行是 200 个）。每一列都是单次操作的数值：

| 列 | 含义 |
|----|------|
| `wall p50 (ns)` | 各样本 wall clock 时间的中位数 |
| `wall min (ns)` | 最快样本的 wall clock 时间 |
| `instructions` | 执行指令数的中位数，通过 `proc_pid_rusage` 读取。仅 macOS 支持，其他平台输出 `-` |

对比库的两个版本时，在两个版本上各运行一次，再比较输出。先比较 `instructions`，因为它不受机器负载影响。Wall clock 受负载影响：测量前关闭其他构建任务，只比较同一台机器上的结果。

## Benchmark 列表

注册和填充缓存的首次解析在计时开始前完成。除 `resolve graph` 外，所有 benchmark 共用一个 `ServiceEnv(name: "bench")`。`resolve graph` 使用独立的环境，因此共用环境中没有 graph 作用域的注册。

| Benchmark | 测量内容 |
|-----------|----------|
| `resolve singleton (concrete)` | `resolve` 已缓存的 `.singleton` struct |
| `resolve singleton (existential)` | `resolve` 以 `any Greeter`（`Greeter: Sendable`）注册的已缓存 `.singleton` |
| `resolve transient` | `resolve` 工厂函数极简的 `.transient` 服务 |
| `resolve graph` | 顶层 `resolve` 一个 `.graph` 服务 |
| `resolve custom scope` | `resolve` 已缓存的 `.custom("bench")` 服务 |
| `resolve nested (transient + 2 hits)` | `resolve` 一个 `.transient` 服务，其工厂函数再 `resolve` 两个已缓存的 singleton：共三次 `resolve` 调用，解析栈深度为 2 |
| `@Service cached` | 读取已持有值的 `@Service` 属性 |
| `@Service first access` | 构造带 `@Service` 属性的 holder 并读取一次；服务已缓存在环境中 |
| `@Provider` | 读取 `.singleton` 服务的 `@Provider` 属性 |
| `resolve singleton (8 threads)` | 8 个线程 `resolve` 同一个已缓存的 singleton，每个样本中各执行 1000 次。Wall clock 是每个线程完成一次 `resolve` 的时间。指令计数覆盖整个进程，因此 `instructions` 是 8 次操作的开销 |
| `resolveMain singleton` | 在 MainActor 上 `resolveMain` 已缓存的 `.singleton` |
| `@MainService cached` | 读取已持有值的 `@MainService` 属性 |
| `@MainProvider` | 读取 `.singleton` 服务的 `@MainProvider` 属性 |
| `control: mutex + dictionary + downcast` | 不经过 `Service`，用 `Mutex` 保护 `[ObjectIdentifier: any Sendable]` 做查找和 `as?` 转换。是 `resolve` 各行的下限 |

`resolve singleton (8 threads)` 用于观察锁竞争。它在各次运行间的波动比其他行大，并取决于机器的核心数。

## Baseline

| 项目 | 值 |
|------|----|
| 机器 | Apple M4 Max，16 核，128 GB |
| 系统 | macOS 27.0.1 (26A434) |
| Swift | 6.4.2 (swiftlang-6.4.2.1.9) |
| 库 | 合入 #21 后的 `main` |

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
