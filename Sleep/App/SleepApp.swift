import SleepCore
import SwiftData
import SwiftUI

@main
struct SleepApp: App {
    @State private var session = NightSession(context: Persistence.container.mainContext)
    @State private var settings = AppSettings.shared
    @State private var router = AppRouter.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(settings)
                .environment(router)
                .preferredColorScheme(.dark)
        }
        .modelContainer(Persistence.container)
    }
}

/// Cross-cutting navigation and requests coming from App Intents / notifications.
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()

    enum TabID: Hashable { case tonight, nights, trends, insights, settings }

    var tab: TabID = .tonight
    /// Set by the Start Night shortcut; Tonight view picks it up and starts with current defaults.
    var pendingStartNight = false

    private init() {}
}
