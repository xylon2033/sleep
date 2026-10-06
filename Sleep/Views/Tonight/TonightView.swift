import SleepCore
import SwiftData
import SwiftUI

struct TonightView: View {
    @Environment(NightSession.self) private var session
    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    @Query(sort: \NightRecord.inBedStart, order: .reverse) private var nights: [NightRecord]
    @State private var showManual = false
    @State private var starting = false
    @State private var alarmOn = true
    @State private var smartWake = false

    private var tonightKey: String { NightKey.key(for: Date()) }

    private var suggestion: BedtimeCoach.Suggestion {
        let beds = nights.filter { !$0.isInProgress }.prefix(7).map(\.inBedStart)
        return BedtimeCoach().suggestion(schedule: settings.schedule, recentBedtimes: Array(beds))
    }

    private var nextWake: Date { settings.schedule.nextWake(after: Date()) }

    var body: some View {
        @Bindable var settings = settings
        ScrollView {
            VStack(spacing: 16) {
                if let orphan = session.orphan {
                    orphanBanner(orphan)
                }
                scheduleCard
                if let experiment = settings.activeExperiment,
                   let phase = experiment.phase(on: Date()) {
                    experimentBanner(experiment, phase: phase)
                }
                Card(title: "Tonight's tags", systemImage: "tag") {
                    EveningTagsView(nightKey: tonightKey)
                }
                Card(title: "Sleep sounds", systemImage: "speaker.wave.2") {
                    SoundPicker(sounds: $settings.sounds)
                }
                alarmCard
                if let error = session.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.footnote)
                }
                if !session.isCharging {
                    Label("Plug in your phone. A night of listening uses a meaningful chunk of battery, and charging avoids Low Power Mode interfering.",
                          systemImage: "battery.25")
                        .font(.footnote)
                        .foregroundStyle(.yellow)
                }
                startButton
                Button("Log a night manually") { showManual = true }
                    .font(.footnote)
                    .padding(.bottom)
            }
            .padding()
        }
        .navigationTitle("Tonight")
        .sheet(isPresented: $showManual) {
            NavigationStack { ManualNightView() }
        }
        .onAppear {
            alarmOn = settings.schedule.alarmEnabled
            smartWake = settings.schedule.smartWakeEnabled
        }
        .onChange(of: router.pendingStartNight, initial: true) { _, pending in
            guard pending else { return }
            router.pendingStartNight = false
            if !session.isActive { Task { await start() } }
        }
    }

    // MARK: - Sections

    private var scheduleCard: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading) {
                    Text("Bedtime").font(.caption).foregroundStyle(.secondary)
                    Text(Format.clock(minutesAfterMidnight: suggestion.bedtimeMinutes))
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Wake").font(.caption).foregroundStyle(.secondary)
                    Text(Format.clock(nextWake))
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
            }
            Text(suggestion.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Same wake time every day, weekends too. That's the anchor.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var alarmCard: some View {
        Card(title: "Alarm", systemImage: "alarm") {
            Toggle("Wake alarm at \(Format.clock(nextWake))", isOn: $alarmOn)
            if alarmOn {
                Toggle("Gentle wake window (\(settings.schedule.smartWakeWindowMinutes) min)", isOn: $smartWake)
                Text(smartWake
                     ? "If you're stirring in the window, a soft melody fades in. The system alarm at \(Format.clock(nextWake)) is the backstop and always rings."
                     : "A system alarm that rings through Silent mode and Focus.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error = AlarmService.shared.lastError {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var startButton: some View {
        Button {
            Task { await start() }
        } label: {
            Label(starting ? "Starting…" : "Start Night", systemImage: "moon.zzz.fill")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(starting || session.isActive || session.orphan != nil)
    }

    private func orphanBanner(_ night: NightRecord) -> some View {
        Card(title: "Tracking was interrupted", systemImage: "exclamationmark.arrow.circlepath") {
            Text("The night that started at \(Format.clock(night.inBedStart)) stopped recording at \(Format.clock(night.lastHeartbeat ?? night.inBedStart)). The gap will show in your report.")
                .font(.subheadline)
            HStack {
                Button("Resume tracking") { Task { await session.resumeOrphan() } }
                    .buttonStyle(.borderedProminent)
                Button("End night") { session.endOrphan() }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func experimentBanner(_ e: SleepExperiment, phase: SleepExperiment.Phase) -> some View {
        Card(title: "Experiment: \(e.title)", systemImage: "flask") {
            Text(phase == .intervention ? "This week: \(e.instruction)." : "Control week: sleep as you normally would.")
                .font(.subheadline)
        }
    }

    private func start() async {
        starting = true
        defer { starting = false }
        let sounds = settings.sounds
        let options = NightSession.StartOptions(
            sound: sounds.kind, soundVolume: sounds.volume, soundTimerMinutes: sounds.timerMinutes,
            alarmEnabled: alarmOn, wakeTime: nextWake, smartWake: smartWake,
            smartWindowMinutes: settings.schedule.smartWakeWindowMinutes
        )
        await session.startNight(options: options)
    }
}

struct SoundPicker: View {
    @Binding var sounds: SoundSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Sound", selection: $sounds.kind) {
                ForEach(NoiseKind.allCases) { kind in
                    Label(kind.label, systemImage: kind.systemImage).tag(kind)
                }
            }
            if sounds.kind != .off {
                HStack {
                    Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                    Slider(value: $sounds.volume, in: 0.05...1)
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                }
                Picker("Fade out after", selection: $sounds.timerMinutes) {
                    ForEach(SoundSettings.timerChoices, id: \.self) { m in
                        Text(m == 0 ? "All night (masking)" : "\(m) min").tag(m)
                    }
                }
                Text(sounds.timerMinutes == 0
                     ? "All-night noise is for masking a noisy room. In a 2026 lab study, constant pink noise cut REM sleep."
                     : "Sounds help you fall asleep, then fade out so they don't play all night.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
