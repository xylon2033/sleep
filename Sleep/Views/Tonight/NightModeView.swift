import Charts
import SleepCore
import SwiftUI

/// Full-screen, dark night view shown while a night is tracked.
struct NightModeView: View {
    @Environment(NightSession.self) private var session
    @Environment(AppSettings.self) private var settings
    @State private var confirmEnd = false
    @State private var showSounds = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            ZStack {
                Color.black.ignoresSafeArea()
                if session.phase == .ringing {
                    ringing
                } else {
                    running(now: context.date)
                }
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
    }

    private func running(now: Date) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Text(now, format: .dateTime.hour().minute())
                .font(.system(size: 84, weight: .thin, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.75))
            if let alarm = session.record?.alarmTime {
                let window = session.record?.smartWakeWindowMinutes ?? 0
                Label(window > 0
                      ? "Gentle wake \(Format.clock(alarm.addingTimeInterval(-Double(window) * 60)))–\(Format.clock(alarm))"
                      : "Alarm \(Format.clock(alarm))",
                      systemImage: "alarm")
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                Label("No alarm", systemImage: "alarm.waves.left.and.right")
                    .foregroundStyle(.white.opacity(0.4))
            }
            status
            if !session.epochs.isEmpty {
                ActivitySparkline(epochs: Array(session.epochs.suffix(120)))
                    .frame(height: 60)
                    .padding(.horizontal, 32)
                    .opacity(0.5)
            }
            Spacer()
            HStack(spacing: 16) {
                Button {
                    showSounds = true
                } label: {
                    Label("Sounds", systemImage: "speaker.wave.2")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button {
                    confirmEnd = true
                } label: {
                    Label("End Night", systemImage: "sun.max")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
            .tint(.indigo)
            .padding(.horizontal, 24)
            Text("Leave the app open, lock the phone and place it near your pillow, plugged in.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.35))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 12)
        }
        .confirmationDialog("End the night now?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End Night") { session.endNight(reason: .user) }
            Button("Keep tracking", role: .cancel) {}
        } message: {
            Text("Your alarm will be cancelled for this morning.")
        }
        .sheet(isPresented: $showSounds) {
            NightSoundSheet()
                .presentationDetents([.medium])
        }
    }

    @ViewBuilder
    private var status: some View {
        switch session.phase {
        case .interrupted:
            VStack(spacing: 8) {
                Label("Recording paused by another app or a call", systemImage: "mic.slash")
                    .foregroundStyle(.orange)
                Text("Tracking resumes automatically when possible. Your alarm is still set.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
        default:
            HStack(spacing: 14) {
                Label("Listening", systemImage: "waveform")
                if !session.isCharging {
                    Label("Not charging", systemImage: "battery.25").foregroundStyle(.yellow)
                }
                if let last = session.events.last(where: { $0.kind == .snoring }) {
                    Label("Snore \(Format.clock(last.start))", systemImage: "zzz")
                }
            }
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.45))
        }
    }

    private var ringing: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "sun.horizon.fill")
                .font(.system(size: 72))
                .foregroundStyle(.orange.gradient)
            Text("Good morning")
                .font(.largeTitle.weight(.semibold))
            Text("You were stirring, so this is a gentle start. Your system alarm will be cancelled.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Spacer()
            Button {
                session.stopGentleAlarm()
            } label: {
                Text("I'm up")
                    .font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
    }
}

private struct NightSoundSheet: View {
    @Environment(NightSession.self) private var session
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                SoundPicker(sounds: $settings.sounds)
            }
            .navigationTitle("Sleep sounds")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: settings.sounds.kind) { _, _ in apply() }
            .onChange(of: settings.sounds.timerMinutes) { _, _ in apply() }
            .onChange(of: settings.sounds.volume) { _, v in session.setSoundVolume(v) }
        }
    }

    private func apply() {
        let s = settings.sounds
        session.changeSound(kind: s.kind, volume: s.volume, timerMinutes: s.timerMinutes)
    }
}

/// Tiny activity chart for the in-progress night.
struct ActivitySparkline: View {
    let epochs: [EpochFeatures]

    var body: some View {
        Chart(epochs, id: \.start) { e in
            BarMark(x: .value("Time", e.start), y: .value("Activity", min(e.activity, 10)))
                .foregroundStyle(.indigo.gradient)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...10)
    }
}
