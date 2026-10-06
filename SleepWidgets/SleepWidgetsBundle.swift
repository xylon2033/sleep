import ActivityKit
import AlarmKit
import SwiftUI
import WidgetKit

@main
struct SleepWidgetsBundle: WidgetBundle {
    var body: some Widget {
        AlarmLiveActivity()
    }
}

/// Live Activity for our AlarmKit alarms: shown on the Lock Screen and in the Dynamic Island
/// while an alarm is snoozed (counting down) or alerting.
struct AlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<SleepAlarmMetadata>.self) { context in
            HStack(spacing: 12) {
                Image(systemName: "alarm.fill")
                    .font(.title2)
                    .foregroundStyle(context.attributes.tintColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(for: context.state))
                        .font(.headline)
                    countdown(context.state)
                        .font(.title2.monospacedDigit())
                }
                Spacer()
            }
            .padding()
            .activityBackgroundTint(.black.opacity(0.6))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "alarm.fill").foregroundStyle(context.attributes.tintColor)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(title(for: context.state))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context.state).monospacedDigit()
                }
            } compactLeading: {
                Image(systemName: "alarm.fill").foregroundStyle(context.attributes.tintColor)
            } compactTrailing: {
                countdown(context.state)
                    .monospacedDigit()
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "alarm.fill").foregroundStyle(context.attributes.tintColor)
            }
        }
    }

    private func title(for state: AlarmPresentationState) -> String {
        if case .countdown = state.mode { return "Snoozing" }
        return "Alarm"
    }

    @ViewBuilder
    private func countdown(_ state: AlarmPresentationState) -> some View {
        if case .countdown(let countdown) = state.mode {
            Text(timerInterval: Date.now...max(Date.now, countdown.fireDate), countsDown: true)
        } else {
            Text("Wake up")
        }
    }
}
