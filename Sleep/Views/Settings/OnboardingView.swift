import SleepCore
import SwiftUI

struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings
    @State private var step = 0
    @State private var wake = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var goalMinutes = 480

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                switch step {
                case 0: intro
                case 1: schedule
                default: permissions
                }
                Spacer()
            }
            .padding(24)
            .navigationTitle(["Welcome", "Your schedule", "Permissions"][min(step, 2)])
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 16) {
            point("metronome", "Regularity first", "The same wake time every day is the strongest lever. Regularity is the headline metric here.")
            point("tag", "Tag your evenings", "Caffeine, alcohol, screens, stress… The app compares your nights with and without each tag once there's enough data.")
            point("waveform", "Listens, doesn't record", "At night the microphone measures movement and detects snoring. Only derived numbers are kept, and they stay on your phone.")
            point("alarm", "An alarm you can trust", "A system alarm that rings through Silent and Focus, with an optional gentle window before it.")
            Button("Continue") { step = 1 }
                .buttonStyle(.borderedProminent)
                .padding(.top)
        }
    }

    private var schedule: some View {
        VStack(alignment: .leading, spacing: 16) {
            DatePicker("Wake time", selection: $wake, displayedComponents: .hourAndMinute)
            Stepper("Sleep goal: \(Format.duration(Double(goalMinutes) * 60))", value: $goalMinutes, in: 300...660, step: 15)
            Text("Target bedtime: \(Format.clock(wake.addingTimeInterval(-Double(goalMinutes) * 60)))")
                .foregroundStyle(.secondary)
            Button("Continue") {
                let c = Calendar.current.dateComponents([.hour, .minute], from: wake)
                settings.schedule.wakeHour = c.hour ?? 7
                settings.schedule.wakeMinute = c.minute ?? 0
                settings.schedule.sleepGoalMinutes = goalMinutes
                step = 2
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("The app needs three permissions. You can change them later in Settings.")
                .foregroundStyle(.secondary)
            point("bell", "Notifications", "Wind-down, caffeine cutoff and bedtime nudges.")
            point("alarm", "Alarms", "To ring through Silent mode and Focus.")
            point("mic", "Microphone", "Asked the first time you start a night.")
            Button("Allow and finish") {
                Task {
                    _ = await ReminderService.requestAuthorization()
                    _ = await AlarmService.shared.requestAuthorization()
                    settings.hasOnboarded = true
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func point(_ image: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: image)
                .font(.title2)
                .foregroundStyle(.indigo)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
