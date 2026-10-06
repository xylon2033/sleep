import Charts
import SleepCore
import SwiftData
import SwiftUI

/// n-of-1 tag effects (with vs without, weekday-adjusted, bootstrap CIs, FDR) and experiments.
struct InsightsView: View {
    @Environment(AppSettings.self) private var settings
    @Query(sort: \NightRecord.inBedStart) private var nights: [NightRecord]
    @Query private var journals: [JournalRecord]
    @State private var outcome: Outcome = .quality
    @State private var effects: [TagEffect] = []
    @State private var observationCount = 0
    @State private var showNewExperiment = false

    var body: some View {
        List {
            Section {
                Picker("Outcome", selection: $outcome) {
                    ForEach(Outcome.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            } footer: {
                Text("Compares nights with and without each tag, within work and free days separately so weekend habits don't masquerade as tag effects. Ranked by effect size; shown with 95% bootstrap intervals.")
            }

            Section("Tag effects") {
                if effects.isEmpty {
                    Text(observationCount < 10
                         ? "Keep tagging. A tag shows up once it has at least 5 nights with it and 5 without (\(observationCount) nights so far)."
                         : "No tag has 5+ nights both with and without it yet for this outcome.")
                        .foregroundStyle(.secondary)
                }
                ForEach(effects) { effect in
                    EffectRow(effect: effect)
                }
            }

            Section {
                if let active = settings.activeExperiment {
                    ExperimentStatus(experiment: active, nights: nights, journals: journals, schedule: settings.schedule)
                }
                ForEach(settings.experiments.filter { $0.isFinished(at: Date()) }.reversed()) { e in
                    ExperimentStatus(experiment: e, nights: nights, journals: journals, schedule: settings.schedule)
                }
                if settings.activeExperiment == nil {
                    Button {
                        showNewExperiment = true
                    } label: {
                        Label("Start a 2-week experiment", systemImage: "flask")
                    }
                }
            } header: {
                Text("Experiments")
            } footer: {
                Text("Correlations can mislead. An experiment switches one habit on in alternating weeks and compares the two, which is much stronger evidence.")
            }

            Section {
                Text("Findings below about 10 nights per group are marked provisional. With many tags, some differences appear by chance; \"holds after correction\" means it survives a Benjamini–Hochberg false-discovery check.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Insights")
        .task(id: "\(outcome.rawValue)-\(nights.count)-\(journals.map(\.updatedAt).max()?.timeIntervalSince1970 ?? 0)") {
            recompute()
        }
        .sheet(isPresented: $showNewExperiment) {
            NavigationStack { NewExperimentView() }
        }
    }

    private func recompute() {
        let analytics = Analytics(nights: nights, journals: journals, schedule: settings.schedule)
        let observations = analytics.observations()
        observationCount = observations.count
        effects = TagEffectAnalyzer.analyze(observations: observations, outcome: outcome, iterations: 1500)
    }
}

private struct EffectRow: View {
    let effect: TagEffect

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(AnalysisTags.label(for: effect.tag)).font(.headline)
                Spacer()
                Text(Format.signed(effect.difference))
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(effect.interval.containsZero ? Color.secondary : (effect.isBeneficial ? Color.teal : Color.orange))
            }
            IntervalBar(effect: effect)
                .frame(height: 22)
            HStack(spacing: 8) {
                Text("95% CI \(Format.signed(effect.interval.low)) to \(Format.signed(effect.interval.high))")
                Text("· \(effect.withCount) vs \(effect.withoutCount) nights")
                if let g = effect.effectSize { Text("· g \(String(format: "%.2f", g))") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                if effect.isProvisional { badge("provisional", .yellow) }
                if effect.survivesFDR, !effect.interval.containsZero { badge("holds after correction", .teal) }
                if effect.interval.containsZero { badge("could be no effect", .gray) }
            }
        }
        .padding(.vertical, 4)
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2), in: .capsule)
    }
}

private struct IntervalBar: View {
    let effect: TagEffect

    var body: some View {
        let span = max(abs(effect.interval.low), abs(effect.interval.high), abs(effect.difference), 0.1) * 1.2
        Chart {
            RuleMark(x: .value("Zero", 0)).foregroundStyle(.secondary)
            BarMark(xStart: .value("Low", effect.interval.low), xEnd: .value("High", effect.interval.high),
                    y: .value("Tag", "ci"), height: 6)
                .foregroundStyle(.indigo.opacity(0.5))
            PointMark(x: .value("Difference", effect.difference), y: .value("Tag", "ci"))
                .foregroundStyle(.indigo)
        }
        .chartXScale(domain: -span...span)
        .chartYAxis(.hidden)
        .chartXAxis(.hidden)
    }
}

private struct ExperimentStatus: View {
    let experiment: SleepExperiment
    let nights: [NightRecord]
    let journals: [JournalRecord]
    let schedule: SleepSchedule

    var body: some View {
        let analytics = Analytics(nights: nights, journals: journals, schedule: schedule)
        let result = experiment.result(observations: analytics.observations())
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(experiment.title).font(.headline)
                Spacer()
                if experiment.isFinished(at: Date()) {
                    Text("Finished").font(.caption).foregroundStyle(.secondary)
                } else if let phase = experiment.phase(on: Date()) {
                    Text(phase == .intervention ? "Intervention week" : "Control week")
                        .font(.caption).foregroundStyle(.indigo)
                }
            }
            Text("\(experiment.instruction) · \(experiment.outcome.shortLabel) · ends \(experiment.end().shortDay)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let r = result {
                Text("Intervention \(String(format: "%.1f", r.interventionMean)) (\(r.interventionNights) nights) vs control \(String(format: "%.1f", r.controlMean)) (\(r.controlNights) nights): \(Format.signed(r.difference))")
                    .font(.subheadline)
                if let ci = r.interval {
                    Text("95% CI \(Format.signed(ci.low)) to \(Format.signed(ci.high))\(ci.containsZero ? ", could be no real difference" : "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Results appear once both weeks have nights logged.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct NewExperimentView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var title = "Caffeine cutoff"
    @State private var instruction = "No caffeine after 14:00"
    @State private var weeks = 2
    @State private var outcome: Outcome = .quality

    private let templates: [(String, String)] = [
        ("Caffeine cutoff", "No caffeine after 14:00"),
        ("No alcohol", "No alcohol in the evening"),
        ("Screens out", "No screens in the hour before bed"),
        ("Fixed bedtime", "In bed at your target bedtime every night"),
        ("Morning light", "15 minutes outdoors within an hour of waking"),
    ]

    var body: some View {
        Form {
            Section("Template") {
                ForEach(templates, id: \.0) { t in
                    Button {
                        title = t.0
                        instruction = t.1
                    } label: {
                        HStack {
                            Text(t.0)
                            Spacer()
                            if title == t.0 { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
            Section("Details") {
                TextField("Title", text: $title)
                TextField("What to do on intervention weeks", text: $instruction)
                Picker("Length", selection: $weeks) {
                    Text("2 weeks").tag(2)
                    Text("4 weeks").tag(4)
                    Text("6 weeks").tag(6)
                }
                Picker("Judge by", selection: $outcome) {
                    ForEach(Outcome.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }
            Section {
                Text("Week 1 is the intervention, week 2 is your normal routine, alternating. Do the morning check-in every day so there's something to compare.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("New experiment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Start") {
                    settings.experiments.append(SleepExperiment(title: title, instruction: instruction,
                                                                start: Calendar.current.startOfDay(for: Date()),
                                                                weeks: weeks, outcome: outcome))
                    dismiss()
                }
                .disabled(title.isEmpty || instruction.isEmpty)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }
}
