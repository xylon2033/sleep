import Charts
import SleepCore
import SwiftData
import SwiftUI

struct TrendsView: View {
    enum Range: Int, CaseIterable, Identifiable {
        case week = 7, twoWeeks = 14, month = 30, quarter = 90
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .week: "Week"
            case .twoWeeks: "2 weeks"
            case .month: "Month"
            case .quarter: "3 months"
            }
        }
    }

    @Environment(AppSettings.self) private var settings
    @Query(sort: \NightRecord.inBedStart) private var nights: [NightRecord]
    @Query private var journals: [JournalRecord]
    @State private var range: Range = .twoWeeks

    private var analytics: Analytics { Analytics(nights: nights, journals: journals, schedule: settings.schedule) }

    var body: some View {
        let a = analytics
        let records = a.recent(days: range.rawValue)
        let snapshot = a.snapshot(days: range.rawValue)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Range", selection: $range) {
                    ForEach(Range.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                if records.isEmpty {
                    ContentUnavailableView("No nights in this range", systemImage: "chart.bar",
                                           description: Text("Track or log a few nights to see trends."))
                } else {
                    regularityCard(snapshot)
                    Card(title: "Bed and wake times", systemImage: "bed.double") {
                        BedWakeChart(records: records, schedule: settings.schedule)
                            .frame(height: 220)
                    }
                    Card(title: "Estimated sleep", systemImage: "clock") {
                        DurationChart(records: records, goalHours: Double(settings.schedule.sleepGoalMinutes) / 60)
                            .frame(height: 180)
                        HStack {
                            StatTile(label: "Average", value: snapshot.averageSleep.map(Format.duration) ?? "–")
                            StatTile(label: "Sleep debt (7 nights)", value: Format.duration(snapshot.debtMinutes * 60))
                            StatTile(label: "On-schedule streak", value: "\(snapshot.streak) night\(snapshot.streak == 1 ? "" : "s")")
                        }
                    }
                    bestWorst(records: records, analytics: a)
                    if range.rawValue >= 30 {
                        Card(title: "Trend", systemImage: "chart.line.uptrend.xyaxis") {
                            TrendLines(records: records, analytics: a)
                                .frame(height: 180)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Trends")
    }

    private func regularityCard(_ s: Analytics.Snapshot) -> some View {
        Card(title: "Regularity", systemImage: "metronome") {
            HStack(alignment: .top) {
                StatTile(label: "Sleep Regularity Index",
                         value: s.sri.map { String(format: "%.0f", $0.value) } ?? "–",
                         detail: s.sri == nil ? "needs 7+ consecutive nights" : "UK Biobank median ≈ 81")
                StatTile(label: "Social jetlag",
                         value: s.socialJetlag.map { Format.hours($0.hours) } ?? "–",
                         detail: s.socialJetlag == nil ? "needs 2 work + 2 free nights" : "work vs free mid-sleep")
            }
            if let v = s.variability {
                let wake = Format.duration(v.wakeRange * 60)
                Text(v.wakeRange <= 30
                     ? "Your wake time varied by \(wake). Nicely consistent; keep it under 30 m."
                     : "Your wake time varied by \(wake) over these nights. Target: under 30 m.")
                    .font(.subheadline)
                Text("Bedtime SD \(Format.duration(v.bedtimeSD * 60)) · wake SD \(Format.duration(v.wakeSD * 60))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Regularity predicted mortality risk better than duration in the UK Biobank (observational).")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func bestWorst(records: [NightRecord], analytics: Analytics) -> some View {
        let scored: [(NightRecord, Double)] = records.compactMap { n in
            if let q = analytics.journal(for: n)?.checkIn?.quality { return (n, Double(q) * 10 + (n.summary?.totalSleep ?? 0) / 3600) }
            if let t = n.summary?.totalSleep { return (n, t / 3600) }
            return nil
        }
        if scored.count >= 3, let best = scored.max(by: { $0.1 < $1.1 }), let worst = scored.min(by: { $0.1 < $1.1 }) {
            Card(title: "Best and worst", systemImage: "arrow.up.arrow.down") {
                nightLine("Best", best.0, analytics: analytics)
                Divider()
                nightLine("Worst", worst.0, analytics: analytics)
            }
        }
    }

    private func nightLine(_ title: String, _ night: NightRecord, analytics: Analytics) -> some View {
        let tags = analytics.journal(for: night)?.tags.map(\.displayName) ?? []
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(night.inBedStart.shortDay).foregroundStyle(.secondary)
                Text(Format.duration(night.summary?.totalSleep ?? 0)).monospacedDigit()
            }
            Text(tags.isEmpty ? "No tags" : tags.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Floating bars from bedtime to wake, on a clock axis that runs 18:00 → 14:00.
struct BedWakeChart: View {
    let records: [NightRecord]
    let schedule: SleepSchedule

    private func hours(_ date: Date) -> Double {
        Regularity.clockMinutes(date, pivotHour: 18) / 60
    }

    var body: some View {
        let targetBed = Regularity.clockMinutes(fromMidnight: Double(schedule.targetBedtimeMinutes), pivotHour: 18) / 60
        let targetWake = Regularity.clockMinutes(fromMidnight: Double(schedule.wakeMinutes), pivotHour: 18) / 60
        Chart {
            RuleMark(y: .value("Target bed", targetBed))
                .foregroundStyle(.indigo.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            RuleMark(y: .value("Target wake", targetWake))
                .foregroundStyle(.orange.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            ForEach(records) { n in
                if let end = n.inBedEnd {
                    BarMark(x: .value("Night", n.inBedStart, unit: .day),
                            yStart: .value("Bed", hours(n.inBedStart)),
                            yEnd: .value("Up", hours(end)),
                            width: .ratio(0.5))
                        .foregroundStyle(.indigo.gradient)
                        .cornerRadius(6)
                }
            }
        }
        .chartYScale(domain: 2...20)
        .chartYAxis {
            AxisMarks(values: [2, 4, 6, 8, 10, 12, 14, 16, 18, 20]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let h = value.as(Double.self) {
                        Text(String(format: "%02d:00", (Int(h) + 18) % 24))
                    }
                }
            }
        }
    }
}

struct DurationChart: View {
    let records: [NightRecord]
    let goalHours: Double

    var body: some View {
        Chart {
            ForEach(records) { n in
                if let s = n.summary {
                    BarMark(x: .value("Night", n.inBedStart, unit: .day), y: .value("Hours", s.totalSleep / 3600))
                        .foregroundStyle(s.totalSleep / 3600 >= goalHours ? Color.teal : Color.indigo)
                }
            }
            RuleMark(y: .value("Goal", goalHours))
                .foregroundStyle(.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .annotation(position: .top, alignment: .leading) {
                    Text("goal").font(.caption2).foregroundStyle(.secondary)
                }
        }
    }
}

/// 7-night rolling means of estimated sleep and (if logged) quality.
struct TrendLines: View {
    let records: [NightRecord]
    let analytics: Analytics

    var body: some View {
        let points = rolling()
        Chart {
            ForEach(points, id: \.date) { p in
                LineMark(x: .value("Date", p.date), y: .value("Value", p.sleep))
                    .foregroundStyle(by: .value("Series", "Sleep (h)"))
                if let q = p.quality {
                    LineMark(x: .value("Date", p.date), y: .value("Value", q))
                        .foregroundStyle(by: .value("Series", "Quality"))
                }
            }
        }
        .chartForegroundStyleScale(["Sleep (h)": Color.indigo, "Quality": Color.orange])
    }

    private func rolling() -> [(date: Date, sleep: Double, quality: Double?)] {
        records.indices.map { i in
            let window = records[max(0, i - 6)...i]
            let sleep = Stats.mean(window.compactMap { $0.summary?.totalSleep }).map { $0 / 3600 } ?? 0
            let quality = Stats.mean(window.compactMap { analytics.journal(for: $0)?.checkIn.map { Double($0.quality) } })
            return (records[i].inBedStart, sleep, quality)
        }
    }
}
