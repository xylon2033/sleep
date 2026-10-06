import Foundation

/// The user's sleep plan. Wake time is the anchor, seven days a week.
public struct SleepSchedule: Codable, Equatable, Sendable {
    public var wakeHour: Int = 7
    public var wakeMinute: Int = 0
    public var sleepGoalMinutes: Int = 480

    public var alarmEnabled = true
    public var smartWakeEnabled = false
    /// Length of the gentle-wake window that ends at the wake time.
    public var smartWakeWindowMinutes: Int = 30

    public var windDownEnabled = true
    public var windDownLeadMinutes: Int = 45
    public var bedtimeReminderEnabled = true
    public var caffeineReminderEnabled = true
    public var caffeineCutoffHoursBeforeBed: Int = 8
    public var morningLightEnabled = true

    /// Calendar weekdays (1 = Sunday … 7 = Saturday) of *wake days* that count as free days.
    public var freeWeekdays: Set<Int> = [1, 7]

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case wakeHour, wakeMinute, sleepGoalMinutes, alarmEnabled, smartWakeEnabled, smartWakeWindowMinutes,
             windDownEnabled, windDownLeadMinutes, bedtimeReminderEnabled, caffeineReminderEnabled,
             caffeineCutoffHoursBeforeBed, morningLightEnabled, freeWeekdays
    }

    /// Lenient decoding: settings saved by an older build keep working when fields are added.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var s = SleepSchedule()
        s.wakeHour = try c.decodeIfPresent(Int.self, forKey: .wakeHour) ?? s.wakeHour
        s.wakeMinute = try c.decodeIfPresent(Int.self, forKey: .wakeMinute) ?? s.wakeMinute
        s.sleepGoalMinutes = try c.decodeIfPresent(Int.self, forKey: .sleepGoalMinutes) ?? s.sleepGoalMinutes
        s.alarmEnabled = try c.decodeIfPresent(Bool.self, forKey: .alarmEnabled) ?? s.alarmEnabled
        s.smartWakeEnabled = try c.decodeIfPresent(Bool.self, forKey: .smartWakeEnabled) ?? s.smartWakeEnabled
        s.smartWakeWindowMinutes = try c.decodeIfPresent(Int.self, forKey: .smartWakeWindowMinutes) ?? s.smartWakeWindowMinutes
        s.windDownEnabled = try c.decodeIfPresent(Bool.self, forKey: .windDownEnabled) ?? s.windDownEnabled
        s.windDownLeadMinutes = try c.decodeIfPresent(Int.self, forKey: .windDownLeadMinutes) ?? s.windDownLeadMinutes
        s.bedtimeReminderEnabled = try c.decodeIfPresent(Bool.self, forKey: .bedtimeReminderEnabled) ?? s.bedtimeReminderEnabled
        s.caffeineReminderEnabled = try c.decodeIfPresent(Bool.self, forKey: .caffeineReminderEnabled) ?? s.caffeineReminderEnabled
        s.caffeineCutoffHoursBeforeBed = try c.decodeIfPresent(Int.self, forKey: .caffeineCutoffHoursBeforeBed) ?? s.caffeineCutoffHoursBeforeBed
        s.morningLightEnabled = try c.decodeIfPresent(Bool.self, forKey: .morningLightEnabled) ?? s.morningLightEnabled
        s.freeWeekdays = try c.decodeIfPresent(Set<Int>.self, forKey: .freeWeekdays) ?? s.freeWeekdays
        self = s
    }

    /// Wake time as minutes after midnight.
    public var wakeMinutes: Int { wakeHour * 60 + wakeMinute }

    /// Target bedtime (wake − goal) as minutes after midnight.
    public var targetBedtimeMinutes: Int {
        ((wakeMinutes - sleepGoalMinutes) % 1440 + 1440) % 1440
    }

    /// The next wake time strictly after `date`.
    public func nextWake(after date: Date, calendar: Calendar = .current) -> Date {
        let comps = DateComponents(hour: wakeHour, minute: wakeMinute, second: 0)
        return calendar.nextDate(after: date, matching: comps, matchingPolicy: .nextTime) ?? date.addingTimeInterval(86_400)
    }
}

/// Coaching towards the target bedtime in 15-minute steps (CBT-I style: fixed wake, gradual bedtime).
public struct BedtimeCoach: Sendable {
    public var stepMinutes: Double = 15

    public init(stepMinutes: Double = 15) {
        self.stepMinutes = stepMinutes
    }

    public struct Suggestion: Sendable, Equatable {
        /// Tonight's suggested bedtime, minutes after midnight.
        public var bedtimeMinutes: Double
        /// Your recent typical bedtime (median of recent nights), minutes after midnight.
        public var typicalMinutes: Double?
        /// How far tonight's suggestion still is from the target.
        public var remainingMinutes: Double
        public var message: String
    }

    /// - Parameter recentBedtimes: bedtimes of the most recent nights (7 is a good window).
    public func suggestion(schedule: SleepSchedule, recentBedtimes: [Date], calendar: Calendar = .current) -> Suggestion {
        let target = Double(schedule.targetBedtimeMinutes)
        let targetPivot = Regularity.clockMinutes(fromMidnight: target, pivotHour: 12)
        let typicalPivot = Stats.median(recentBedtimes.map { Regularity.clockMinutes($0, pivotHour: 12, calendar: calendar) })

        guard let typical = typicalPivot else {
            return Suggestion(bedtimeMinutes: target, typicalMinutes: nil, remainingMinutes: 0,
                              message: "Aim for \(Self.format(target)) so you get your full sleep goal.")
        }
        let typicalClock = Regularity.minutesAfterMidnight(fromPivoted: typical, pivotHour: 12)
        let lateBy = typical - targetPivot
        if lateBy > stepMinutes {
            let tonight = typical - stepMinutes
            let clock = Regularity.minutesAfterMidnight(fromPivoted: tonight, pivotHour: 12)
            return Suggestion(bedtimeMinutes: clock, typicalMinutes: typicalClock, remainingMinutes: tonight - targetPivot,
                              message: "You've been going to bed around \(Self.format(typicalClock)). Try \(Self.format(clock)) tonight: 15 minutes earlier, one step closer to \(Self.format(target)).")
        }
        if lateBy < -stepMinutes {
            return Suggestion(bedtimeMinutes: target, typicalMinutes: typicalClock, remainingMinutes: 0,
                              message: "You've been going to bed early (around \(Self.format(typicalClock))). Going to bed before you're sleepy can mean more time lying awake, so aim for \(Self.format(target)).")
        }
        return Suggestion(bedtimeMinutes: target, typicalMinutes: typicalClock, remainingMinutes: 0,
                          message: "You're on target. Keep \(Self.format(target)) and the same wake time every day.")
    }

    public static func format(_ minutesAfterMidnight: Double) -> String {
        let m = Int(minutesAfterMidnight.rounded()) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }
}

/// Informational nudges (local notifications). The wake alarm itself is AlarmKit, not one of these.
public struct PlannedReminder: Sendable, Equatable, Hashable {
    public enum Kind: String, Sendable, CaseIterable {
        case caffeineCutoff, windDown, bedtime, morningLight
    }
    public var kind: Kind
    public var date: Date
    public var title: String
    public var body: String

    public var identifier: String {
        "reminder.\(kind.rawValue).\(Int(date.timeIntervalSince1970))"
    }
}

public enum ReminderPlanner {
    /// Reminders for the next `days` days, using tonight's coached bedtime for every evening
    /// (re-planned each time the app becomes active, so the step advances as habits change).
    public static func plan(schedule: SleepSchedule, bedtimeMinutes: Double, from now: Date, days: Int = 7,
                            calendar: Calendar = .current) -> [PlannedReminder] {
        var result: [PlannedReminder] = []
        let today = calendar.startOfDay(for: now)
        let bed = Int(bedtimeMinutes.rounded())
        let bedText = BedtimeCoach.format(bedtimeMinutes)
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            // Bedtimes after midnight belong to the evening of `day` but fall on the next calendar date.
            let bedDayOffset = bed < 12 * 60 ? 1 : 0
            guard let bedDay = calendar.date(byAdding: .day, value: bedDayOffset, to: day),
                  let bedDate = calendar.date(bySettingHour: bed / 60, minute: bed % 60, second: 0, of: bedDay) else { continue }

            if schedule.caffeineReminderEnabled {
                let d = bedDate.addingTimeInterval(-Double(schedule.caffeineCutoffHoursBeforeBed) * 3600)
                result.append(PlannedReminder(kind: .caffeineCutoff, date: d, title: "Caffeine cutoff",
                                              body: "Last call for coffee, tea and energy drinks if you want to be asleep by \(bedText)."))
            }
            if schedule.windDownEnabled {
                let d = bedDate.addingTimeInterval(-Double(schedule.windDownLeadMinutes) * 60)
                result.append(PlannedReminder(kind: .windDown, date: d, title: "Time to wind down",
                                              body: "Dim the lights and put screens away. Bedtime is \(bedText)."))
            }
            if schedule.bedtimeReminderEnabled {
                result.append(PlannedReminder(kind: .bedtime, date: bedDate, title: "Bedtime",
                                              body: "Plug in your phone and tap Start Night before you lock it."))
            }
            if schedule.morningLightEnabled,
               let wake = calendar.date(bySettingHour: schedule.wakeHour, minute: schedule.wakeMinute, second: 0, of: day) {
                result.append(PlannedReminder(kind: .morningLight, date: wake.addingTimeInterval(15 * 60), title: "Get some daylight",
                                              body: "10–15 minutes of outdoor light soon after waking helps anchor your body clock."))
            }
        }
        return result.filter { $0.date > now }.sorted { $0.date < $1.date }
    }
}
