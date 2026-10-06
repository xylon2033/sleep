import Foundation
import SleepCore

/// Bridges stored records to the SleepCore metrics.
struct Analytics {
    let nights: [NightRecord]
    let journals: [String: JournalRecord]
    let schedule: SleepSchedule

    init(nights: [NightRecord], journals: [JournalRecord], schedule: SleepSchedule) {
        self.nights = nights.filter { !$0.isInProgress && $0.summary != nil }.sorted { $0.inBedStart < $1.inBedStart }
        var byKey: [String: JournalRecord] = [:]
        for j in journals { byKey[j.nightKey] = j }
        self.journals = byKey
        self.schedule = schedule
    }

    func journal(for night: NightRecord) -> JournalRecord? { journals[night.nightKey] }

    func isShift(_ night: NightRecord) -> Bool { journal(for: night)?.isLateShift ?? false }

    func isFreeDay(_ night: NightRecord) -> Bool {
        switch night.dayTypeOverride {
        case "free": return true
        case "work": return false
        default:
            let wake = night.inBedEnd ?? night.inBedStart
            return schedule.freeWeekdays.contains(Calendar.current.component(.weekday, from: wake))
        }
    }

    func recent(days: Int, before now: Date = Date()) -> [NightRecord] {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        return nights.filter { $0.inBedStart >= cutoff }
    }

    func periods(_ records: [NightRecord]) -> [SleepPeriod] {
        records.compactMap { $0.sleepPeriod(isShift: isShift($0)) }
    }

    // MARK: Headline metrics

    struct Snapshot {
        var nights: Int
        var sri: Regularity.SRIResult?
        var socialJetlag: Regularity.SocialJetlag?
        var variability: Regularity.Variability?
        var averageSleep: TimeInterval?
        var debtMinutes: Double
        var streak: Int
    }

    func snapshot(days: Int) -> Snapshot {
        let records = recent(days: days)
        let p = periods(records)
        let durations = p.map(\.sleepDuration)
        return Snapshot(
            nights: records.count,
            sri: p.count >= 7 ? Regularity.sleepRegularityIndex(periods: p) : nil,
            socialJetlag: Regularity.socialJetlag(periods: p, freeWeekdays: schedule.freeWeekdays),
            variability: Regularity.variability(periods: p),
            averageSleep: Stats.mean(durations),
            debtMinutes: Regularity.sleepDebtMinutes(periods: Array(p.suffix(7)), goalMinutes: Double(schedule.sleepGoalMinutes)),
            streak: Regularity.onScheduleStreak(periods: p, targetBedMinutes: Double(schedule.targetBedtimeMinutes),
                                                targetWakeMinutes: Double(schedule.wakeMinutes))
        )
    }

    // MARK: Journal analysis

    func observations() -> [NightObservation] {
        nights.compactMap { night in
            guard let summary = night.summary else { return nil }
            let journal = journal(for: night)
            var outcomes: [Outcome: Double] = [:]
            if let c = journal?.checkIn {
                outcomes[.quality] = Double(c.quality)
                outcomes[.mood] = Double(c.mood)
                outcomes[.latencyMinutes] = c.latency.minutes
            } else if let l = summary.latencyMinutes, !night.isManual {
                outcomes[.latencyMinutes] = l
            }
            outcomes[.totalSleepHours] = summary.totalSleep / 3600
            if !night.isManual {
                outcomes[.movementIndex] = summary.movementIndex
                outcomes[.snoreMinutes] = summary.snoreMinutes
            }
            let tags = AnalysisTags.keys(for: journal?.tags ?? [])
            return NightObservation(nightOf: NightKey.date(from: night.nightKey) ?? night.inBedStart,
                                    isFreeDay: isFreeDay(night), tags: tags, outcomes: outcomes)
        }
    }

    // MARK: Morning card

    /// One sentence comparing a night with the 14 nights before it.
    func morningSentence(for night: NightRecord) -> String {
        guard let s = night.summary else { return "No data for this night." }
        let before = nights.filter { $0.inBedStart < night.inBedStart && $0.inBedStart > night.inBedStart.addingTimeInterval(-15 * 86_400) }
        let baseline = Stats.mean(before.compactMap { $0.summary?.totalSleep })
        let sleep = Format.duration(s.totalSleep)
        guard let baseline, before.count >= 3 else {
            return "About \(sleep) of estimated sleep. A baseline appears after a few more nights."
        }
        let diff = (s.totalSleep - baseline) / 60
        if abs(diff) < 15 {
            return "About \(sleep) of estimated sleep, in line with your 2-week average."
        }
        let direction = diff > 0 ? "more" : "less"
        return "About \(sleep) of estimated sleep, \(Format.duration(abs(diff) * 60)) \(direction) than your 2-week average."
    }
}

enum Format {
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int((seconds / 60).rounded())
        let h = total / 60, m = total % 60
        if h == 0 { return "\(m) m" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) m"
    }

    static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func clock(minutesAfterMidnight m: Double) -> String {
        let cal = Calendar.current
        let base = cal.startOfDay(for: Date())
        return clock(base.addingTimeInterval(m * 60))
    }

    static func signed(_ value: Double, digits: Int = 1) -> String {
        let s = String(format: "%.\(digits)f", abs(value))
        return value >= 0 ? "+\(s)" : "−\(s)"
    }

    static func hours(_ h: Double) -> String {
        Format.duration(h * 3600)
    }
}
