import Foundation
import Observation
import SleepCore
import SwiftData
import UIKit

/// Drives one tracked night: Start Night (foreground) → recording + heartbeat → optional gentle
/// smart wake → AlarmKit backstop → End Night → summary, Health, alarm re-arm.
@MainActor
@Observable
final class NightSession {
    enum Phase: Equatable {
        case idle
        case running
        /// Recording stopped (call, Siri, another app took the mic) and hasn't recovered yet.
        case interrupted
        /// The in-app gentle alarm is playing.
        case ringing
    }

    struct StartOptions {
        var sound: NoiseKind
        var soundVolume: Double
        var soundTimerMinutes: Int
        var alarmEnabled: Bool
        var wakeTime: Date
        var smartWake: Bool
        var smartWindowMinutes: Int
    }

    private(set) var phase: Phase = .idle
    private(set) var record: NightRecord?
    private(set) var epochs: [EpochFeatures] = []
    private(set) var events: [SoundEvent] = []
    private(set) var lastError: String?
    private(set) var isCharging = true
    /// The record of a night that was cut off (app killed). The UI offers Resume / End.
    private(set) var orphan: NightRecord?
    /// Set when a night just ended, so the UI can open the morning report.
    var justFinished: NightRecord?

    private let context: ModelContext
    private let recorder = NightRecorder()
    private let gentleAlarm = GentleAlarmPlayer()
    private let detector = SmartWakeDetector()
    private var heartbeat: Timer?
    private var lastPersist = Date.distantPast
    private var smartWakeEnabled = false

    init(context: ModelContext) {
        self.context = context
        UIDevice.current.isBatteryMonitoringEnabled = true
        updateCharging()
        NotificationCenter.default.addObserver(forName: UIDevice.batteryStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateCharging() }
        }
        recorder.onEpoch = { @Sendable [weak self] epoch in
            Task { @MainActor in self?.handle(epoch: epoch) }
        }
        recorder.onEvent = { @Sendable [weak self] event in
            Task { @MainActor in self?.events.append(event) }
        }
        recorder.onInterruption = { @Sendable [weak self] interrupted in
            Task { @MainActor in self?.handleInterruption(interrupted) }
        }
        AlarmService.shared.onBackstopDismissed = { [weak self] in
            guard let self, self.phase != .idle else { return }
            self.endNight(reason: .alarmDismissed)
        }
        findOrphan()
    }

    var isActive: Bool { phase != .idle }

    // MARK: - Start

    func startNight(options: StartOptions) async {
        lastError = nil
        guard await NightRecorder.requestMicrophonePermission() else {
            lastError = NightRecorder.RecorderError.microphoneDenied.errorDescription
            return
        }
        let settings = AppSettings.shared
        let night = NightRecord(inBedStart: Date(), source: .tracked)
        night.soundKind = options.sound == .off ? nil : options.sound.rawValue
        if options.alarmEnabled {
            night.alarmTime = options.wakeTime
            night.smartWakeWindowMinutes = options.smartWake ? options.smartWindowMinutes : 0
        }
        context.insert(night)
        try? context.save()

        do {
            var recorderOptions = NightRecorder.Options()
            recorderOptions.thresholdDb = Float(settings.tracking.thresholdDb)
            recorderOptions.detectEvents = settings.tracking.detectEvents
            recorderOptions.saveClips = settings.tracking.saveClips
            try recorder.start(options: recorderOptions)
        } catch {
            context.delete(night)
            try? context.save()
            lastError = error.localizedDescription
            return
        }
        if options.sound != .off {
            recorder.playSound(kind: options.sound, volume: options.soundVolume, timerMinutes: options.soundTimerMinutes)
        }
        record = night
        epochs = []
        events = []
        smartWakeEnabled = options.alarmEnabled && options.smartWake
        phase = .running
        orphan = nil
        startHeartbeat()

        if options.alarmEnabled {
            await AlarmService.shared.armBackstop(at: options.wakeTime)
        } else {
            await AlarmService.shared.reconcile(schedule: settings.schedule, nightInProgress: true)
        }
    }

    /// Continues a night whose recording was cut off (app killed / relaunched mid-night).
    func resumeOrphan() async {
        guard let night = orphan else { return }
        lastError = nil
        do {
            var options = NightRecorder.Options()
            options.thresholdDb = Float(AppSettings.shared.tracking.thresholdDb)
            options.detectEvents = AppSettings.shared.tracking.detectEvents
            options.saveClips = AppSettings.shared.tracking.saveClips
            try recorder.start(options: options)
        } catch {
            lastError = error.localizedDescription
            return
        }
        record = night
        epochs = night.epochs
        events = night.events
        smartWakeEnabled = night.smartWakeWindowMinutes > 0 && night.alarmTime != nil
        night.interruptionCount += 1
        phase = .running
        orphan = nil
        startHeartbeat()
        if let alarm = night.alarmTime, alarm > Date(), AlarmService.shared.backstopID == nil {
            await AlarmService.shared.armBackstop(at: alarm)
        }
    }

    func endOrphan() {
        guard let night = orphan else { return }
        record = night
        epochs = night.epochs
        events = night.events
        orphan = nil
        phase = .running
        endNight(reason: .user)
    }

    // MARK: - Sounds

    func changeSound(kind: NoiseKind, volume: Double, timerMinutes: Int) {
        if kind == .off {
            recorder.stopSound()
        } else {
            recorder.playSound(kind: kind, volume: volume, timerMinutes: timerMinutes)
        }
        record?.soundKind = kind == .off ? nil : kind.rawValue
    }

    func setSoundVolume(_ volume: Double) {
        recorder.setSoundVolume(volume)
    }

    // MARK: - Running

    private func startHeartbeat() {
        heartbeat?.invalidate()
        beat()
        heartbeat = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.beat() }
        }
    }

    /// Every minute: heartbeat timestamp (so gaps are visible later), persistence, recovery, auto-end.
    private func beat() {
        guard let night = record else { return }
        let now = Date()
        if recorder.engineIsRunning {
            night.lastHeartbeat = now
            if phase == .interrupted { phase = .running }
        } else if phase == .running {
            phase = .interrupted
        }
        if phase == .interrupted, !recorder.recover() {
            // Still stuck; the morning report will show the gap honestly.
        }
        if now.timeIntervalSince(lastPersist) > 300 { persist() }

        // Nobody ended the night: stop 3 h after the alarm (or 16 h after starting).
        let limit = night.alarmTime.map { $0.addingTimeInterval(3 * 3600) } ?? night.inBedStart.addingTimeInterval(16 * 3600)
        if now > limit { endNight(reason: .timeout) }
    }

    private func handle(epoch: EpochFeatures) {
        guard record != nil else { return }
        epochs.append(epoch)
        checkSmartWake()
    }

    private func handleInterruption(_ interrupted: Bool) {
        guard record != nil else { return }
        if interrupted {
            if phase == .running { phase = .interrupted }
            record?.interruptionCount += 1
            persist()
        } else if phase == .interrupted {
            phase = .running
        }
    }

    func appBecameActive() {
        updateCharging()
        if phase == .interrupted { _ = recorder.recover() }
        if phase == .idle { findOrphan() }
    }

    private func updateCharging() {
        let state = UIDevice.current.batteryState
        isCharging = state == .charging || state == .full || state == .unknown
    }

    private func persist() {
        guard let night = record else { return }
        night.epochs = epochs
        night.events = events
        try? context.save()
        lastPersist = Date()
    }

    // MARK: - Smart wake

    private func checkSmartWake() {
        guard smartWakeEnabled, phase == .running, let night = record, let alarm = night.alarmTime,
              night.smartWakeTriggeredAt == nil else { return }
        let windowStart = alarm.addingTimeInterval(-Double(night.smartWakeWindowMinutes) * 60)
        let now = Date()
        guard now >= windowStart, now < alarm.addingTimeInterval(-30) else { return }
        guard detector.shouldWake(recent: Array(epochs.suffix(detector.lookback)), nightSoFar: epochs) else { return }
        night.smartWakeTriggeredAt = now
        recorder.stopSound()
        gentleAlarm.start()
        phase = .ringing
        ReminderService.postSmartWakeNotice()
        persist()
    }

    /// Debug/testing aid: ring the gentle alarm now.
    func testGentleAlarm() {
        guard phase == .running else { return }
        record?.smartWakeTriggeredAt = Date()
        gentleAlarm.start()
        phase = .ringing
    }

    /// The user stopped the in-app alarm: cancel the backstop and finish the night.
    func stopGentleAlarm() {
        gentleAlarm.stop()
        endNight(reason: .user)
    }

    // MARK: - End

    enum EndReason { case user, alarmDismissed, timeout }

    func endNight(reason: EndReason) {
        guard let night = record else { return }
        heartbeat?.invalidate()
        heartbeat = nil
        gentleAlarm.stop()
        let tail = recorder.stop()
        if let epoch = tail.epoch { epochs.append(epoch) }
        events.append(contentsOf: tail.events)

        let end = Date()
        night.inBedEnd = end
        night.epochs = epochs
        night.events = events
        night.lastHeartbeat = end
        let summary = SleepEstimator().summarize(epochs: epochs, events: events, inBedStart: night.inBedStart, inBedEnd: end)
        night.summary = summary
        try? context.save()

        // Alarm housekeeping: the backstop isn't needed once the user is up.
        let alarmService = AlarmService.shared
        let woke = reason == .user && (night.alarmTime.map { end < $0 } ?? false)
        alarmService.cancelBackstop()
        if woke || night.smartWakeTriggeredAt != nil { alarmService.suppressToday() }
        Task {
            await alarmService.reconcile(schedule: AppSettings.shared.schedule, nightInProgress: false)
            if AppSettings.shared.tracking.healthKitEnabled, await HealthService.save(summary: summary) {
                night.savedToHealth = true
                try? context.save()
            }
        }

        record = nil
        epochs = []
        events = []
        phase = .idle
        justFinished = night
    }

    // MARK: - Orphans

    private func findOrphan() {
        guard record == nil else { return }
        let descriptor = FetchDescriptor<NightRecord>(predicate: #Predicate { $0.inBedEnd == nil })
        guard let found = try? context.fetch(descriptor).first(where: { !$0.isManual }) else { return }
        let lastSign = found.lastHeartbeat ?? found.inBedStart
        // Too old to resume: close it at the last heartbeat; the gap shows in the report.
        if Date().timeIntervalSince(lastSign) > 16 * 3600 {
            let epochs = found.epochs
            found.inBedEnd = lastSign
            found.summary = SleepEstimator().summarize(epochs: epochs, events: found.events, inBedStart: found.inBedStart, inBedEnd: lastSign)
            try? context.save()
            return
        }
        orphan = found
    }
}
