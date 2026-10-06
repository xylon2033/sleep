import Foundation

/// Built-in evening (pre-sleep) tags. Custom tags use `TagEntry.customKey(_:)`.
public enum BuiltInTag: String, CaseIterable, Codable, Sendable, Identifiable {
    case caffeine, alcohol, exercise, lateScreens, stress, lateMeal, nap, lateShift, sick, travel

    public var id: String { rawValue }

    public enum Input: Sendable { case toggle, timed, count, scale }

    public var label: String {
        switch self {
        case .caffeine: "Caffeine"
        case .alcohol: "Alcohol"
        case .exercise: "Exercise"
        case .lateScreens: "Late screens"
        case .stress: "Stress"
        case .lateMeal: "Late meal"
        case .nap: "Nap"
        case .lateShift: "Late shift"
        case .sick: "Sick"
        case .travel: "Travel"
        }
    }

    public var systemImage: String {
        switch self {
        case .caffeine: "cup.and.saucer.fill"
        case .alcohol: "wineglass.fill"
        case .exercise: "figure.run"
        case .lateScreens: "iphone"
        case .stress: "brain.head.profile"
        case .lateMeal: "fork.knife"
        case .nap: "powersleep"
        case .lateShift: "briefcase.fill"
        case .sick: "facemask.fill"
        case .travel: "airplane"
        }
    }

    /// How the tag is entered. Time-sensitive tags record a time; alcohol a count; stress 1–5.
    public var input: Input {
        switch self {
        case .caffeine, .exercise: .timed
        case .alcohol: .count
        case .stress: .scale
        default: .toggle
        }
    }
}

public struct TagEntry: Codable, Hashable, Sendable {
    /// Built-in raw value, or "custom:<name>".
    public var key: String
    /// Drinks for alcohol, 1–5 for stress.
    public var amount: Int?
    /// Last caffeine dose / exercise time.
    public var time: Date?

    public init(key: String, amount: Int? = nil, time: Date? = nil) {
        self.key = key
        self.amount = amount
        self.time = time
    }

    public static func customKey(_ name: String) -> String { "custom:\(name)" }

    public var builtIn: BuiltInTag? { BuiltInTag(rawValue: key) }
    public var customName: String? { key.hasPrefix("custom:") ? String(key.dropFirst(7)) : nil }
    public var displayName: String { builtIn?.label ?? customName ?? key }
}

public enum LatencyBucket: Int, Codable, CaseIterable, Sendable {
    case under10 = 0, tenTo20, twentyTo40, fortyTo60, over60

    public var label: String {
        switch self {
        case .under10: "< 10 min"
        case .tenTo20: "10–20"
        case .twentyTo40: "20–40"
        case .fortyTo60: "40–60"
        case .over60: "60+"
        }
    }

    /// Representative minutes for averaging.
    public var minutes: Double {
        switch self {
        case .under10: 5
        case .tenTo20: 15
        case .twentyTo40: 30
        case .fortyTo60: 50
        case .over60: 75
        }
    }

    /// Long enough that the stimulus-control tip applies.
    public var isLong: Bool { rawValue >= LatencyBucket.twentyTo40.rawValue }
}

/// The < 15 s morning check-in.
public struct MorningCheckIn: Codable, Equatable, Sendable {
    /// 1 (awful) … 5 (great).
    public var mood: Int
    /// Perceived sleep quality 1 … 5.
    public var quality: Int
    public var latency: LatencyBucket
    /// Number of awakenings (3 means "3 or more").
    public var awakenings: Int
    public var notes: String

    public init(mood: Int = 3, quality: Int = 3, latency: LatencyBucket = .tenTo20, awakenings: Int = 1, notes: String = "") {
        self.mood = mood
        self.quality = quality
        self.latency = latency
        self.awakenings = awakenings
        self.notes = notes
    }

    public static let moodEmoji = ["😫", "😕", "😐", "🙂", "😄"]
}

/// Keys used for analysis. Ordinal/count tags are binarised so each comparison is "with vs without".
public enum AnalysisTags {
    public static let lateCaffeineHour = 14

    public static func keys(for entries: [TagEntry], calendar: Calendar = .current) -> Set<String> {
        var keys = Set<String>()
        for e in entries {
            switch e.builtIn {
            case .caffeine:
                keys.insert("caffeine")
                if let t = e.time, calendar.component(.hour, from: t) >= lateCaffeineHour { keys.insert("caffeineLate") }
            case .alcohol:
                if (e.amount ?? 1) >= 1 { keys.insert("alcohol") }
                if (e.amount ?? 0) >= 3 { keys.insert("alcohol3plus") }
            case .stress:
                if (e.amount ?? 3) >= 3 { keys.insert("stressHigh") }
            case .some(let tag):
                keys.insert(tag.rawValue)
            case .none:
                keys.insert(e.key)
            }
        }
        return keys
    }

    public static func label(for key: String) -> String {
        switch key {
        case "caffeineLate": return "Caffeine after \(lateCaffeineHour):00"
        case "alcohol3plus": return "3+ drinks"
        case "stressHigh": return "Stress 3+"
        default:
            if let b = BuiltInTag(rawValue: key) { return b.label }
            return TagEntry(key: key).displayName
        }
    }
}
