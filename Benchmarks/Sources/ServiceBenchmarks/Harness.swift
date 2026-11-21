//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

#if os(macOS)
import Darwin
#endif

/// The number of operations that one sample performs.
let operationsPerSample = 1_000

/// Measures benchmarks and prints one table row per benchmark.
///
/// A benchmark is a closure that performs `operationsPerSample` operations. The runner calls it once to warm up,
/// then once per sample, and reports each metric per operation.
struct BenchmarkRunner {
    /// Benchmarks whose name does not contain this text are skipped. `nil` runs every benchmark.
    private let filter: String?

    /// The instructions that one sample spends on reading the clock and the instruction counter.
    private let instructionOverhead: Double

    init(filter: String?) {
        self.filter = filter
        instructionOverhead = Self.collect(samples: 1_000) {}.instructions.median ?? 0
    }

    func printHeader() {
        printRow("benchmark", "wall p50 (ns)", "wall min (ns)", "instructions")
    }

    /// Runs `sample` once to warm up and then `samples` times, and prints the per-operation statistics.
    func measure(_ name: String, samples: Int = 1_000, sample: () throws -> Void) rethrows {
        if let filter, !name.contains(filter) { return }
        try sample()
        let (wall, instructions) = try Self.collect(samples: samples, sample: sample)
        let operations = Double(operationsPerSample)
        printRow(
            name,
            wall.median.map { oneDecimal($0 / operations) } ?? "-",
            wall.min().map { oneDecimal($0 / operations) } ?? "-",
            instructions.median.map { String(Int((($0 - instructionOverhead) / operations).rounded())) } ?? "-"
        )
    }

    /// Returns the wall clock time in nanoseconds and the retired instructions of each sample.
    /// `instructions` is empty where the platform has no instruction counter.
    private static func collect(
        samples: Int,
        sample: () throws -> Void
    ) rethrows -> (wall: [Double], instructions: [Double]) {
        var wall: [Double] = []
        var instructions: [Double] = []
        wall.reserveCapacity(samples)
        instructions.reserveCapacity(samples)
        let clock = ContinuousClock()
        for _ in 0..<samples {
            let instructionsBefore = instructionsRetired()
            let start = clock.now
            try sample()
            let elapsed = clock.now - start
            let instructionsAfter = instructionsRetired()
            let (seconds, attoseconds) = elapsed.components
            wall.append(Double(seconds) * 1e9 + Double(attoseconds) / 1e9)
            if let instructionsBefore, let instructionsAfter {
                instructions.append(Double(instructionsAfter - instructionsBefore))
            }
        }
        return (wall, instructions)
    }

    private func printRow(_ name: String, _ wallMedian: String, _ wallMin: String, _ instructions: String) {
        print(
            pad(name, to: 42, alignRight: false),
            pad(wallMedian, to: 14),
            pad(wallMin, to: 14),
            pad(instructions, to: 14)
        )
    }
}

/// The instructions retired by this process on all threads, or `nil` where the platform has no counter.
private func instructionsRetired() -> UInt64? {
    #if os(macOS)
    var info = rusage_info_v4()
    let status = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
            proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
        }
    }
    return status == 0 ? info.ri_instructions : nil
    #else
    return nil
    #endif
}

extension [Double] {
    fileprivate var median: Double? {
        isEmpty ? nil : sorted()[count / 2]
    }
}

/// Formats a non-negative value with one fraction digit.
private func oneDecimal(_ value: Double) -> String {
    let tenths = Int((value * 10).rounded())
    return "\(tenths / 10).\(tenths % 10)"
}

private func pad(_ text: String, to width: Int, alignRight: Bool = true) -> String {
    let padding = String(repeating: " ", count: max(0, width - text.count))
    return alignRight ? padding + text : text + padding
}
