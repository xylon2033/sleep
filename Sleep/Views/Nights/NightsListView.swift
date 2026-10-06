import SleepCore
import SwiftData
import SwiftUI

struct NightsListView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<NightRecord> { $0.inBedEnd != nil }, sort: \NightRecord.inBedStart, order: .reverse)
    private var nights: [NightRecord]
    @Query private var journals: [JournalRecord]
    @State private var showManual = false

    var body: some View {
        List {
            if nights.isEmpty {
                ContentUnavailableView("No nights yet", systemImage: "moon.zzz",
                                       description: Text("Start a night from the Tonight tab, or log one manually."))
            }
            ForEach(nights) { night in
                NavigationLink {
                    MorningReportView(night: night, promptCheckIn: false)
                } label: {
                    NightRow(night: night, journal: journals.first { $0.nightKey == night.nightKey })
                }
            }
            .onDelete { offsets in
                for i in offsets { context.delete(nights[i]) }
                try? context.save()
            }
        }
        .navigationTitle("Nights")
        .toolbar {
            Button {
                showManual = true
            } label: {
                Label("Log a night", systemImage: "plus")
            }
        }
        .sheet(isPresented: $showManual) {
            NavigationStack { ManualNightView() }
        }
    }
}

private struct NightRow: View {
    let night: NightRecord
    let journal: JournalRecord?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(night.inBedStart.shortDay)
                    .font(.headline)
                HStack(spacing: 6) {
                    Text("\(Format.clock(night.inBedStart))–\(Format.clock(night.inBedEnd ?? night.inBedStart))")
                    if night.isManual { Text("manual").font(.caption2).foregroundStyle(.secondary) }
                    if (night.summary?.gapMinutes ?? 0) > 5 {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange).font(.caption)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let s = night.summary {
                    Text(Format.duration(s.totalSleep))
                        .font(.headline)
                        .monospacedDigit()
                }
                if let c = journal?.checkIn {
                    Text(MorningCheckIn.moodEmoji[max(0, min(4, c.mood - 1))])
                }
            }
        }
    }
}
