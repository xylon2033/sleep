import Foundation
import Observation
import SleepCore

/// User preferences, persisted as JSON in UserDefaults.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    var schedule: SleepSchedule { didSet { save(schedule, key: Keys.schedule) } }
    var sounds: SoundSettings { didSet { save(sounds, key: Keys.sounds) } }
    var tracking: TrackingSettings { didSet { save(tracking, key: Keys.tracking) } }
    var customTags: [String] { didSet { save(customTags, key: Keys.customTags) } }
    var experiments: [SleepExperiment] { didSet { save(experiments, key: Keys.experiments) } }
    var hasOnboarded: Bool { didSet { UserDefaults.standard.set(hasOnboarded, forKey: Keys.onboarded) } }

    private enum Keys {
        static let schedule = "settings.schedule"
        static let sounds = "settings.sounds"
        static let tracking = "settings.tracking"
        static let customTags = "settings.customTags"
        static let experiments = "settings.experiments"
        static let onboarded = "settings.onboarded"
    }

    private init() {
        schedule = Self.load(SleepSchedule.self, key: Keys.schedule) ?? SleepSchedule()
        sounds = Self.load(SoundSettings.self, key: Keys.sounds) ?? SoundSettings()
        tracking = Self.load(TrackingSettings.self, key: Keys.tracking) ?? TrackingSettings()
        customTags = Self.load([String].self, key: Keys.customTags) ?? []
        experiments = Self.load([SleepExperiment].self, key: Keys.experiments) ?? []
        hasOnboarded = UserDefaults.standard.bool(forKey: Keys.onboarded)
    }

    var activeExperiment: SleepExperiment? {
        experiments.first { !$0.isFinished(at: Date()) && $0.start <= Date() }
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

enum NoiseKind: String, Codable, CaseIterable, Identifiable {
    case off, white, pink, brown, rain, waves

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: "None"
        case .white: "White noise"
        case .pink: "Pink noise"
        case .brown: "Brown noise"
        case .rain: "Rain"
        case .waves: "Ocean waves"
        }
    }

    var systemImage: String {
        switch self {
        case .off: "speaker.slash"
        case .white: "waveform"
        case .pink: "waveform.path"
        case .brown: "water.waves"
        case .rain: "cloud.rain"
        case .waves: "water.waves.and.arrow.up"
        }
    }
}

struct SoundSettings: Codable, Equatable {
    var kind: NoiseKind = .off
    /// 0…1 of the app's capped output gain.
    var volume: Double = 0.35
    /// Fade-out timer in minutes; 0 = all night (masking).
    var timerMinutes: Int = 45

    static let timerChoices = [15, 30, 45, 60, 90, 0]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(NoiseKind.self, forKey: .kind) ?? .off
        volume = try c.decodeIfPresent(Double.self, forKey: .volume) ?? 0.35
        timerMinutes = try c.decodeIfPresent(Int.self, forKey: .timerMinutes) ?? 45
    }
}

struct TrackingSettings: Codable, Equatable {
    /// dB above the noise floor that counts as a sound. Lower = more sensitive.
    var thresholdDb: Double = 6
    /// Run Apple's built-in sound classifier for snore / talk / cough events.
    var detectEvents = true
    /// Save short clips of snoring/talking (off by default; max 5 per night; deleted after 30 days).
    var saveClips = false
    var healthKitEnabled = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        thresholdDb = try c.decodeIfPresent(Double.self, forKey: .thresholdDb) ?? 6
        detectEvents = try c.decodeIfPresent(Bool.self, forKey: .detectEvents) ?? true
        saveClips = try c.decodeIfPresent(Bool.self, forKey: .saveClips) ?? false
        healthKitEnabled = try c.decodeIfPresent(Bool.self, forKey: .healthKitEnabled) ?? false
    }
}
