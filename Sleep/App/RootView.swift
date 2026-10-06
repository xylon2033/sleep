import SleepCore
import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(NightSession.self) private var session
    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @Query(sort: \NightRecord.inBedStart, order: .reverse) private var nights: [NightRecord]

    var body: some View {
        @Bindable var router = router
        @Bindable var session = session
        TabView(selection: $router.tab) {
            Tab("Tonight", systemImage: "moon.stars.fill", value: AppRouter.TabID.tonight) {
                NavigationStack { TonightView() }
            }
            Tab("Nights", systemImage: "list.bullet.rectangle", value: AppRouter.TabID.nights) {
                NavigationStack { NightsListView() }
            }
            Tab("Trends", systemImage: "chart.xyaxis.line", value: AppRouter.TabID.trends) {
                NavigationStack { TrendsView() }
            }
            Tab("Insights", systemImage: "lightbulb.max", value: AppRouter.TabID.insights) {
                NavigationStack { InsightsView() }
            }
            Tab("Settings", systemImage: "gearshape", value: AppRouter.TabID.settings) {
                NavigationStack { SettingsView() }
            }
        }
        .tint(.indigo)
        .fullScreenCover(isPresented: Binding(get: { session.isActive }, set: { _ in })) {
            NightModeView()
        }
        .sheet(item: $session.justFinished) { night in
            NavigationStack {
                MorningReportView(night: night, promptCheckIn: true)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { session.justFinished = nil }
                        }
                    }
            }
        }
        .sheet(isPresented: Binding(get: { !settings.hasOnboarded }, set: { _ in })) {
            OnboardingView()
                .interactiveDismissDisabled()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            session.appBecameActive()
            Task { await refreshPlans() }
        }
        .onChange(of: settings.schedule) { _, _ in
            Task { await refreshPlans() }
        }
        .task {
            ClipStore.purge()
        }
    }

    /// Re-plans reminders around tonight's coached bedtime and reconciles AlarmKit.
    private func refreshPlans() async {
        let schedule = settings.schedule
        let recentBeds = nights.filter { !$0.isInProgress }.prefix(7).map(\.inBedStart)
        let suggestion = BedtimeCoach().suggestion(schedule: schedule, recentBedtimes: Array(recentBeds))
        await ReminderService.reschedule(schedule: schedule, bedtimeMinutes: suggestion.bedtimeMinutes)
        guard settings.hasOnboarded else { return }
        await AlarmService.shared.reconcile(schedule: schedule, nightInProgress: session.isActive)
    }
}
