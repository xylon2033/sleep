import Foundation

/// One night as seen by the n-of-1 analysis.
public struct NightObservation: Sendable, Equatable {
    /// The evening the night started on (used for experiment phases).
    public var nightOf: Date
    /// Free (weekend) vs work night, for the weekday adjustment.
    public var isFreeDay: Bool
    public var tags: Set<String>
    public var outcomes: [Outcome: Double]

    public init(nightOf: Date, isFreeDay: Bool, tags: Set<String>, outcomes: [Outcome: Double]) {
        self.nightOf = nightOf
        self.isFreeDay = isFreeDay
        self.tags = tags
        self.outcomes = outcomes
    }
}

public enum Outcome: String, CaseIterable, Codable, Sendable {
    case quality, mood, totalSleepHours, latencyMinutes, movementIndex, snoreMinutes

    public var label: String {
        switch self {
        case .quality: "Sleep quality (1–5)"
        case .mood: "Wake mood (1–5)"
        case .totalSleepHours: "Estimated sleep (h)"
        case .latencyMinutes: "Time to fall asleep (min)"
        case .movementIndex: "Movement index"
        case .snoreMinutes: "Snoring (min)"
        }
    }

    public var shortLabel: String {
        switch self {
        case .quality: "Quality"
        case .mood: "Mood"
        case .totalSleepHours: "Sleep"
        case .latencyMinutes: "Latency"
        case .movementIndex: "Movement"
        case .snoreMinutes: "Snoring"
        }
    }

    /// Whether a larger value is better (for colouring effects).
    public var higherIsBetter: Bool {
        switch self {
        case .quality, .mood, .totalSleepHours: true
        case .latencyMinutes, .movementIndex, .snoreMinutes: false
        }
    }
}

public struct TagEffect: Sendable, Equatable, Identifiable {
    public var tag: String
    public var outcome: Outcome
    public var withCount: Int
    public var withoutCount: Int
    public var meanWith: Double
    public var meanWithout: Double
    /// Weekday/weekend-stratified mean difference (with − without).
    public var difference: Double
    public var interval: Stats.Interval
    /// Hedges' g on the unstratified groups.
    public var effectSize: Double?
    /// Percentage of non-overlapping data (0…1).
    public var nonOverlap: Double?
    /// Bootstrap two-sided p (not shown as a headline).
    public var p: Double
    /// Benjamini–Hochberg adjusted p across the tags analysed for this outcome.
    public var q: Double
    /// Fewer than `provisionalBelow` nights in either group.
    public var isProvisional: Bool

    public var id: String { "\(tag)|\(outcome.rawValue)" }
    public var survivesFDR: Bool { q < 0.1 }
    /// Direction relative to "better".
    public var isBeneficial: Bool { outcome.higherIsBetter ? difference > 0 : difference < 0 }
}

public enum TagEffectAnalyzer {
    /// Compares nights with and without each tag for one outcome.
    ///
    /// - Nothing is reported until a tag has `minEach` nights with *and* without it.
    /// - Results with fewer than `provisionalBelow` nights in either group are flagged provisional.
    /// - The difference is stratified by free/work day, so weekend-clustered tags (alcohol, late
    ///   nights) aren't credited with the weekend's own effect.
    /// - p-values are FDR-adjusted (Benjamini–Hochberg); results are ranked by |effect size|.
    public static func analyze(observations: [NightObservation], outcome: Outcome, minEach: Int = 5,
                               provisionalBelow: Int = 10, iterations: Int = 2000) -> [TagEffect] {
        let usable = observations.filter { $0.outcomes[outcome] != nil }
        let allTags = Set(usable.flatMap(\.tags))
        var effects: [TagEffect] = []

        for tag in allTags.sorted() {
            let with = usable.filter { $0.tags.contains(tag) }
            let without = usable.filter { !$0.tags.contains(tag) }
            guard with.count >= minEach, without.count >= minEach else { continue }
            func values(_ obs: [NightObservation], free: Bool?) -> [Double] {
                obs.filter { free == nil || $0.isFreeDay == free }.compactMap { $0.outcomes[outcome] }
            }
            let groups = [values(with, free: true), values(without, free: true),
                          values(with, free: false), values(without, free: false)]
            guard let diff = stratifiedDifference(groups),
                  let boot = Stats.bootstrap(groups: groups, iterations: iterations,
                                             seed: UInt64(truncatingIfNeeded: tag.hashValueStable),
                                             statistic: stratifiedDifference) else { continue }
            let w = values(with, free: nil), wo = values(without, free: nil)
            effects.append(TagEffect(
                tag: tag, outcome: outcome, withCount: w.count, withoutCount: wo.count,
                meanWith: Stats.mean(w) ?? 0, meanWithout: Stats.mean(wo) ?? 0, difference: diff,
                interval: boot.interval, effectSize: Stats.hedgesG(w, wo), nonOverlap: Stats.pnd(w, wo),
                p: boot.p, q: 1, isProvisional: w.count < provisionalBelow || wo.count < provisionalBelow
            ))
        }
        let q = Stats.benjaminiHochberg(effects.map(\.p))
        for i in effects.indices { effects[i].q = q[i] }
        return effects.sorted { abs($0.effectSize ?? 0) > abs($1.effectSize ?? 0) }
    }

    /// groups = [freeWith, freeWithout, workWith, workWithout]. Each stratum that has both groups
    /// contributes its mean difference, weighted by nWith·nWithout / (nWith + nWithout).
    static func stratifiedDifference(_ groups: [[Double]]) -> Double? {
        var weighted = 0.0, weights = 0.0
        for s in stride(from: 0, to: groups.count, by: 2) {
            let a = groups[s], b = groups[s + 1]
            guard let ma = Stats.mean(a), let mb = Stats.mean(b) else { continue }
            let w = Double(a.count * b.count) / Double(a.count + b.count)
            weighted += (ma - mb) * w
            weights += w
        }
        return weights > 0 ? weighted / weights : nil
    }
}

extension String {
    /// FNV-1a: stable across launches (unlike `hashValue`), used to seed the bootstrap.
    var hashValueStable: UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in utf8 {
            h ^= UInt64(b)
            h = h &* 0x100_0000_01b3
        }
        return h
    }
}

// MARK: - Experiments

/// A self-experiment: the intervention is on in alternating weeks (SleepCoacher-style closed loop).
public struct SleepExperiment: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    /// What to do on intervention weeks, e.g. "No caffeine after 14:00".
    public var instruction: String
    public var start: Date
    /// Total length in weeks (even: half intervention, half control).
    public var weeks: Int
    public var startsWithIntervention: Bool
    public var outcome: Outcome

    public init(id: UUID = UUID(), title: String, instruction: String, start: Date, weeks: Int = 2,
                startsWithIntervention: Bool = true, outcome: Outcome = .quality) {
        self.id = id
        self.title = title
        self.instruction = instruction
        self.start = start
        self.weeks = weeks
        self.startsWithIntervention = startsWithIntervention
        self.outcome = outcome
    }

    public enum Phase: String, Sendable { case intervention, control }

    public func end(calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: weeks * 7, to: calendar.startOfDay(for: start)) ?? start
    }

    public func phase(on date: Date, calendar: Calendar = .current) -> Phase? {
        let startDay = calendar.startOfDay(for: start)
        guard let days = calendar.dateComponents([.day], from: startDay, to: calendar.startOfDay(for: date)).day,
              days >= 0, days < weeks * 7 else { return nil }
        let even = (days / 7) % 2 == 0
        return even == startsWithIntervention ? .intervention : .control
    }

    public func isFinished(at now: Date, calendar: Calendar = .current) -> Bool {
        now >= end(calendar: calendar)
    }

    public struct Result: Sendable, Equatable {
        public var interventionNights: Int
        public var controlNights: Int
        public var interventionMean: Double
        public var controlMean: Double
        public var difference: Double
        public var interval: Stats.Interval?
        public var effectSize: Double?
    }

    public func result(observations: [NightObservation], calendar: Calendar = .current) -> Result? {
        var on: [Double] = [], off: [Double] = []
        for o in observations {
            guard let v = o.outcomes[outcome], let p = phase(on: o.nightOf, calendar: calendar) else { continue }
            if p == .intervention { on.append(v) } else { off.append(v) }
        }
        guard let mOn = Stats.mean(on), let mOff = Stats.mean(off) else { return nil }
        let boot = Stats.bootstrap(groups: [on, off], seed: id.uuidString.hashValueStable) { g in
            guard let a = Stats.mean(g[0]), let b = Stats.mean(g[1]) else { return nil }
            return a - b
        }
        return Result(interventionNights: on.count, controlNights: off.count, interventionMean: mOn,
                      controlMean: mOff, difference: mOn - mOff, interval: boot?.interval,
                      effectSize: Stats.hedgesG(on, off))
    }
}
