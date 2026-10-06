import Foundation

public enum Stats {
    public static func mean(_ x: [Double]) -> Double? {
        x.isEmpty ? nil : x.reduce(0, +) / Double(x.count)
    }

    /// Sample standard deviation (n − 1).
    public static func standardDeviation(_ x: [Double]) -> Double? {
        guard x.count > 1, let m = mean(x) else { return nil }
        let ss = x.reduce(0) { $0 + ($1 - m) * ($1 - m) }
        return (ss / Double(x.count - 1)).squareRoot()
    }

    public static func median(_ x: [Double]) -> Double? {
        quantile(x, 0.5)
    }

    /// Linear-interpolated quantile (type 7), q in 0…1.
    public static func quantile(_ x: [Double], _ q: Double) -> Double? {
        guard !x.isEmpty else { return nil }
        let s = x.sorted()
        let pos = min(max(q, 0), 1) * Double(s.count - 1)
        let lo = Int(pos.rounded(.down))
        let hi = min(lo + 1, s.count - 1)
        let frac = pos - Double(lo)
        return s[lo] + (s[hi] - s[lo]) * frac
    }

    /// Hedges' g (bias-corrected standardised mean difference), a − b.
    public static func hedgesG(_ a: [Double], _ b: [Double]) -> Double? {
        guard a.count > 1, b.count > 1, let ma = mean(a), let mb = mean(b),
              let sa = standardDeviation(a), let sb = standardDeviation(b) else { return nil }
        let na = Double(a.count), nb = Double(b.count)
        let pooled = (((na - 1) * sa * sa + (nb - 1) * sb * sb) / (na + nb - 2)).squareRoot()
        guard pooled > 0 else { return nil }
        let correction = 1 - 3 / (4 * (na + nb) - 9)
        return (ma - mb) / pooled * correction
    }

    /// Percentage of non-overlapping data: share of `a` values beyond the most extreme `b` value
    /// in the direction of the mean difference (single-case design statistic).
    public static func pnd(_ a: [Double], _ b: [Double]) -> Double? {
        guard !a.isEmpty, let ma = mean(a), let mb = mean(b), let maxB = b.max(), let minB = b.min() else { return nil }
        let beyond = ma >= mb ? a.filter { $0 > maxB }.count : a.filter { $0 < minB }.count
        return Double(beyond) / Double(a.count)
    }

    /// Benjamini–Hochberg adjusted p-values (same order as input).
    public static func benjaminiHochberg(_ p: [Double]) -> [Double] {
        let m = Double(p.count)
        let order = p.indices.sorted { p[$0] < p[$1] }
        var adjusted = [Double](repeating: 1, count: p.count)
        var running = 1.0
        for rank in stride(from: order.count - 1, through: 0, by: -1) {
            let i = order[rank]
            running = min(running, p[i] * m / Double(rank + 1))
            adjusted[i] = min(1, running)
        }
        return adjusted
    }
}

/// Small deterministic PRNG so bootstrap results don't jump around between app launches.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

public extension Stats {
    struct Interval: Sendable, Equatable, Codable {
        public var low: Double
        public var high: Double
        public init(low: Double, high: Double) {
            self.low = low
            self.high = high
        }
        public var containsZero: Bool { low <= 0 && high >= 0 }
    }

    /// Bootstrap (percentile) CI and two-sided p-value for a statistic over resampled groups.
    /// `statistic` gets resampled copies of every group, in the same order as `groups`
    /// (empty groups stay empty; the statistic may return nil for a degenerate resample).
    static func bootstrap(groups: [[Double]], iterations: Int = 2000, seed: UInt64 = 42,
                          confidence: Double = 0.95,
                          statistic: ([[Double]]) -> Double?) -> (interval: Interval, p: Double)? {
        guard groups.contains(where: { !$0.isEmpty }) else { return nil }
        var rng = SplitMix64(seed: seed)
        var samples: [Double] = []
        samples.reserveCapacity(iterations)
        for _ in 0..<iterations {
            let resampled = groups.map { g -> [Double] in
                g.isEmpty ? [] : (0..<g.count).map { _ in g[Int.random(in: 0..<g.count, using: &rng)] }
            }
            if let s = statistic(resampled) { samples.append(s) }
        }
        guard samples.count >= iterations / 2,
              let lo = quantile(samples, (1 - confidence) / 2),
              let hi = quantile(samples, 1 - (1 - confidence) / 2) else { return nil }
        let below = Double(samples.filter { $0 <= 0 }.count) / Double(samples.count)
        let above = Double(samples.filter { $0 >= 0 }.count) / Double(samples.count)
        let p = min(1, 2 * min(below, above))
        return (Interval(low: lo, high: hi), p)
    }
}
