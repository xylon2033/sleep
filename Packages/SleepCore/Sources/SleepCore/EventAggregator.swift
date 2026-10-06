import Foundation

/// Merges per-window classifier detections into episodes: a run of snore detections a few
/// seconds apart becomes one "snoring 03:12–03:20" event instead of hundreds of blips.
public struct EventAggregator: Sendable {
    /// Maximum silence between detections that still counts as the same episode, per kind.
    public var mergeGap: [SoundEvent.Kind: TimeInterval] = [.snoring: 30, .speech: 10, .cough: 5, .sneeze: 5, .other: 5]
    /// Length credited to a single detection window.
    public var windowDuration: TimeInterval

    private var open: [SoundEvent.Kind: SoundEvent] = [:]

    public init(windowDuration: TimeInterval = 1.5) {
        self.windowDuration = windowDuration
    }

    /// Adds a detection. Returns any episodes that closed because this detection came after their gap.
    public mutating func add(kind: SoundEvent.Kind, confidence: Double, at time: Date) -> [SoundEvent] {
        var closed = close(before: time)
        if var current = open[kind] {
            current.end = max(current.end, time)
            current.confidence = max(current.confidence, confidence)
            open[kind] = current
        } else {
            open[kind] = SoundEvent(kind: kind, start: time.addingTimeInterval(-windowDuration), end: time, confidence: confidence)
        }
        closed.sort { $0.start < $1.start }
        return closed
    }

    /// Closes episodes whose merge gap has passed by `time` (call periodically).
    public mutating func close(before time: Date) -> [SoundEvent] {
        var closed: [SoundEvent] = []
        for (kind, event) in open where time.timeIntervalSince(event.end) > (mergeGap[kind] ?? 5) {
            closed.append(event)
            open[kind] = nil
        }
        return closed.sorted { $0.start < $1.start }
    }

    /// Ends the night: returns all open episodes.
    public mutating func flush() -> [SoundEvent] {
        let all = open.values.sorted { $0.start < $1.start }
        open.removeAll()
        return all
    }

    /// Kinds with an episode in progress (for clip capture decisions).
    public var openKinds: Set<SoundEvent.Kind> { Set(open.keys) }
}

/// "Night of" key: the calendar date of the evening a night started on (a 01:00 start belongs
/// to the previous evening). Used to pair a night with its journal entry.
public enum NightKey {
    public static func key(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date.addingTimeInterval(-12 * 3600))
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Midday of the evening the key refers to.
    public static func date(from key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }
}
