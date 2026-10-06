import AVFoundation
import Charts
import SleepCore
import SwiftData
import SwiftUI

struct MorningReportView: View {
    @Bindable var night: NightRecord
    var promptCheckIn: Bool

    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query(sort: \NightRecord.inBedStart) private var allNights: [NightRecord]
    @Query private var journals: [JournalRecord]
    @State private var showCheckIn = false
    @State private var clipPlayer: AVAudioPlayer?

    private var journal: JournalRecord? { journals.first { $0.nightKey == night.nightKey } }
    private var analytics: Analytics { Analytics(nights: allNights, journals: journals, schedule: settings.schedule) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let summary = night.summary {
                    Card {
                        Text(analytics.morningSentence(for: night))
                            .font(.title3.weight(.medium))
                        if let c = journal?.checkIn, c.latency.isLong {
                            Label("Took a while to fall asleep? If you're awake for more than ~20 minutes, get up and do something calm in dim light, then return when sleepy.",
                                  systemImage: "lightbulb")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    stats(summary)
                    if !night.isManual {
                        Card(title: "The night", systemImage: "waveform.path.ecg") {
                            NightChart(summary: summary, epochs: night.epochs, events: night.events)
                                .frame(height: 220)
                            EstimateNote()
                        }
                        eventsCard(summary)
                        if summary.gapMinutes > 1 || night.interruptionCount > 0 {
                            gapsCard(summary)
                        }
                    }
                }
                checkInCard
                Card(title: "Tags", systemImage: "tag") {
                    EveningTagsView(nightKey: night.nightKey)
                }
                Card(title: "Day type", systemImage: "calendar") {
                    Picker("Day type", selection: Binding(
                        get: { night.dayTypeOverride ?? "auto" },
                        set: { night.dayTypeOverride = $0 == "auto" ? nil : $0; try? context.save() }
                    )) {
                        Text("Auto").tag("auto")
                        Text("Work").tag("work")
                        Text("Free").tag("free")
                    }
                    .pickerStyle(.segmented)
                    Text("Used for social jetlag. Auto uses your free days in Settings.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if night.savedToHealth {
                    Label("Saved to Apple Health (in bed + asleep)", systemImage: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(.pink)
                }
            }
            .padding()
        }
        .navigationTitle(night.inBedStart.shortDay)
        .sheet(isPresented: $showCheckIn) {
            CheckInView(nightKey: night.nightKey)
                .presentationDetents([.large])
        }
        .onAppear {
            if promptCheckIn, journal?.checkIn == nil { showCheckIn = true }
        }
    }

    private func stats(_ s: NightSummary) -> some View {
        Card {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
                GridRow {
                    StatTile(label: "In bed", value: Format.duration(s.timeInBed),
                             detail: "\(Format.clock(s.inBedStart))–\(Format.clock(s.inBedEnd))")
                    StatTile(label: "Est. sleep", value: Format.duration(s.totalSleep),
                             detail: "goal \(Format.duration(Double(settings.schedule.sleepGoalMinutes) * 60))")
                }
                if !night.isManual {
                    GridRow {
                        StatTile(label: "Est. fell asleep", value: s.sleepOnset.map(Format.clock) ?? "–",
                                 detail: s.latencyMinutes.map { "after \(Int($0.rounded())) min" })
                        StatTile(label: "Est. woke", value: s.finalWake.map(Format.clock) ?? "–",
                                 detail: s.wakeBouts > 0 ? "\(s.wakeBouts) restless spells" : nil)
                    }
                    GridRow {
                        StatTile(label: "Efficiency", value: s.efficiency.map { "\(Int(($0 * 100).rounded()))%" } ?? "–",
                                 detail: "low confidence", lowConfidence: true)
                        StatTile(label: "Movement index", value: String(format: "%.1f", s.movementIndex),
                                 detail: "sound activity per 30 s")
                    }
                }
            }
        }
    }

    private func eventsCard(_ s: NightSummary) -> some View {
        Card(title: "Sounds", systemImage: "ear") {
            if night.events.isEmpty {
                Text("No snoring, talking or coughing detected.")
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    StatTile(label: "Snoring", value: Format.duration(s.snoreMinutes * 60))
                    StatTile(label: "Talking", value: "\(s.eventCounts[SoundEvent.Kind.speech.rawValue] ?? 0)×")
                    StatTile(label: "Coughs", value: "\(s.eventCounts[SoundEvent.Kind.cough.rawValue] ?? 0)×")
                }
                ForEach(night.events.sorted { $0.start < $1.start }.prefix(30)) { event in
                    HStack {
                        Text(event.kind.label)
                        Spacer()
                        Text(Format.clock(event.start)).foregroundStyle(.secondary).monospacedDigit()
                        if event.duration > 60 {
                            Text(Format.duration(event.duration)).foregroundStyle(.secondary)
                        }
                        if let clip = event.clipFileName {
                            Button {
                                play(clip)
                            } label: {
                                Image(systemName: "play.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .font(.subheadline)
                }
                if s.snoreMinutes > 30 {
                    Text("Loud, frequent snoring with daytime sleepiness is worth raising with a doctor. Use this as a prompt for an evaluation, not to rule sleep apnea out.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func gapsCard(_ s: NightSummary) -> some View {
        Card(title: "Recording gaps", systemImage: "exclamationmark.triangle") {
            Text("\(Format.duration(s.gapMinutes * 60)) of the night wasn't recorded (\(Int((s.coverage * 100).rounded()))% coverage, \(night.interruptionCount) interruption\(night.interruptionCount == 1 ? "" : "s")). Calls, Siri or another app using the microphone can pause tracking.")
                .font(.footnote)
        }
    }

    private var checkInCard: some View {
        Card(title: "Morning check-in", systemImage: "sun.max") {
            if let c = journal?.checkIn {
                HStack {
                    StatTile(label: "Mood", value: MorningCheckIn.moodEmoji[max(0, min(4, c.mood - 1))])
                    StatTile(label: "Quality", value: "\(c.quality)/5")
                    StatTile(label: "Fell asleep", value: c.latency.label)
                    StatTile(label: "Woke", value: c.awakenings >= 3 ? "3+" : "\(c.awakenings)×")
                }
                if !c.notes.isEmpty {
                    Text(c.notes).font(.footnote).foregroundStyle(.secondary)
                }
                Button("Edit") { showCheckIn = true }.font(.footnote)
            } else {
                Button {
                    showCheckIn = true
                } label: {
                    Label("How did you sleep?", systemImage: "hand.tap")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func play(_ clip: String) {
        clipPlayer = try? AVAudioPlayer(contentsOf: ClipStore.url(for: clip))
        clipPlayer?.play()
    }
}

/// Activity bars with the estimated state band and event markers.
struct NightChart: View {
    let summary: NightSummary
    let epochs: [EpochFeatures]
    let events: [SoundEvent]

    private func color(_ state: EstimatedState) -> Color {
        switch state {
        case .awake: .orange
        case .light: .teal
        case .deep: .indigo
        case .noData: .gray.opacity(0.3)
        }
    }

    private func level(_ state: EstimatedState) -> String {
        switch state {
        case .awake: "Awake"
        case .light: "Light (est.)"
        case .deep: "Deep (est.)"
        case .noData: "No data"
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            Chart {
                ForEach(Array(summary.segments.enumerated()), id: \.offset) { _, seg in
                    RectangleMark(xStart: .value("Start", seg.start), xEnd: .value("End", seg.end),
                                  y: .value("State", level(seg.state)))
                        .foregroundStyle(color(seg.state))
                }
            }
            .chartYScale(domain: ["Awake", "Light (est.)", "Deep (est.)", "No data"])
            .chartXAxis(.hidden)
            .frame(height: 110)

            Chart {
                ForEach(epochs, id: \.start) { e in
                    BarMark(x: .value("Time", e.start), y: .value("Activity", min(e.activity, 10)))
                        .foregroundStyle(.indigo.opacity(0.7))
                }
                ForEach(events.filter { $0.kind == .snoring }) { e in
                    RectangleMark(xStart: .value("Start", e.start), xEnd: .value("End", max(e.end, e.start.addingTimeInterval(60))),
                                  yStart: .value("Lo", 9.5), yEnd: .value("Hi", 10))
                        .foregroundStyle(.pink)
                }
            }
            .chartYScale(domain: 0...10)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour())
                }
            }
        }
    }
}
