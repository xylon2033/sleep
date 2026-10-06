import SleepCore
import SwiftData
import SwiftUI

/// One-tap pre-sleep tags. Time-sensitive tags (caffeine, exercise) record a time,
/// alcohol a drink count, stress a 1–5 level.
struct EveningTagsView: View {
    let nightKey: String
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query private var journals: [JournalRecord]
    @State private var editing: BuiltInTag?
    @State private var newCustom = ""
    @State private var addingCustom = false

    init(nightKey: String) {
        self.nightKey = nightKey
        _journals = Query(filter: #Predicate<JournalRecord> { $0.nightKey == nightKey })
    }

    private var tags: [TagEntry] { journals.first?.tags ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlowLayout(spacing: 8) {
                ForEach(BuiltInTag.allCases, id: \.self) { tag in
                    let entry = tags.first { $0.key == tag.rawValue }
                    Chip(title: tag.label, systemImage: tag.systemImage, isOn: entry != nil, detail: detail(for: entry)) {
                        tap(tag, entry: entry)
                    }
                }
                ForEach(settings.customTags, id: \.self) { name in
                    let key = TagEntry.customKey(name)
                    let isOn = tags.contains { $0.key == key }
                    Chip(title: name, systemImage: "tag", isOn: isOn) {
                        toggle(key: key, isOn: isOn)
                    }
                }
                Chip(title: "Custom", systemImage: "plus", isOn: false) { addingCustom = true }
            }
        }
        .sheet(item: $editing) { tag in
            TagDetailSheet(tag: tag, entry: tags.first { $0.key == tag.rawValue }) { entry in
                upsert(entry)
            } onRemove: {
                remove(key: tag.rawValue)
            }
            .presentationDetents([.height(320)])
        }
        .alert("New tag", isPresented: $addingCustom) {
            TextField("e.g. Melatonin", text: $newCustom)
            Button("Add") {
                let name = newCustom.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty, !settings.customTags.contains(name) {
                    settings.customTags.append(name)
                    upsert(TagEntry(key: TagEntry.customKey(name)))
                }
                newCustom = ""
            }
            Button("Cancel", role: .cancel) { newCustom = "" }
        }
    }

    private func detail(for entry: TagEntry?) -> String? {
        guard let entry, let tag = entry.builtIn else { return nil }
        switch tag.input {
        case .timed: return entry.time.map(Format.clock)
        case .count: return entry.amount.map { "×\($0)" }
        case .scale: return entry.amount.map { "\($0)/5" }
        case .toggle: return nil
        }
    }

    private func tap(_ tag: BuiltInTag, entry: TagEntry?) {
        if tag.input == .toggle {
            toggle(key: tag.rawValue, isOn: entry != nil)
        } else {
            editing = tag
        }
    }

    private func toggle(key: String, isOn: Bool) {
        if isOn { remove(key: key) } else { upsert(TagEntry(key: key)) }
    }

    private func upsert(_ entry: TagEntry) {
        guard let journal = Persistence.journal(for: nightKey, in: context) else { return }
        var list = journal.tags.filter { $0.key != entry.key }
        list.append(entry)
        journal.tags = list
        try? context.save()
    }

    private func remove(key: String) {
        guard let journal = Persistence.journal(for: nightKey, in: context, create: false) else { return }
        journal.tags = journal.tags.filter { $0.key != key }
        try? context.save()
    }
}

private struct TagDetailSheet: View {
    let tag: BuiltInTag
    let entry: TagEntry?
    var onSave: (TagEntry) -> Void
    var onRemove: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var time = Date()
    @State private var amount = 1

    var body: some View {
        NavigationStack {
            Form {
                switch tag.input {
                case .timed:
                    DatePicker(tag == .caffeine ? "Last caffeine" : "Time", selection: $time, displayedComponents: .hourAndMinute)
                    if tag == .caffeine {
                        Text("Caffeine's half-life is around 5 hours, so an afternoon coffee is still partly active at bedtime.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                case .count:
                    Stepper("Drinks: \(amount)", value: $amount, in: 1...12)
                case .scale:
                    Picker("Stress", selection: $amount) {
                        ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                case .toggle:
                    EmptyView()
                }
                if entry != nil {
                    Button("Remove tag", role: .destructive) {
                        onRemove()
                        dismiss()
                    }
                }
            }
            .navigationTitle(tag.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        switch tag.input {
                        case .timed: onSave(TagEntry(key: tag.rawValue, time: time))
                        case .count, .scale: onSave(TagEntry(key: tag.rawValue, amount: amount))
                        case .toggle: onSave(TagEntry(key: tag.rawValue))
                        }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                time = entry?.time ?? Date()
                amount = entry?.amount ?? (tag == .stress ? 3 : 1)
            }
        }
    }
}
