import AppIntents
import SleepCore
import SwiftData

/// "Start Night": opens the app (recording must begin in the foreground) and starts tracking with
/// tonight's defaults. Usable from Shortcuts, Siri, or a bedtime Focus automation.
struct StartNightIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Night"
    static let description = IntentDescription("Opens the app and starts tonight's sleep tracking and alarm.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.tab = .tonight
        AppRouter.shared.pendingStartNight = true
        return .result()
    }
}

enum TagOption: String, AppEnum {
    case caffeine, alcohol, exercise, lateScreens, stress, lateMeal, nap, lateShift, sick, travel

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Sleep tag"
    static let caseDisplayRepresentations: [TagOption: DisplayRepresentation] = [
        .caffeine: "Caffeine",
        .alcohol: "Alcohol",
        .exercise: "Exercise",
        .lateScreens: "Late screens",
        .stress: "Stress",
        .lateMeal: "Late meal",
        .nap: "Nap",
        .lateShift: "Late shift",
        .sick: "Sick",
        .travel: "Travel",
    ]
}

/// "Log Tag": adds an evening tag to tonight's journal without opening the app.
/// Caffeine and exercise get the current time; alcohol adds one drink.
struct LogTagIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Sleep Tag"
    static let description = IntentDescription("Adds a tag such as caffeine or alcohol to tonight's sleep journal.")

    @Parameter(title: "Tag")
    var tag: TagOption

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = Persistence.container.mainContext
        let key = NightKey.key(for: Date())
        guard let journal = Persistence.journal(for: key, in: context) else { return .result(dialog: "Couldn't open the journal.") }
        var tags = journal.tags
        let existing = tags.first { $0.key == tag.rawValue }
        tags.removeAll { $0.key == tag.rawValue }
        switch tag {
        case .caffeine, .exercise:
            tags.append(TagEntry(key: tag.rawValue, time: Date()))
        case .alcohol:
            tags.append(TagEntry(key: tag.rawValue, amount: (existing?.amount ?? 0) + 1))
        case .stress:
            tags.append(TagEntry(key: tag.rawValue, amount: existing?.amount ?? 3))
        default:
            tags.append(TagEntry(key: tag.rawValue))
        }
        journal.tags = tags
        try context.save()
        let label = BuiltInTag(rawValue: tag.rawValue)?.label ?? tag.rawValue
        return .result(dialog: "Logged \(label) for tonight.")
    }
}

struct SleepShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartNightIntent(), phrases: [
            "Start night in \(.applicationName)",
            "Start sleep tracking in \(.applicationName)",
        ], shortTitle: "Start Night", systemImageName: "moon.zzz.fill")
        AppShortcut(intent: LogTagIntent(), phrases: [
            "Log a tag in \(.applicationName)",
            "Log \(\.$tag) in \(.applicationName)",
        ], shortTitle: "Log Tag", systemImageName: "tag")
    }
}
