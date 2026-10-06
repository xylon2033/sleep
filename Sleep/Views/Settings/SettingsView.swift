import SleepCore
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @Query(sort: \NightRecord.inBedStart) private var nights: [NightRecord]
    @Query private var journals: [JournalRecord]
    @State private var exportURLs: [URL] = []
    @State private var confirmDelete = false

    private var wakeBinding: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: settings.schedule.wakeHour, minute: settings.schedule.wakeMinute, second: 0, of: Date()) ?? Date()
        } set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            settings.schedule.wakeHour = c.hour ?? 7
            settings.schedule.wakeMinute = c.minute ?? 0
        }
    }

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                DatePicker("Wake time (every day)", selection: wakeBinding, displayedComponents: .hourAndMinute)
                Stepper("Sleep goal: \(Format.duration(Double(settings.schedule.sleepGoalMinutes) * 60))",
                        value: $settings.schedule.sleepGoalMinutes, in: 300...660, step: 15)
                LabeledContent("Target bedtime", value: Format.clock(minutesAfterMidnight: Double(settings.schedule.targetBedtimeMinutes)))
            } header: {
                Text("Schedule")
            } footer: {
                Text("A fixed wake time seven days a week is the anchor. Bedtime is coached towards wake − goal in 15-minute steps.")
            }

            Section {
                Toggle("Wake alarm", isOn: $settings.schedule.alarmEnabled)
                Toggle("Gentle wake window", isOn: $settings.schedule.smartWakeEnabled)
                if settings.schedule.smartWakeEnabled {
                    Stepper("Window: \(settings.schedule.smartWakeWindowMinutes) min",
                            value: $settings.schedule.smartWakeWindowMinutes, in: 10...45, step: 5)
                }
            } header: {
                Text("Alarm")
            } footer: {
                Text("The alarm uses AlarmKit, so it rings through Silent and Focus at your ringer volume (set it up in Settings → Sounds; volume buttons dismiss it). The gentle window plays a fading-in melody in the app if you're stirring; it promises a gentler wake inside a window, not detection of light sleep.")
            }

            Section("Reminders") {
                Toggle("Wind-down", isOn: $settings.schedule.windDownEnabled)
                if settings.schedule.windDownEnabled {
                    Stepper("\(settings.schedule.windDownLeadMinutes) min before bed",
                            value: $settings.schedule.windDownLeadMinutes, in: 15...90, step: 15)
                }
                Toggle("Bedtime: start your night", isOn: $settings.schedule.bedtimeReminderEnabled)
                Toggle("Caffeine cutoff", isOn: $settings.schedule.caffeineReminderEnabled)
                if settings.schedule.caffeineReminderEnabled {
                    Stepper("\(settings.schedule.caffeineCutoffHoursBeforeBed) h before bed",
                            value: $settings.schedule.caffeineCutoffHoursBeforeBed, in: 4...12)
                }
                Toggle("Morning light", isOn: $settings.schedule.morningLightEnabled)
            }

            Section {
                ForEach(1...7, id: \.self) { weekday in
                    let symbol = Calendar.current.weekdaySymbols[weekday - 1]
                    Toggle(symbol, isOn: Binding(
                        get: { settings.schedule.freeWeekdays.contains(weekday) },
                        set: { on in
                            if on { settings.schedule.freeWeekdays.insert(weekday) } else { settings.schedule.freeWeekdays.remove(weekday) }
                        }
                    ))
                }
            } header: {
                Text("Free days")
            } footer: {
                Text("Days you wake up without work, used for social jetlag. A night counts as free when the morning after is free. Override single nights from their report; a Late shift tag excludes a night.")
            }

            Section {
                VStack(alignment: .leading) {
                    Text("Detection sensitivity")
                    Slider(value: $settings.tracking.thresholdDb, in: 3...12, step: 1) {
                        Text("Sensitivity")
                    } minimumValueLabel: {
                        Text("More").font(.caption)
                    } maximumValueLabel: {
                        Text("Less").font(.caption)
                    }
                    Text("A sound counts when it's \(Int(settings.tracking.thresholdDb)) dB above the room's background.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Detect snoring, talking, coughs", isOn: $settings.tracking.detectEvents)
                Toggle("Save short snore/talk clips", isOn: $settings.tracking.saveClips)
                if settings.tracking.saveClips {
                    Button("Delete all clips", role: .destructive) { ClipStore.deleteAll() }
                }
            } header: {
                Text("Tracking")
            } footer: {
                Text("Audio is analysed on the phone and only derived features are kept. Clips are off by default, capped at 5 per night, and deleted after 30 days.")
            }

            Section {
                Toggle("Save nights to Apple Health", isOn: Binding(
                    get: { settings.tracking.healthKitEnabled },
                    set: { on in
                        settings.tracking.healthKitEnabled = on
                        if on { Task { settings.tracking.healthKitEnabled = await HealthService.requestAuthorization() } }
                    }
                ))
                .disabled(!HealthService.isAvailable)
            } header: {
                Text("Health")
            } footer: {
                Text("Writes \"in bed\" and \"asleep\" only, never REM/deep stages: a phone's audio estimate isn't sleep staging.")
            }

            Section("Data") {
                Button("Export CSV + JSON") {
                    exportURLs = (try? Exporter.export(nights: nights, journals: journals)) ?? []
                }
                if !exportURLs.isEmpty {
                    ShareLink(items: exportURLs) {
                        Label("Share export", systemImage: "square.and.arrow.up")
                    }
                }
                Button("Delete all sleep data", role: .destructive) { confirmDelete = true }
            }

            Section("About") {
                Text("This app estimates sleep from sound. Phone apps track time in bed reasonably well but cannot stage sleep. Use it to spot trends in your own data, not for diagnosis.")
                Text("Loud, frequent snoring with daytime sleepiness deserves a sleep-apnea evaluation; the snore data here can prompt one but can't rule it out.")
                Text("Alarm reliability: build with a paid developer account. A free provisioning profile expires after 7 days and the app (and its alarm) stops launching until you rebuild.")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .navigationTitle("Settings")
        .confirmationDialog("Delete every night, tag and check-in?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) {
                try? context.delete(model: NightRecord.self)
                try? context.delete(model: JournalRecord.self)
                try? context.save()
                ClipStore.deleteAll()
            }
        }
    }
}
