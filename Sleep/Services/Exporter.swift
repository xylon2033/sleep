import Foundation
import SleepCore

/// Exports nights + journal as a CSV (one row per night) and a JSON file
/// (summaries, events and per-epoch features) for your own analysis. Returns both file URLs.
enum Exporter {
    static func export(nights: [NightRecord], journals: [JournalRecord]) throws -> [URL] {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("sleep-export-\(Int(Date().timeIntervalSince1970))", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var byKey: [String: JournalRecord] = [:]
        for j in journals { byKey[j.nightKey] = j }
        let finished = nights.filter { !$0.isInProgress }.sorted { $0.inBedStart < $1.inBedStart }

        let iso = ISO8601DateFormatter()
        func d(_ date: Date?) -> String { date.map { iso.string(from: $0) } ?? "" }
        func n(_ v: Double?, _ digits: Int = 2) -> String { v.map { String(format: "%.\(digits)f", $0) } ?? "" }
        func esc(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }

        var csv = "night_of,source,in_bed,out_of_bed,sleep_onset,final_wake,est_sleep_h,latency_min,waso_min,wake_bouts,efficiency,movement_index,snore_min,gap_min,coverage,tags,mood,quality,latency_bucket,awakenings,notes\n"
        for night in finished {
            let s = night.summary
            let j = byKey[night.nightKey]
            let tags = (j?.tags ?? []).map { t -> String in
                var label = t.displayName
                if let a = t.amount { label += "=\(a)" }
                if let time = t.time { label += "@\(Format.clock(time))" }
                return label
            }.joined(separator: ";")
            let c = j?.checkIn
            let row: [String] = [
                night.nightKey, night.source, d(night.inBedStart), d(night.inBedEnd), d(s?.sleepOnset), d(s?.finalWake),
                n(s.map { $0.totalSleep / 3600 }), n(s?.latencyMinutes, 0), n(s?.wasoMinutes, 0), s.map { "\($0.wakeBouts)" } ?? "",
                n(s?.efficiency), n(s?.movementIndex), n(s?.snoreMinutes, 1), n(s?.gapMinutes, 0), n(s?.coverage),
                esc(tags), c.map { "\($0.mood)" } ?? "", c.map { "\($0.quality)" } ?? "", c?.latency.label ?? "",
                c.map { "\($0.awakenings)" } ?? "", esc(c?.notes ?? ""),
            ]
            csv += row.joined(separator: ",") + "\n"
        }
        let csvURL = folder.appendingPathComponent("nights.csv")
        try csv.write(to: csvURL, atomically: true, encoding: .utf8)

        struct NightExport: Encodable {
            var nightKey: String
            var source: String
            var summary: NightSummary?
            var events: [SoundEvent]
            var epochs: [EpochFeatures]
            var tags: [TagEntry]
            var checkIn: MorningCheckIn?
        }
        let payload = finished.map { night in
            NightExport(nightKey: night.nightKey, source: night.source, summary: night.summary, events: night.events,
                        epochs: night.epochs, tags: byKey[night.nightKey]?.tags ?? [], checkIn: byKey[night.nightKey]?.checkIn)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonURL = folder.appendingPathComponent("nights.json")
        try encoder.encode(payload).write(to: jsonURL)
        return [csvURL, jsonURL]
    }
}
