import XCTest
@testable import SleepCore

let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    utc.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

/// Builds a synthetic night: `awake(i)` decides per epoch whether it's an active (awake) epoch.
func syntheticNight(start: Date, epochs count: Int, awake: (Int) -> Bool, skip: Set<Int> = []) -> [EpochFeatures] {
    (0..<count).compactMap { i in
        guard !skip.contains(i) else { return nil }
        let isAwake = awake(i)
        // A little noise during sleep so it isn't perfectly flat.
        let blip = (i % 37 == 0) ? 1 : 0
        return EpochFeatures(
            start: start.addingTimeInterval(Double(i) * epochDuration),
            meanDb: isAwake ? -40 : -55, maxDb: isAwake ? -20 : -45, noiseFloorDb: -58,
            transientCount: isAwake ? 8 : blip, activeFrames: isAwake ? 90 : blip * 3, totalFrames: 300
        )
    }
}

final class NoiseFloorTests: XCTestCase {
    func testFloorTracksLowPercentile() {
        var est = NoiseFloorEstimator(windowFrames: 100, percentile: 0.1)
        XCTAssertNil(est.floorDb)
        for i in 0..<200 { est.add(i % 10 == 0 ? -20 : -50) }
        XCTAssertEqual(est.floorDb!, -50, accuracy: 0.5)
    }

    func testWindowForgetsOldValues() {
        var est = NoiseFloorEstimator(windowFrames: 50, percentile: 0.1)
        for _ in 0..<50 { est.add(-70) }
        for _ in 0..<50 { est.add(-40) }
        XCTAssertEqual(est.floorDb!, -40, accuracy: 0.5)
    }
}

final class EpochAccumulatorTests: XCTestCase {
    func testCountsTransientsAndEmitsEpoch() {
        var acc = EpochAccumulator(frameDuration: 0.1, thresholdDb: 6, floorWindow: 300)
        let t0 = date(2026, 1, 1, 23)
        var emitted: [EpochFeatures] = []
        for i in 0..<600 {
            // Three separate 3-frame sounds in the first epoch, quiet second epoch.
            let loud = i < 300 && [50, 51, 52, 150, 151, 152, 250, 251, 252].contains(i)
            if let e = acc.add(FrameStats(rmsDb: loud ? -30 : -55), at: t0.addingTimeInterval(Double(i) * 0.1)) {
                emitted.append(e)
            }
        }
        XCTAssertEqual(emitted.count, 2)
        XCTAssertEqual(emitted[0].transientCount, 3)
        XCTAssertEqual(emitted[0].activeFrames, 9)
        XCTAssertEqual(emitted[1].transientCount, 0)
        XCTAssertEqual(emitted[0].noiseFloorDb, -55, accuracy: 0.5)
        XCTAssertGreaterThan(emitted[0].activity, emitted[1].activity)
    }

    func testTimeJumpClosesPartialEpoch() {
        var acc = EpochAccumulator()
        let t0 = date(2026, 1, 1, 23)
        var emitted: [EpochFeatures] = []
        for i in 0..<100 { if let e = acc.add(FrameStats(rmsDb: -50), at: t0.addingTimeInterval(Double(i) * 0.1)) { emitted.append(e) } }
        // 10 minute interruption
        if let e = acc.add(FrameStats(rmsDb: -50), at: t0.addingTimeInterval(600)) { emitted.append(e) }
        XCTAssertEqual(emitted.count, 1)
        XCTAssertEqual(emitted[0].totalFrames, 100)
        XCTAssertEqual(acc.flush()?.start, t0.addingTimeInterval(600))
    }

    func testPlaybackRaisesThreshold() {
        var quiet = EpochAccumulator(thresholdDb: 6)
        var playing = EpochAccumulator(thresholdDb: 6)
        playing.soundPlaying = true
        let t0 = date(2026, 1, 1)
        var a: EpochFeatures?, b: EpochFeatures?
        for i in 0..<300 {
            let db: Float = (i % 50 == 49) ? -48 : -55 // 7 dB bumps
            let t = t0.addingTimeInterval(Double(i) * 0.1)
            a = quiet.add(FrameStats(rmsDb: db), at: t) ?? a
            b = playing.add(FrameStats(rmsDb: db), at: t) ?? b
        }
        XCTAssertEqual(a?.transientCount, 6)
        XCTAssertEqual(b?.transientCount, 0)
        XCTAssertEqual(b?.soundPlaying, true)
    }
}

final class SleepEstimatorTests: XCTestCase {
    let start = date(2026, 1, 1, 23)
    let total = 960 // 8 h

    func testSyntheticNight() {
        // Awake for the first 20 min, a 10 min wake at 3 h, awake for the last 15 min.
        let epochs = syntheticNight(start: start, epochs: total) { i in
            i < 40 || (360..<380).contains(i) || i >= total - 30
        }
        let summary = SleepEstimator().summarize(epochs: epochs, events: [], inBedStart: start,
                                                 inBedEnd: start.addingTimeInterval(Double(total) * epochDuration))
        XCTAssertEqual(summary.latencyMinutes!, 20, accuracy: 5)
        XCTAssertEqual(summary.finalWake!.timeIntervalSince(start) / 60, 465, accuracy: 6)
        XCTAssertGreaterThanOrEqual(summary.wakeBouts, 1)
        XCTAssertEqual(summary.wasoMinutes, 10, accuracy: 5)
        XCTAssertEqual(summary.totalSleep / 3600, 7.1, accuracy: 0.3)
        XCTAssertEqual(summary.coverage, 1, accuracy: 0.001)
        XCTAssertTrue(summary.segments.contains { $0.state == .deep })
        XCTAssertFalse(summary.segments.contains { $0.state == .noData })
    }

    func testGapsAreReportedNotGuessed() {
        let skip = Set(200..<260) // 30 min gap
        let epochs = syntheticNight(start: start, epochs: total, awake: { $0 < 40 }, skip: skip)
        let end = start.addingTimeInterval(Double(total) * epochDuration)
        let summary = SleepEstimator().summarize(epochs: epochs, events: [], inBedStart: start, inBedEnd: end)
        XCTAssertEqual(summary.gapMinutes, 30, accuracy: 0.01)
        XCTAssertTrue(summary.segments.contains { $0.state == .noData })
        let gaps = Gaps.detect(epochs: epochs, sessionStart: start, sessionEnd: end)
        XCTAssertEqual(gaps.count, 1)
        XCTAssertEqual(gaps[0].duration, 1800, accuracy: 1)
    }

    func testRestlessNightHasNoOnset() {
        let epochs = syntheticNight(start: start, epochs: 120) { _ in true }
        let summary = SleepEstimator().summarize(epochs: epochs, events: [], inBedStart: start,
                                                 inBedEnd: start.addingTimeInterval(3600))
        XCTAssertNil(summary.sleepOnset)
        XCTAssertEqual(summary.totalSleep, 0)
    }

    func testSnoreMinutesFromEvents() {
        let events = [
            SoundEvent(kind: .snoring, start: start, end: start.addingTimeInterval(120), confidence: 0.9),
            SoundEvent(kind: .snoring, start: start.addingTimeInterval(600), end: start.addingTimeInterval(660), confidence: 0.8),
            SoundEvent(kind: .cough, start: start, end: start.addingTimeInterval(1), confidence: 0.7),
        ]
        let summary = SleepEstimator().summarize(epochs: [], events: events, inBedStart: start, inBedEnd: start.addingTimeInterval(3600))
        XCTAssertEqual(summary.snoreMinutes, 3, accuracy: 0.01)
        XCTAssertEqual(summary.eventCounts["cough"], 1)
    }

    func testSmartWakeDetector() {
        let quiet = syntheticNight(start: start, epochs: 100) { _ in false }
        let detector = SmartWakeDetector()
        XCTAssertFalse(detector.shouldWake(recent: Array(quiet.suffix(3)), nightSoFar: quiet))
        var stirring = quiet
        stirring[98] = syntheticNight(start: start, epochs: 1) { _ in true }[0]
        stirring[99] = stirring[98]
        XCTAssertTrue(detector.shouldWake(recent: Array(stirring.suffix(3)), nightSoFar: stirring))
    }
}

final class CodecTests: XCTestCase {
    func testRoundTrip() {
        let start = date(2026, 3, 1, 22, 30)
        var epochs = syntheticNight(start: start, epochs: 50) { $0 % 7 == 0 }
        epochs[3].spectralCentroid = 812
        epochs[3].spectralFlux = 0.123
        epochs[3].zeroCrossingRate = 0.0456
        epochs[4].soundPlaying = true
        let data = EpochCodec.encode(epochs)
        XCTAssertEqual(data.count, 16 + 50 * EpochCodec.recordSize)
        let decoded = EpochCodec.decode(data)
        XCTAssertEqual(decoded.count, 50)
        XCTAssertEqual(decoded[3].spectralCentroid, 812)
        XCTAssertEqual(decoded[3].spectralFlux, 0.123, accuracy: 0.001)
        XCTAssertEqual(decoded[3].zeroCrossingRate, 0.0456, accuracy: 0.0001)
        XCTAssertTrue(decoded[4].soundPlaying)
        XCTAssertEqual(decoded[10].start, epochs[10].start)
        XCTAssertEqual(decoded[0].transientCount, epochs[0].transientCount)
        XCTAssertEqual(decoded[0].meanDb, epochs[0].meanDb, accuracy: 0.01)
        XCTAssertEqual(EpochCodec.decode(Data([1, 2, 3])), [])
    }
}

final class RegularityTests: XCTestCase {
    func period(night: Int, bed: (Int, Int), wake: (Int, Int), shift: Bool = false) -> SleepPeriod {
        let evening = utc.date(byAdding: .day, value: night, to: date(2026, 1, 5))! // a Monday
        let bedDay = bed.0 < 12 ? utc.date(byAdding: .day, value: 1, to: evening)! : evening
        let b = utc.date(bySettingHour: bed.0, minute: bed.1, second: 0, of: bedDay)!
        let w = utc.date(bySettingHour: wake.0, minute: wake.1, second: 0, of: utc.date(byAdding: .day, value: 1, to: evening)!)!
        return SleepPeriod(bedtime: b, sleepOnset: b, wake: w, outOfBed: w, isShift: shift)
    }

    func testPerfectlyRegularIs100() {
        let periods = (0..<7).map { period(night: $0, bed: (23, 0), wake: (7, 0)) }
        let sri = Regularity.sleepRegularityIndex(periods: periods, calendar: utc)
        XCTAssertEqual(sri?.value ?? 0, 100, accuracy: 0.01)
        XCTAssertEqual(sri?.dayPairs, 6)
    }

    func testIrregularIsLower() {
        let periods = (0..<7).map { i in
            i.isMultiple(of: 2) ? period(night: i, bed: (23, 0), wake: (7, 0)) : period(night: i, bed: (2, 0), wake: (10, 0))
        }
        let sri = Regularity.sleepRegularityIndex(periods: periods, calendar: utc)!
        // 3 h shift on each 8 h night → 6 of 24 h disagree → SRI = -100 + 200 * 18/24 = 50.
        XCTAssertEqual(sri.value, 50, accuracy: 1)
    }

    func testMissingNightsAreNotPaired() {
        let periods = [period(night: 0, bed: (23, 0), wake: (7, 0)), period(night: 3, bed: (1, 0), wake: (9, 0))]
        XCTAssertNil(Regularity.sleepRegularityIndex(periods: periods, calendar: utc))
    }

    func testSocialJetlag() {
        // Nights 0–6 starting Monday evening: wake days Tue…Mon. Fri & Sat nights wake on free days.
        let periods = (0..<7).map { i -> SleepPeriod in
            let wakeDay = utc.component(.weekday, from: utc.date(byAdding: .day, value: i + 1, to: date(2026, 1, 5))!)
            return [1, 7].contains(wakeDay)
                ? period(night: i, bed: (1, 0), wake: (9, 0))   // mid 05:00
                : period(night: i, bed: (23, 0), wake: (7, 0))  // mid 03:00
        }
        let sj = Regularity.socialJetlag(periods: periods, freeWeekdays: [1, 7], calendar: utc)!
        XCTAssertEqual(sj.hours, 2, accuracy: 0.01)
        XCTAssertEqual(sj.freeNights, 2)
        XCTAssertEqual(sj.workNights, 5)
        XCTAssertEqual(sj.workMidSleep, 3, accuracy: 0.01)
    }

    func testShiftNightsExcludedFromJetlag() {
        var periods = (0..<7).map { period(night: $0, bed: (23, 0), wake: (7, 0)) }
        periods.append(period(night: 7, bed: (4, 0), wake: (12, 0), shift: true))
        let sj = Regularity.socialJetlag(periods: periods, freeWeekdays: [1, 7], calendar: utc)!
        XCTAssertEqual(sj.hours, 0, accuracy: 0.01)
    }

    func testClockMinutesAcrossMidnight() {
        XCTAssertEqual(Regularity.clockMinutes(date(2026, 1, 1, 23, 30), pivotHour: 12, calendar: utc), 690)
        XCTAssertEqual(Regularity.clockMinutes(date(2026, 1, 2, 0, 30), pivotHour: 12, calendar: utc), 750)
        XCTAssertEqual(Regularity.minutesAfterMidnight(fromPivoted: 750, pivotHour: 12), 30)
    }

    func testVariabilityDebtStreak() {
        let periods = [
            period(night: 0, bed: (23, 0), wake: (7, 0)),
            period(night: 1, bed: (23, 30), wake: (7, 0)),
            period(night: 2, bed: (23, 0), wake: (6, 0)),
        ]
        let v = Regularity.variability(periods: periods, calendar: utc)!
        XCTAssertEqual(v.wakeRange, 60, accuracy: 0.01)
        XCTAssertEqual(Regularity.sleepDebtMinutes(periods: periods, goalMinutes: 480), 30 + 60, accuracy: 0.01)
        // Most recent night woke at 06:00, 60 min off a 07:00 target → streak 0; target 06:00 tolerates it.
        XCTAssertEqual(Regularity.onScheduleStreak(periods: periods, targetBedMinutes: 23 * 60, targetWakeMinutes: 420, calendar: utc), 0)
        XCTAssertEqual(Regularity.onScheduleStreak(periods: periods, targetBedMinutes: 23 * 60, targetWakeMinutes: 390, calendar: utc), 3)
    }
}

final class ScheduleTests: XCTestCase {
    func testTargetBedtime() {
        var s = SleepSchedule()
        s.wakeHour = 7
        s.sleepGoalMinutes = 8 * 60
        XCTAssertEqual(s.targetBedtimeMinutes, 23 * 60)
        s.wakeHour = 5
        s.sleepGoalMinutes = 9 * 60
        XCTAssertEqual(s.targetBedtimeMinutes, 20 * 60)
    }

    func testCoachStepsEarlierBy15() {
        var s = SleepSchedule()
        s.wakeHour = 7
        let beds = (0..<5).map { utc.date(bySettingHour: 0, minute: 30, second: 0, of: date(2026, 1, 2 + $0))! }
        let suggestion = BedtimeCoach().suggestion(schedule: s, recentBedtimes: beds, calendar: utc)
        XCTAssertEqual(suggestion.bedtimeMinutes, 15)
        XCTAssertEqual(suggestion.typicalMinutes!, 30, accuracy: 0.01)
        XCTAssertEqual(suggestion.remainingMinutes, 75, accuracy: 0.01)
    }

    func testCoachOnTarget() {
        let s = SleepSchedule()
        let beds = [utc.date(bySettingHour: 23, minute: 5, second: 0, of: date(2026, 1, 2))!]
        XCTAssertEqual(BedtimeCoach().suggestion(schedule: s, recentBedtimes: beds, calendar: utc).bedtimeMinutes, 1380)
    }

    func testReminderPlan() {
        let s = SleepSchedule()
        let now = date(2026, 1, 1, 12)
        let plan = ReminderPlanner.plan(schedule: s, bedtimeMinutes: 23 * 60, from: now, days: 2, calendar: utc)
        // Day 0: caffeine 15:00, wind-down 22:15, bedtime 23:00 (morning light already passed). Day 1: all four.
        XCTAssertEqual(plan.count, 7)
        XCTAssertEqual(plan.first?.kind, .caffeineCutoff)
        XCTAssertEqual(plan.first?.date, date(2026, 1, 1, 15))
        XCTAssertTrue(plan.allSatisfy { $0.date > now })
        let afterMidnight = ReminderPlanner.plan(schedule: s, bedtimeMinutes: 30, from: now, days: 1, calendar: utc)
        XCTAssertEqual(afterMidnight.first { $0.kind == .bedtime }?.date, date(2026, 1, 2, 0, 30))
    }

    func testNextWake() {
        let s = SleepSchedule()
        XCTAssertEqual(s.nextWake(after: date(2026, 1, 1, 23), calendar: utc), date(2026, 1, 2, 7))
        XCTAssertEqual(s.nextWake(after: date(2026, 1, 1, 6), calendar: utc), date(2026, 1, 1, 7))
    }

    func testLenientDecoding() throws {
        let json = #"{"wakeHour": 6, "sleepGoalMinutes": 450}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(SleepSchedule.self, from: json)
        XCTAssertEqual(s.wakeHour, 6)
        XCTAssertEqual(s.sleepGoalMinutes, 450)
        XCTAssertEqual(s.windDownLeadMinutes, SleepSchedule().windDownLeadMinutes)
    }
}

final class StatsTests: XCTestCase {
    func testBasics() {
        XCTAssertEqual(Stats.median([3, 1, 2]), 2)
        XCTAssertEqual(Stats.median([1, 2, 3, 4]), 2.5)
        XCTAssertEqual(Stats.quantile([0, 10], 0.25), 2.5)
        XCTAssertEqual(Stats.standardDeviation([2, 4, 4, 4, 5, 5, 7, 9])!, 2.138, accuracy: 0.001)
        XCTAssertNil(Stats.mean([]))
    }

    func testBenjaminiHochberg() {
        let q = Stats.benjaminiHochberg([0.01, 0.04, 0.03, 0.2])
        XCTAssertEqual(q[0], 0.04, accuracy: 1e-9)
        XCTAssertEqual(q[1], 0.0533, accuracy: 1e-3)
        XCTAssertEqual(q[2], 0.0533, accuracy: 1e-3)
        XCTAssertEqual(q[3], 0.2, accuracy: 1e-9)
    }

    func testHedgesGSign() {
        XCTAssertLessThan(Stats.hedgesG([1, 2, 1, 2], [4, 5, 4, 5])!, 0)
        XCTAssertEqual(Stats.pnd([6, 7, 8], [1, 2, 6.5]), 2.0 / 3.0, accuracy: 1e-9)
    }

    func testBootstrapDeterministic() {
        let a = [1.0, 2, 3, 4, 5], b = [3.0, 4, 5, 6, 7]
        let stat: ([[Double]]) -> Double? = { Stats.mean($0[0])! - Stats.mean($0[1])! }
        let r1 = Stats.bootstrap(groups: [a, b], seed: 7, statistic: stat)!
        let r2 = Stats.bootstrap(groups: [a, b], seed: 7, statistic: stat)!
        XCTAssertEqual(r1.interval, r2.interval)
        XCTAssertLessThan(r1.interval.low, -2)
        XCTAssertGreaterThan(r1.interval.high, -2)
    }
}

final class TagEffectTests: XCTestCase {
    func observations(n: Int) -> [NightObservation] {
        (0..<n).map { i in
            let alcohol = i % 3 == 0
            let free = i % 7 >= 5
            let noise = Double((i * 7919) % 11) / 20 - 0.25
            return NightObservation(
                nightOf: utc.date(byAdding: .day, value: i, to: date(2026, 1, 1))!,
                isFreeDay: free,
                tags: alcohol ? ["alcohol", "random\(i % 2)"] : ["random\(i % 2)"],
                outcomes: [.quality: (alcohol ? 2.5 : 4) + noise]
            )
        }
    }

    func testDetectsRealEffect() {
        let effects = TagEffectAnalyzer.analyze(observations: observations(n: 40), outcome: .quality, iterations: 500)
        let alcohol = effects.first { $0.tag == "alcohol" }!
        XCTAssertEqual(alcohol.difference, -1.5, accuracy: 0.3)
        XCTAssertLessThan(alcohol.interval.high, 0)
        XCTAssertTrue(alcohol.survivesFDR)
        XCTAssertFalse(alcohol.isProvisional)
        XCTAssertFalse(alcohol.isBeneficial)
        XCTAssertEqual(effects.first?.tag, "alcohol")
    }

    func testRequiresMinimumNights() {
        let effects = TagEffectAnalyzer.analyze(observations: observations(n: 12), outcome: .quality, iterations: 200)
        // 4 alcohol nights (< 5) → not reported.
        XCTAssertNil(effects.first { $0.tag == "alcohol" })
    }

    func testProvisionalFlag() {
        let effects = TagEffectAnalyzer.analyze(observations: observations(n: 18), outcome: .quality, iterations: 200)
        XCTAssertEqual(effects.first { $0.tag == "alcohol" }?.isProvisional, true)
    }

    func testAnalysisKeys() {
        let late = utc.date(bySettingHour: 16, minute: 0, second: 0, of: date(2026, 1, 1))!
        let keys = AnalysisTags.keys(for: [
            TagEntry(key: "caffeine", time: late),
            TagEntry(key: "alcohol", amount: 3),
            TagEntry(key: "stress", amount: 2),
            TagEntry(key: TagEntry.customKey("Melatonin")),
        ], calendar: utc)
        XCTAssertEqual(keys, ["caffeine", "caffeineLate", "alcohol", "alcohol3plus", "custom:Melatonin"])
        XCTAssertEqual(AnalysisTags.label(for: "custom:Melatonin"), "Melatonin")
    }
}

final class ExperimentTests: XCTestCase {
    func testAlternatingPhases() {
        let e = SleepExperiment(title: "Caffeine", instruction: "No caffeine after 14:00", start: date(2026, 2, 2), weeks: 4)
        XCTAssertEqual(e.phase(on: date(2026, 2, 2, 22), calendar: utc), .intervention)
        XCTAssertEqual(e.phase(on: date(2026, 2, 9, 22), calendar: utc), .control)
        XCTAssertEqual(e.phase(on: date(2026, 2, 16), calendar: utc), .intervention)
        XCTAssertNil(e.phase(on: date(2026, 3, 2), calendar: utc))
        XCTAssertNil(e.phase(on: date(2026, 2, 1), calendar: utc))
        XCTAssertTrue(e.isFinished(at: date(2026, 3, 2), calendar: utc))
    }

    func testResult() {
        let e = SleepExperiment(title: "Caffeine", instruction: "x", start: date(2026, 2, 2), weeks: 2)
        let obs = (0..<14).map { i in
            NightObservation(nightOf: utc.date(byAdding: .day, value: i, to: date(2026, 2, 2))!, isFreeDay: false,
                             tags: [], outcomes: [.quality: i < 7 ? 4 + Double(i % 2) * 0.2 : 3 + Double(i % 2) * 0.2])
        }
        let r = e.result(observations: obs, calendar: utc)!
        XCTAssertEqual(r.interventionNights, 7)
        XCTAssertEqual(r.difference, 1, accuracy: 0.05)
        XCTAssertGreaterThan(r.interval!.low, 0)
    }
}
