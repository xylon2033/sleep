import Foundation
import HealthKit
import SleepCore

/// Writes nights to Apple Health as `inBed` plus `asleepUnspecified` (and `awake`) samples.
/// Never `asleepCore/Deep/REM`: an audio estimate isn't sleep staging and would pollute Health.
@MainActor
enum HealthService {
    private static let store = HKHealthStore()
    private static let sleepType = HKCategoryType(.sleepAnalysis)

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    static func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [sleepType],
                                                 read: [sleepType])
            return store.authorizationStatus(for: sleepType) == .sharingAuthorized
        } catch {
            return false
        }
    }

    static func save(summary: NightSummary) async -> Bool {
        guard isAvailable, store.authorizationStatus(for: sleepType) == .sharingAuthorized else { return false }
        let metadata: [String: Any] = [HKMetadataKeyWasUserEntered: false]
        var samples: [HKCategorySample] = [
            HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.inBed.rawValue,
                             start: summary.inBedStart, end: summary.inBedEnd, metadata: metadata),
        ]
        for segment in summary.segments where segment.end > segment.start {
            let value: HKCategoryValueSleepAnalysis
            switch segment.state {
            case .light, .deep: value = .asleepUnspecified
            case .awake:
                // Only wake inside the sleep period is meaningful.
                guard let onset = summary.sleepOnset, let wake = summary.finalWake,
                      segment.start >= onset, segment.end <= wake else { continue }
                value = .awake
            case .noData: continue
            }
            samples.append(HKCategorySample(type: sleepType, value: value.rawValue,
                                            start: segment.start, end: segment.end, metadata: metadata))
        }
        do {
            try await store.save(samples)
            return true
        } catch {
            return false
        }
    }
}
