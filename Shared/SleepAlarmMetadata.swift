import AlarmKit

/// Metadata attached to every AlarmKit alarm this app schedules. Shared with the widget
/// extension, which renders the alarm's Live Activity (snooze countdown).
struct SleepAlarmMetadata: AlarmMetadata {
    enum Role: String, Codable, Hashable, Sendable {
        /// Repeating daily wake alarm (when no night is being tracked).
        case daily
        /// Fixed alarm at the end of the wake window while a night is tracked.
        case backstop
    }

    var role: Role = .daily
}
