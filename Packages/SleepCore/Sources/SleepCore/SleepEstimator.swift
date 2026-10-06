import Foundation

/// Per-epoch estimate. Deliberately *not* called REM/N3: audio actigraphy cannot stage sleep.
public enum EstimatedState: Int, Codable, Sendable, CaseIterable {
    case noData = -1
    case awake = 0
    case light = 1
    case deep = 2

    public var label: String {
        switch self {
        case .noData: "No data"
        case .awake: "Awake / restless"
        case .light: "Estimated light"
        case .deep: "Estimated deep"
        }
    }
}

/// A run of equal states, for charting.
public struct StateSegment: Codable, Sendable, Equatable {
    public var state: EstimatedState
    public var start: Date
    public var end: Date
    public init(state: EstimatedState, start: Date, end: Date) {
        self.state = state
        self.start = start
        self.end = end
    }
}

/// Everything the morning report and the trend metrics need for one night.
public struct NightSummary: Codable, Sendable, Equatable {
    public var inBedStart: Date
    public var inBedEnd: Date
    public var sleepOnset: Date?
    public var finalWake: Date?
    /// Estimated total sleep (seconds).
    public var totalSleep: TimeInterval
    /// Minutes from lights-out to estimated onset.
    public var latencyMinutes: Double?
    /// Estimated wake after sleep onset (minutes).
    public var wasoMinutes: Double
    public var wakeBouts: Int
    /// Estimated sleep / recorded time in bed. Low confidence.
    public var efficiency: Double?
    /// Mean activity across recorded epochs.
    public var movementIndex: Double
    public var snoreMinutes: Double
    public var eventCounts: [String: Int]
    public var gapMinutes: Double
    /// Fraction of time in bed that was actually recorded (0…1).
    public var coverage: Double
    public var segments: [StateSegment]

    public var timeInBed: TimeInterval { inBedEnd.timeIntervalSince(inBedStart) }
}

public struct SleepEstimatorConfig: Sendable, Equatable {
    /// Minimum smoothed activity treated as wake, regardless of the personal baseline.
    public var minWakeThreshold: Double = 2.0
    /// Wake threshold as a multiple of the night's median smoothed activity.
    public var relativeWakeThreshold: Double = 2.5
    /// Length of the quiet run that marks sleep onset (epochs). 30 × 30 s = 15 min.
    public var onsetRunEpochs: Int = 30
    /// A sleep run must be at least this long to count as the last sleep before final wake.
    public var finalSleepRunEpochs: Int = 6
    /// Epoch runs shorter than this are merged into their neighbours for light/deep labels.
    public var minDepthRunEpochs: Int = 6
    /// Fraction of sleep epochs (the quietest) labelled "estimated deep".
    public var deepFraction: Double = 0.35
    /// HMM probability of staying asleep from one epoch to the next.
    public var stayAsleep: Double = 0.99
    /// HMM probability of staying awake from one epoch to the next.
    public var stayAwake: Double = 0.95
    /// Weight multiplier for activity measured while the app played sleep sounds.
    public var playbackTrust: Double = 0.7

    public init() {}
}

/// Audio-actigraphy sleep/wake estimator.
///
/// 1. Lay recorded epochs on a regular 30 s grid; missing slots are gaps.
/// 2. Smooth activity with a weighted window (in the spirit of Cole–Kripke).
/// 3. Two-state HMM (Viterbi) over a logistic emission, so short blips don't flip the state.
/// 4. Sleep-onset rule (first sustained quiet run) and final-wake rule.
/// 5. Within sleep, the quietest stretches are labelled "estimated deep".
public struct SleepEstimator: Sendable {
    public var config: SleepEstimatorConfig

    public init(config: SleepEstimatorConfig = .init()) {
        self.config = config
    }

    static let smoothingWeights: [Double] = [0.04, 0.06, 0.10, 0.15, 0.30, 0.15, 0.10, 0.06, 0.04]

    public func summarize(epochs: [EpochFeatures], events: [SoundEvent], inBedStart: Date, inBedEnd: Date) -> NightSummary {
        let slotCount = max(0, Int((inBedEnd.timeIntervalSince(inBedStart) / epochDuration).rounded(.down)))
        var grid = [EpochFeatures?](repeating: nil, count: slotCount)
        for epoch in epochs {
            let index = Int((epoch.start.timeIntervalSince(inBedStart) / epochDuration).rounded())
            if index >= 0, index < slotCount { grid[index] = epoch }
        }
        let states = classify(grid: grid)
        return buildSummary(grid: grid, states: states, events: events, inBedStart: inBedStart, inBedEnd: inBedEnd)
    }

    // MARK: - Classification

    /// Weighted, gap-aware moving average of activity.
    func smoothedActivity(grid: [EpochFeatures?]) -> [Double?] {
        let weights = Self.smoothingWeights
        let half = weights.count / 2
        return grid.indices.map { i in
            guard grid[i] != nil else { return nil }
            var sum = 0.0, weightSum = 0.0
            for (k, w) in weights.enumerated() {
                let j = i + k - half
                guard j >= 0, j < grid.count, let e = grid[j] else { continue }
                let trust = e.soundPlaying ? config.playbackTrust : 1
                sum += e.activity * trust * w
                weightSum += w
            }
            return weightSum > 0 ? sum / weightSum : nil
        }
    }

    func wakeThreshold(for smoothed: [Double?]) -> Double {
        let values = smoothed.compactMap { $0 }
        guard let med = Stats.median(values) else { return config.minWakeThreshold }
        return max(config.minWakeThreshold, med * config.relativeWakeThreshold)
    }

    public func classify(grid: [EpochFeatures?]) -> [EstimatedState] {
        guard !grid.isEmpty else { return [] }
        let smoothed = smoothedActivity(grid: grid)
        let threshold = wakeThreshold(for: smoothed)

        // Viterbi over {0: asleep, 1: awake}.
        let logStay = [log(config.stayAsleep), log(config.stayAwake)]
        let logSwitch = [log(1 - config.stayAsleep), log(1 - config.stayAwake)]
        func emission(_ s: Double?) -> [Double] {
            guard let s else { return [log(0.5), log(0.5)] }
            let pAwake = 1 / (1 + exp(-(s - threshold) / max(0.25, threshold * 0.25)))
            let p = min(max(pAwake, 0.001), 0.999)
            return [log(1 - p), log(p)]
        }
        // Lights-out: most likely still awake.
        let first = emission(smoothed[0])
        var score = [log(0.1) + first[0], log(0.9) + first[1]]
        var back = [[Int]](repeating: [0, 0], count: grid.count)
        for t in 1..<grid.count {
            let e = emission(smoothed[t])
            var next = [0.0, 0.0]
            for to in 0..<2 {
                let fromSame = score[to] + logStay[to]
                let other = 1 - to
                let fromOther = score[other] + logSwitch[other]
                if fromSame >= fromOther {
                    next[to] = fromSame + e[to]
                    back[t][to] = to
                } else {
                    next[to] = fromOther + e[to]
                    back[t][to] = other
                }
            }
            score = next
        }
        var path = [Int](repeating: 1, count: grid.count)
        path[grid.count - 1] = score[0] >= score[1] ? 0 : 1
        if grid.count > 1 {
            for t in stride(from: grid.count - 1, to: 0, by: -1) {
                path[t - 1] = back[t][path[t]]
            }
        }

        var asleep = path.map { $0 == 0 }
        // Gaps are never asleep or awake.
        for i in grid.indices where grid[i] == nil { asleep[i] = false }

        // Sleep-onset rule: first sustained run of sleep.
        guard let onset = firstRun(of: true, in: asleep, minLength: config.onsetRunEpochs, gaps: grid) else {
            return grid.map { $0 == nil ? .noData : .awake }
        }
        // Final-wake rule: end of the last sleep run of reasonable length.
        let lastSleep = lastRunEnd(of: true, in: asleep, minLength: config.finalSleepRunEpochs, from: onset) ?? onset

        var states: [EstimatedState] = grid.indices.map { i in
            if grid[i] == nil { return .noData }
            if i < onset || i > lastSleep { return .awake }
            return asleep[i] ? .light : .awake
        }
        labelDepth(states: &states, grid: grid)
        return states
    }

    /// Index of the first run of `value` with at least `minLength` epochs (gaps break runs).
    func firstRun(of value: Bool, in flags: [Bool], minLength: Int, gaps: [EpochFeatures?]) -> Int? {
        var runStart: Int?
        for i in flags.indices {
            if flags[i] == value, gaps[i] != nil {
                if runStart == nil { runStart = i }
                if let s = runStart, i - s + 1 >= minLength { return s }
            } else {
                runStart = nil
            }
        }
        return nil
    }

    /// Last index of the final run of `value` (length ≥ minLength) at or after `from`.
    func lastRunEnd(of value: Bool, in flags: [Bool], minLength: Int, from: Int) -> Int? {
        var result: Int?
        var i = from
        while i < flags.count {
            if flags[i] == value {
                var j = i
                while j + 1 < flags.count, flags[j + 1] == value { j += 1 }
                if j - i + 1 >= minLength || result == nil { result = j }
                i = j + 1
            } else {
                i += 1
            }
        }
        return result
    }

    /// Splits sleep into estimated light/deep by how quiet the surrounding ~10 minutes were.
    func labelDepth(states: inout [EstimatedState], grid: [EpochFeatures?]) {
        let window = 10
        var quietness = [Double?](repeating: nil, count: grid.count)
        for i in grid.indices where states[i] == .light {
            var sum = 0.0, n = 0.0
            for j in max(0, i - window)...min(grid.count - 1, i + window) {
                if let e = grid[j] { sum += e.activity; n += 1 }
            }
            quietness[i] = n > 0 ? sum / n : nil
        }
        let sleepValues = quietness.compactMap { $0 }
        guard sleepValues.count >= config.minDepthRunEpochs,
              let cutoff = Stats.quantile(sleepValues, config.deepFraction) else { return }
        for i in grid.indices where states[i] == .light {
            if let q = quietness[i], q <= cutoff { states[i] = .deep }
        }
        // Merge very short deep/light runs into the surrounding state.
        var i = 0
        while i < states.count {
            let s = states[i]
            var j = i
            while j + 1 < states.count, states[j + 1] == s { j += 1 }
            if (s == .deep || s == .light), j - i + 1 < config.minDepthRunEpochs {
                let before = i > 0 ? states[i - 1] : nil
                let after = j + 1 < states.count ? states[j + 1] : nil
                let replacement: EstimatedState? = {
                    for candidate in [before, after] {
                        if let c = candidate, c == .light || c == .deep, c != s { return c }
                    }
                    return nil
                }()
                if let r = replacement { for k in i...j { states[k] = r } }
            }
            i = j + 1
        }
    }

    // MARK: - Summary

    func buildSummary(grid: [EpochFeatures?], states: [EstimatedState], events: [SoundEvent],
                      inBedStart: Date, inBedEnd: Date) -> NightSummary {
        func date(_ i: Int) -> Date { inBedStart.addingTimeInterval(Double(i) * epochDuration) }
        let sleepIdx = states.indices.filter { states[$0] == .light || states[$0] == .deep }
        let onsetIdx = sleepIdx.first
        let wakeIdx = sleepIdx.last
        let recorded = grid.compactMap { $0 }
        let gapSlots = grid.filter { $0 == nil }.count
        // Tail beyond the last full slot is not a gap.
        let gapMinutes = Double(gapSlots) * epochDuration / 60
        let recordedSeconds = Double(grid.count - gapSlots) * epochDuration

        var wasoEpochs = 0
        var bouts = 0
        if let a = onsetIdx, let b = wakeIdx, a < b {
            var inBout = false
            var boutLength = 0
            for i in a...b {
                if states[i] == .awake {
                    wasoEpochs += 1
                    boutLength += 1
                    if !inBout { inBout = true }
                } else {
                    if inBout, boutLength >= 2 { bouts += 1 }
                    inBout = false
                    boutLength = 0
                }
            }
        }

        var counts: [String: Int] = [:]
        for e in events { counts[e.kind.rawValue, default: 0] += 1 }
        let snoreSeconds = events.filter { $0.kind == .snoring }.reduce(0) { $0 + $1.duration }

        let totalSleep = Double(sleepIdx.count) * epochDuration
        return NightSummary(
            inBedStart: inBedStart,
            inBedEnd: inBedEnd,
            sleepOnset: onsetIdx.map(date),
            finalWake: wakeIdx.map { date($0 + 1) },
            totalSleep: totalSleep,
            latencyMinutes: onsetIdx.map { Double($0) * epochDuration / 60 },
            wasoMinutes: Double(wasoEpochs) * epochDuration / 60,
            wakeBouts: bouts,
            efficiency: recordedSeconds > 0 ? totalSleep / recordedSeconds : nil,
            movementIndex: recorded.isEmpty ? 0 : recorded.map(\.activity).reduce(0, +) / Double(recorded.count),
            snoreMinutes: snoreSeconds / 60,
            eventCounts: counts,
            gapMinutes: gapMinutes,
            coverage: grid.isEmpty ? 0 : Double(grid.count - gapSlots) / Double(grid.count),
            segments: Self.segments(states: states, start: inBedStart)
        )
    }

    public static func segments(states: [EstimatedState], start: Date) -> [StateSegment] {
        var result: [StateSegment] = []
        var i = 0
        while i < states.count {
            var j = i
            while j + 1 < states.count, states[j + 1] == states[i] { j += 1 }
            result.append(StateSegment(state: states[i],
                                       start: start.addingTimeInterval(Double(i) * epochDuration),
                                       end: start.addingTimeInterval(Double(j + 1) * epochDuration)))
            i = j + 1
        }
        return result
    }

    /// Summary for a night logged by hand (no audio): bed/wake times only.
    public static func manualSummary(inBed: Date, outOfBed: Date, latencyMinutes: Double?) -> NightSummary {
        let latency = latencyMinutes ?? 0
        let onset = inBed.addingTimeInterval(latency * 60)
        let sleep = max(0, outOfBed.timeIntervalSince(onset))
        return NightSummary(
            inBedStart: inBed, inBedEnd: outOfBed, sleepOnset: onset, finalWake: outOfBed,
            totalSleep: sleep, latencyMinutes: latencyMinutes, wasoMinutes: 0, wakeBouts: 0,
            efficiency: nil, movementIndex: 0, snoreMinutes: 0, eventCounts: [:], gapMinutes: 0,
            coverage: 0, segments: [StateSegment(state: .light, start: onset, end: outOfBed)]
        )
    }
}

/// Smart-wake trigger: "sustained movement in 2 of the last 3 epochs".
public struct SmartWakeDetector: Sendable {
    public var requiredActive: Int
    public var lookback: Int
    public var minActivity: Double

    public init(requiredActive: Int = 2, lookback: Int = 3, minActivity: Double = 1.5) {
        self.requiredActive = requiredActive
        self.lookback = lookback
        self.minActivity = minActivity
    }

    /// Personalised threshold: stirring means clearly above this night's typical quiet level.
    public func threshold(nightSoFar: [EpochFeatures]) -> Double {
        let median = Stats.median(nightSoFar.map(\.activity)) ?? 0
        return max(minActivity, median * 2)
    }

    public func shouldWake(recent: [EpochFeatures], nightSoFar: [EpochFeatures]) -> Bool {
        let window = recent.suffix(lookback)
        guard window.count == lookback else { return false }
        let t = threshold(nightSoFar: nightSoFar)
        return window.filter { $0.activity >= t }.count >= requiredActive
    }
}
