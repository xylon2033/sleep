import Foundation
import SwiftData
import SleepCore

/// One night in bed. Per-epoch features live in a single compact blob (`EpochCodec`),
/// not a row per epoch. Raw audio is never stored here.
@Model
final class NightRecord {
    var id: UUID = UUID()
    /// "Night of" key (evening date), shared with the journal entry.
    var nightKey: String = ""
    var inBedStart: Date = Date()
    var inBedEnd: Date?
    /// "tracked" (microphone) or "manual" (bed/wake times typed in).
    var source: String = NightSource.tracked.rawValue
    /// AlarmKit backstop time for this night, if any.
    var alarmTime: Date?
    var smartWakeWindowMinutes: Int = 0
    /// When the in-app gentle alarm started (smart wake), if it did.
    var smartWakeTriggeredAt: Date?
    var lastHeartbeat: Date?
    var interruptionCount: Int = 0
    var soundKind: String?
    var epochData: Data = Data()
    var eventsData: Data = Data()
    var summaryData: Data?
    /// "free" / "work" to override the weekday default for social jetlag.
    var dayTypeOverride: String?
    var savedToHealth: Bool = false

    init(inBedStart: Date, source: NightSource) {
        self.id = UUID()
        self.inBedStart = inBedStart
        self.nightKey = NightKey.key(for: inBedStart)
        self.source = source.rawValue
    }

    var isInProgress: Bool { inBedEnd == nil }
    var isManual: Bool { source == NightSource.manual.rawValue }

    var epochs: [EpochFeatures] {
        get { EpochCodec.decode(epochData) }
        set { epochData = EpochCodec.encode(newValue) }
    }

    var events: [SoundEvent] {
        get { (try? JSONDecoder().decode([SoundEvent].self, from: eventsData)) ?? [] }
        set { eventsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var summary: NightSummary? {
        get { summaryData.flatMap { try? JSONDecoder().decode(NightSummary.self, from: $0) } }
        set { summaryData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    /// Bed/onset/wake reduced for the regularity metrics.
    func sleepPeriod(isShift: Bool) -> SleepPeriod? {
        guard let end = inBedEnd, let s = summary else { return nil }
        let onset = s.sleepOnset ?? inBedStart
        let wake = s.finalWake ?? end
        guard wake > onset else { return nil }
        var asleep: [DateInterval]?
        if !isManual {
            asleep = s.segments
                .filter { $0.state == .light || $0.state == .deep }
                .map { DateInterval(start: $0.start, end: $0.end) }
        }
        return SleepPeriod(bedtime: inBedStart, sleepOnset: onset, wake: wake, outOfBed: end,
                           asleepIntervals: asleep, isShift: isShift)
    }
}

enum NightSource: String {
    case tracked, manual
}

/// Evening tags and morning check-in for one night, keyed by `nightKey`.
@Model
final class JournalRecord {
    var nightKey: String = ""
    var tagsData: Data = Data()
    var checkInData: Data?
    var updatedAt: Date = Date()

    init(nightKey: String) {
        self.nightKey = nightKey
    }

    var tags: [TagEntry] {
        get { (try? JSONDecoder().decode([TagEntry].self, from: tagsData)) ?? [] }
        set {
            tagsData = (try? JSONEncoder().encode(newValue)) ?? Data()
            updatedAt = Date()
        }
    }

    var checkIn: MorningCheckIn? {
        get { checkInData.flatMap { try? JSONDecoder().decode(MorningCheckIn.self, from: $0) } }
        set {
            checkInData = newValue.flatMap { try? JSONEncoder().encode($0) }
            updatedAt = Date()
        }
    }

    var isLateShift: Bool { tags.contains { $0.key == BuiltInTag.lateShift.rawValue } }
}

enum Persistence {
    /// Shared container so App Intents (Log Tag) and the app use the same store.
    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: NightRecord.self, JournalRecord.self)
        } catch {
            fatalError("Could not open the sleep database: \(error)")
        }
    }()

    @MainActor
    static func journal(for key: String, in context: ModelContext, create: Bool = true) -> JournalRecord? {
        let descriptor = FetchDescriptor<JournalRecord>(predicate: #Predicate { $0.nightKey == key })
        if let existing = try? context.fetch(descriptor).first { return existing }
        guard create else { return nil }
        let record = JournalRecord(nightKey: key)
        context.insert(record)
        return record
    }
}
