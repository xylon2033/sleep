import Foundation
import SleepCore
import UserNotifications

/// Informational nudges (wind-down, caffeine cutoff, bedtime, morning light) as ordinary local
/// notifications. AlarmKit is kept for the wake alarm only.
@MainActor
enum ReminderService {
    static let prefix = "reminder."

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Replaces all pending reminders with a fresh 7-day plan built around tonight's coached bedtime.
    static func reschedule(schedule: SleepSchedule, bedtimeMinutes: Double, now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let plan = ReminderPlanner.plan(schedule: schedule, bedtimeMinutes: bedtimeMinutes, from: now, days: 7)
        for reminder in plan {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            content.threadIdentifier = reminder.kind.rawValue
            if reminder.kind == .bedtime { content.userInfo = ["action": "startNight"] }
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger))
        }
    }

    /// Shown when the in-app gentle alarm starts, so there's something on the Lock Screen to tap.
    static func postSmartWakeNotice() {
        let content = UNMutableNotificationContent()
        content.title = "Good morning"
        content.body = "Your gentle alarm is playing. Open the app to stop it."
        content.interruptionLevel = .timeSensitive
        content.userInfo = ["action": "stopAlarm"]
        let request = UNNotificationRequest(identifier: "smartwake.\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// A banner if recording stopped during the night and couldn't recover on its own.
    static func postRecordingStoppedNotice() {
        let content = UNMutableNotificationContent()
        content.title = "Sleep tracking paused"
        content.body = "Recording was interrupted. Open the app to resume. Your alarm is still set."
        let request = UNNotificationRequest(identifier: "recording.stopped", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
