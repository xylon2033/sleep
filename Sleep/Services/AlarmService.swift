import ActivityKit
import AlarmKit
import Foundation
import Observation
import SleepCore
import SwiftUI

/// Wake alarms through AlarmKit (iOS 26), the only API that rings through Silent mode and Focus.
///
/// Exactly one of our alarms should exist at a time (overlapping alarms fire in a
/// non-deterministic order):
/// - no night tracked → a repeating daily alarm at the wake time;
/// - night tracked → a fixed "backstop" at the end of the wake window (the daily one is cancelled).
///
/// AlarmKit doesn't run our code when it fires and `stopIntent` isn't reliably called, so state
/// is reconciled against `AlarmManager.shared.alarms` whenever the app becomes active.
@MainActor
@Observable
final class AlarmService {
    static let shared = AlarmService()
    static let soundFile = "gentle-alarm.caf"
    static let snoozeSeconds: TimeInterval = 9 * 60

    private let manager = AlarmManager.shared
    private(set) var authorization: AlarmManager.AuthorizationState = .notDetermined
    private(set) var lastError: String?
    /// IDs of alarms we currently consider ours.
    private(set) var alarms: [Alarm] = []

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let dailyID = "alarm.daily.id"
        static let dailySignature = "alarm.daily.signature"
        static let backstopID = "alarm.backstop.id"
        static let suppressedDay = "alarm.suppressedDay"
    }

    private var updatesTask: Task<Void, Never>?
    /// Called when a backstop alarm that was alerting disappears (the user stopped it).
    var onBackstopDismissed: (() -> Void)?
    private var alertingIDs = Set<UUID>()

    private init() {
        authorization = manager.authorizationState
        alarms = (try? manager.alarms) ?? []
        updatesTask = Task { [weak self] in
            guard let updates = self?.manager.alarmUpdates else { return }
            for await list in updates {
                self?.handleUpdate(list)
            }
        }
    }

    var isAuthorized: Bool { authorization == .authorized }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            authorization = try await manager.requestAuthorization()
        } catch {
            lastError = error.localizedDescription
            authorization = manager.authorizationState
        }
        return isAuthorized
    }

    // MARK: - Night alarms

    /// Arms the fixed backstop for a tracked night and cancels the daily alarm.
    func armBackstop(at date: Date) async {
        guard await ensureAuthorized() else { return }
        cancelDaily()
        cancel(idKey: Keys.backstopID)
        let id = UUID()
        do {
            let config = configuration(schedule: .fixed(date), role: .backstop, title: "Good morning")
            _ = try await manager.schedule(id: id, configuration: config)
            defaults.set(id.uuidString, forKey: Keys.backstopID)
            lastError = nil
        } catch {
            lastError = "Couldn't set the alarm: \(error.localizedDescription)"
        }
        refresh()
    }

    /// Cancels the backstop (the user was woken by the in-app alarm or ended the night).
    func cancelBackstop() {
        cancel(idKey: Keys.backstopID)
        refresh()
    }

    var backstopID: UUID? { defaults.string(forKey: Keys.backstopID).flatMap(UUID.init) }

    // MARK: - Daily alarm

    /// Call when the app becomes active, after schedule changes, and after a night ends.
    /// - Parameter nightInProgress: the backstop stays in charge while a night is tracked.
    func reconcile(schedule: SleepSchedule, nightInProgress: Bool, now: Date = Date()) async {
        refresh()
        if nightInProgress {
            cancelDaily()
            return
        }
        // A backstop from a night that has ended is stale.
        if let id = backstopID, let alarm = alarms.first(where: { $0.id == id }), alarm.state == .scheduled {
            try? manager.cancel(id: id)
        }
        if backstopID != nil, !alarms.contains(where: { $0.id == backstopID }) {
            defaults.removeObject(forKey: Keys.backstopID)
        }

        guard schedule.alarmEnabled else {
            cancelDaily()
            refresh()
            return
        }
        guard await ensureAuthorized() else { return }

        let calendar = Calendar.current
        let todayWeekday = calendar.component(.weekday, from: now)
        var weekdays = Set(1...7)
        // Woke up already today before the alarm time (smart wake / ended early): skip today's ring.
        if defaults.string(forKey: Keys.suppressedDay) == NightKey.key(for: now.addingTimeInterval(12 * 3600)),
           let todaysWake = calendar.date(bySettingHour: schedule.wakeHour, minute: schedule.wakeMinute, second: 0, of: now),
           now < todaysWake {
            weekdays.remove(todayWeekday)
        }
        let signature = "\(schedule.wakeHour):\(schedule.wakeMinute):\(weekdays.sorted())"
        if let id = defaults.string(forKey: Keys.dailyID).flatMap(UUID.init),
           alarms.contains(where: { $0.id == id }),
           defaults.string(forKey: Keys.dailySignature) == signature {
            cancelStrays(keeping: [id])
            return
        }
        cancelDaily()
        let relative = Alarm.Schedule.Relative(
            time: .init(hour: schedule.wakeHour, minute: schedule.wakeMinute),
            repeats: .weekly(weekdays.sorted().map(Self.localeWeekday))
        )
        let id = UUID()
        do {
            _ = try await manager.schedule(id: id, configuration: configuration(schedule: .relative(relative), role: .daily, title: "Wake up"))
            defaults.set(id.uuidString, forKey: Keys.dailyID)
            defaults.set(signature, forKey: Keys.dailySignature)
            lastError = nil
        } catch {
            lastError = "Couldn't set the daily alarm: \(error.localizedDescription)"
        }
        refresh()
        cancelStrays(keeping: Set([id]))
    }

    /// Marks "already up today" so the daily alarm skips today's occurrence.
    func suppressToday(now: Date = Date()) {
        defaults.set(NightKey.key(for: now.addingTimeInterval(12 * 3600)), forKey: Keys.suppressedDay)
    }

    var nextAlarmDate: Date? {
        alarms.compactMap { alarm -> Date? in
            switch alarm.schedule {
            case .fixed(let date): return date
            case .relative(let relative):
                let comps = DateComponents(hour: relative.time.hour, minute: relative.time.minute)
                return Calendar.current.nextDate(after: Date(), matching: comps, matchingPolicy: .nextTime)
            default: return nil
            }
        }.min()
    }

    // MARK: - Helpers

    private func ensureAuthorized() async -> Bool {
        authorization = manager.authorizationState
        if authorization == .notDetermined { return await requestAuthorization() }
        if authorization == .denied { lastError = "Alarms are turned off for this app in Settings." }
        return isAuthorized
    }

    private func configuration(schedule: Alarm.Schedule, role: SleepAlarmMetadata.Role, title: LocalizedStringResource)
        -> AlarmManager.AlarmConfiguration<SleepAlarmMetadata> {
        let stop = AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.circle")
        let snooze = AlarmButton(text: "Snooze", textColor: .white, systemImageName: "zzz")
        let alert = AlarmPresentation.Alert(title: title, stopButton: stop, secondaryButton: snooze,
                                            secondaryButtonBehavior: .countdown)
        let countdown = AlarmPresentation.Countdown(title: "Snoozing", pauseButton: nil)
        let attributes = AlarmAttributes(presentation: AlarmPresentation(alert: alert, countdown: countdown),
                                         metadata: SleepAlarmMetadata(role: role), tintColor: .indigo)
        return AlarmManager.AlarmConfiguration(
            countdownDuration: Alarm.CountdownDuration(preAlert: nil, postAlert: Self.snoozeSeconds),
            schedule: schedule,
            attributes: attributes,
            sound: .named(Self.soundFile)
        )
    }

    private func cancelDaily() {
        cancel(idKey: Keys.dailyID)
        defaults.removeObject(forKey: Keys.dailySignature)
    }

    private func cancel(idKey: String) {
        if let id = defaults.string(forKey: idKey).flatMap(UUID.init) {
            try? manager.cancel(id: id)
        }
        defaults.removeObject(forKey: idKey)
    }

    /// Cancels alarms we no longer track (e.g. left over after a crash), but never one that is
    /// ringing or snoozed right now.
    private func cancelStrays(keeping keep: Set<UUID>) {
        for alarm in alarms where !keep.contains(alarm.id) && alarm.id != backstopID && alarm.state == .scheduled {
            try? manager.cancel(id: alarm.id)
        }
        refresh()
    }

    private func refresh() {
        alarms = (try? manager.alarms) ?? []
        authorization = manager.authorizationState
    }

    private func handleUpdate(_ list: [Alarm]) {
        alarms = list
        let alerting = Set(list.filter { $0.state == .alerting }.map(\.id))
        if let backstop = backstopID, alertingIDs.contains(backstop), !list.contains(where: { $0.id == backstop }) {
            // The backstop rang and has now been stopped (not snoozed, which keeps it in the list).
            onBackstopDismissed?()
        }
        alertingIDs.formUnion(alerting)
    }

    static func localeWeekday(_ calendarWeekday: Int) -> Locale.Weekday {
        switch calendarWeekday {
        case 1: .sunday
        case 2: .monday
        case 3: .tuesday
        case 4: .wednesday
        case 5: .thursday
        case 6: .friday
        default: .saturday
        }
    }
}
