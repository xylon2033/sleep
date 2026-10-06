import SleepCore
import SwiftData
import SwiftUI

/// The under-15-second morning check-in.
struct CheckInView: View {
    let nightKey: String
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var checkIn = MorningCheckIn()

    var body: some View {
        NavigationStack {
            Form {
                Section("Wake mood") {
                    HStack {
                        ForEach(1...5, id: \.self) { value in
                            Button {
                                checkIn.mood = value
                            } label: {
                                Text(MorningCheckIn.moodEmoji[value - 1])
                                    .font(.system(size: 34))
                                    .opacity(checkIn.mood == value ? 1 : 0.35)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section("Sleep quality") {
                    Picker("Quality", selection: $checkIn.quality) {
                        ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Time to fall asleep") {
                    Picker("Latency", selection: $checkIn.latency) {
                        ForEach(LatencyBucket.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Times you woke up") {
                    Picker("Awakenings", selection: $checkIn.awakenings) {
                        Text("0").tag(0)
                        Text("1").tag(1)
                        Text("2").tag(2)
                        Text("3+").tag(3)
                    }
                    .pickerStyle(.segmented)
                }
                Section("Notes") {
                    TextField("Anything notable?", text: $checkIn.notes, axis: .vertical)
                }
                if checkIn.latency.isLong {
                    Section {
                        Label("If you're awake for more than ~20 minutes, get up and do something calm in dim light, then go back to bed when sleepy. Lying awake in bed teaches your brain that bed is for being awake.",
                              systemImage: "lightbulb")
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Good morning")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let journal = Persistence.journal(for: nightKey, in: context) {
                            journal.checkIn = checkIn
                            try? context.save()
                        }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") { dismiss() }
                }
            }
            .onAppear {
                if let existing = Persistence.journal(for: nightKey, in: context, create: false)?.checkIn {
                    checkIn = existing
                }
            }
        }
    }
}

/// Log a night by hand (no tracking): bed and wake times only.
struct ManualNightView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var bed = Calendar.current.date(bySettingHour: 23, minute: 0, second: 0,
                                                    of: Date().addingTimeInterval(-86_400)) ?? Date()
    @State private var wake = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var latency: LatencyBucket = .tenTo20

    var body: some View {
        Form {
            DatePicker("In bed", selection: $bed)
            DatePicker("Out of bed", selection: $wake)
            Picker("Time to fall asleep", selection: $latency) {
                ForEach(LatencyBucket.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            if wake <= bed {
                Text("Out of bed must be after in bed.").foregroundStyle(.orange)
            }
        }
        .navigationTitle("Log a night")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.disabled(wake <= bed)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private func save() {
        let night = NightRecord(inBedStart: bed, source: .manual)
        night.inBedEnd = wake
        night.summary = SleepEstimator.manualSummary(inBed: bed, outOfBed: wake, latencyMinutes: latency.minutes)
        context.insert(night)
        try? context.save()
        dismiss()
    }
}
