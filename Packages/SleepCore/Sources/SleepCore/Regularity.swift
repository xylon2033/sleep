import Foundation

/// A night reduced to the times the trend metrics need.
public struct SleepPeriod: Sendable, Equatable {
    public var bedtime: Date
    public var sleepOnset: Date
    public var wake: Date
    public var outOfBed: Date
    /// Epoch-level asleep intervals if the night was tracked; nil → onset…wake is treated as asleep.
    public var asleepIntervals: [DateInterval]?
    /// Late-shift nights are their own category for social jetlag.
    public var isShift: Bool

    public init(bedtime: Date, sleepOnset: Date, wake: Date, outOfBed: Date,
                asleepIntervals: [DateInterval]? = nil, isShift: Bool = false) {
        self.bedtime = bedtime
        self.sleepOnset = sleepOnset
        self.wake = wake
        self.outOfBed = outOfBed
        self.asleepIntervals = asleepIntervals
        self.isShift = isShift
    }

    public var sleepDuration: TimeInterval {
        if let intervals = asleepIntervals { return intervals.reduce(0) { $0 + $1.duration } }
        return max(0, wake.timeIntervalSince(sleepOnset))
    }

    public var midSleep: Date { sleepOnset.addingTimeInterval(wake.timeIntervalSince(sleepOnset) / 2) }

    /// Intervals actually counted as asleep.
    public var asleep: [DateInterval] {
        asleepIntervals ?? (wake > sleepOnset ? [DateInterval(start: sleepOnset, end: wake)] : [])
    }
}

public enum Regularity {
    // MARK: Sleep Regularity Index

    public struct SRIResult: Sendable, Equatable {
        /// −100 (perfectly reversed) … 100 (identical every day). UK Biobank median ≈ 81.
        public var value: Double
        /// Number of 24 h day pairs that contributed.
        public var dayPairs: Int
    }

    /// Sleep Regularity Index (Phillips et al. 2017): the probability of being in the same
    /// state at two time points 24 h apart, scaled to −100…100. Only pairs of noon-to-noon
    /// days that both contain a recorded night are compared, so unlogged nights don't count as "awake".
    public static func sleepRegularityIndex(periods: [SleepPeriod], resolution: TimeInterval = 300,
                                            calendar: Calendar = .current, minDayPairs: Int = 1) -> SRIResult? {
        guard let first = periods.map(\.sleepOnset).min() else { return nil }
        let origin = noonOnOrBefore(first, calendar: calendar)
        let slotsPerDay = Int(86_400 / resolution)

        var covered = Set<Int>()
        for p in periods {
            covered.insert(dayIndex(of: p.sleepOnset, origin: origin))
        }
        guard let lastDay = covered.max() else { return nil }
        var asleep = [Bool](repeating: false, count: (lastDay + 2) * slotsPerDay)
        for p in periods {
            for interval in p.asleep {
                let startSlot = max(0, Int((interval.start.timeIntervalSince(origin) / resolution).rounded(.up)))
                let endSlot = min(asleep.count, Int((interval.end.timeIntervalSince(origin) / resolution).rounded(.down)))
                if startSlot < endSlot { for s in startSlot..<endSlot { asleep[s] = true } }
            }
        }
        var same = 0, total = 0, pairs = 0
        for day in covered.sorted() where covered.contains(day + 1) {
            pairs += 1
            let base = day * slotsPerDay
            for s in 0..<slotsPerDay {
                let a = base + s, b = base + s + slotsPerDay
                guard b < asleep.count else { continue }
                total += 1
                if asleep[a] == asleep[b] { same += 1 }
            }
        }
        guard pairs >= minDayPairs, total > 0 else { return nil }
        return SRIResult(value: -100 + 200 * Double(same) / Double(total), dayPairs: pairs)
    }

    static func noonOnOrBefore(_ date: Date, calendar: Calendar) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let noon = calendar.date(byAdding: .hour, value: 12, to: startOfDay)!
        return noon <= date ? noon : calendar.date(byAdding: .day, value: -1, to: noon)!
    }

    static func dayIndex(of date: Date, origin: Date) -> Int {
        Int((date.timeIntervalSince(origin) / 86_400).rounded(.down))
    }

    // MARK: Social jetlag

    public struct SocialJetlag: Sendable, Equatable {
        /// |MSF − MSW| in hours.
        public var hours: Double
        /// Mean mid-sleep, hours relative to midnight of the wake day (negative = before midnight).
        public var freeMidSleep: Double
        public var workMidSleep: Double
        public var freeNights: Int
        public var workNights: Int
    }

    /// Social jetlag (Wittmann et al. 2006): difference in mid-sleep between free and work days.
    /// A night is "free" when the day you wake up on is a free day (default Sat/Sun → Fri & Sat nights).
    /// `freeWeekdays` uses Calendar weekday numbers (1 = Sunday … 7 = Saturday). Shift nights are excluded.
    public static func socialJetlag(periods: [SleepPeriod], freeWeekdays: Set<Int>,
                                    calendar: Calendar = .current, minNightsEach: Int = 2) -> SocialJetlag? {
        var free: [Double] = [], work: [Double] = []
        for p in periods where !p.isShift {
            let mid = midSleepHours(p, calendar: calendar)
            if freeWeekdays.contains(calendar.component(.weekday, from: p.wake)) {
                free.append(mid)
            } else {
                work.append(mid)
            }
        }
        guard free.count >= minNightsEach, work.count >= minNightsEach,
              let f = Stats.mean(free), let w = Stats.mean(work) else { return nil }
        return SocialJetlag(hours: abs(f - w), freeMidSleep: f, workMidSleep: w,
                            freeNights: free.count, workNights: work.count)
    }

    /// Mid-sleep in hours relative to midnight at the start of the wake day.
    public static func midSleepHours(_ p: SleepPeriod, calendar: Calendar = .current) -> Double {
        let midnight = calendar.startOfDay(for: p.wake)
        return p.midSleep.timeIntervalSince(midnight) / 3600
    }

    // MARK: Clock-time helpers

    /// Minutes since the most recent `pivotHour`:00 before `date`. With pivot 12, a 23:30 bedtime
    /// is 690 and a 00:30 bedtime is 750, so averages don't break across midnight.
    public static func clockMinutes(_ date: Date, pivotHour: Int, calendar: Calendar = .current) -> Double {
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        let minutes = Double((c.hour ?? 0) * 60 + (c.minute ?? 0)) + Double(c.second ?? 0) / 60
        var m = minutes - Double(pivotHour * 60)
        if m < 0 { m += 1440 }
        return m
    }

    /// Converts minutes-after-pivot back to minutes after midnight (0..<1440).
    public static func minutesAfterMidnight(fromPivoted m: Double, pivotHour: Int) -> Double {
        var v = (m + Double(pivotHour * 60)).truncatingRemainder(dividingBy: 1440)
        if v < 0 { v += 1440 }
        return v
    }

    public struct Variability: Sendable, Equatable {
        /// Standard deviation of bedtimes, minutes.
        public var bedtimeSD: Double
        /// Standard deviation of wake times, minutes.
        public var wakeSD: Double
        /// Earliest to latest wake time, minutes.
        public var wakeRange: Double
        public var nights: Int
    }

    public static func variability(periods: [SleepPeriod], calendar: Calendar = .current) -> Variability? {
        guard periods.count >= 2 else { return nil }
        let beds = periods.map { clockMinutes($0.bedtime, pivotHour: 12, calendar: calendar) }
        let wakes = periods.map { clockMinutes($0.wake, pivotHour: 18, calendar: calendar) }
        guard let b = Stats.standardDeviation(beds), let w = Stats.standardDeviation(wakes),
              let lo = wakes.min(), let hi = wakes.max() else { return nil }
        return Variability(bedtimeSD: b, wakeSD: w, wakeRange: hi - lo, nights: periods.count)
    }

    // MARK: Debt and streaks

    /// Shortfall versus the goal over the given nights, in minutes (surplus nights offset at most
    /// half their surplus, and the total never goes below zero).
    public static func sleepDebtMinutes(periods: [SleepPeriod], goalMinutes: Double) -> Double {
        let debt = periods.reduce(0.0) { acc, p in
            let diff = goalMinutes - p.sleepDuration / 60
            return acc + (diff > 0 ? diff : diff / 2)
        }
        return max(0, debt)
    }

    /// Consecutive most-recent nights with bedtime and wake within `tolerance` minutes of target.
    /// Targets are minutes after midnight.
    public static func onScheduleStreak(periods: [SleepPeriod], targetBedMinutes: Double, targetWakeMinutes: Double,
                                        toleranceMinutes: Double = 30, calendar: Calendar = .current) -> Int {
        let bedTarget = clockMinutes(fromMidnight: targetBedMinutes, pivotHour: 12)
        let wakeTarget = clockMinutes(fromMidnight: targetWakeMinutes, pivotHour: 18)
        var streak = 0
        for p in periods.sorted(by: { $0.bedtime > $1.bedtime }) {
            let bed = clockMinutes(p.bedtime, pivotHour: 12, calendar: calendar)
            let wake = clockMinutes(p.wake, pivotHour: 18, calendar: calendar)
            if abs(bed - bedTarget) <= toleranceMinutes, abs(wake - wakeTarget) <= toleranceMinutes {
                streak += 1
            } else {
                break
            }
        }
        return streak
    }

    /// Minutes after midnight → minutes after the pivot hour.
    public static func clockMinutes(fromMidnight m: Double, pivotHour: Int) -> Double {
        var v = m - Double(pivotHour * 60)
        if v < 0 { v += 1440 }
        return v
    }
}
