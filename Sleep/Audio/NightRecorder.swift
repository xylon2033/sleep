import AVFoundation
import SleepCore

/// Owns the overnight audio pipeline:
///
/// mic → input tap → 16 kHz mono → 100 ms frames → `FrameAnalyzer` → `EpochAccumulator` → 30 s epochs
///                                       └→ (only when loud) SoundAnalysis classifier → events
/// noise generator → main mixer → speaker
///
/// The session is `.playAndRecord` + `.mixWithOthers` + `.defaultToSpeaker`, so Spotify or our own
/// sounds can play while the mic listens. It **must be started in the foreground**; iOS refuses to
/// start recording from the background. Only derived features leave this class.
final class NightRecorder {
    struct Options {
        var thresholdDb: Float = 6
        var detectEvents = true
        var saveClips = false
        var maxClips = 5
    }

    enum RecorderError: LocalizedError {
        case noInput
        case microphoneDenied

        var errorDescription: String? {
            switch self {
            case .noInput: "No microphone input is available."
            case .microphoneDenied: "Microphone access is off. Enable it in Settings → Privacy → Microphone."
            }
        }
    }

    static let analysisSampleRate: Double = 16_000
    static let frameSamples = 1_600 // 100 ms

    // Callbacks are delivered on the processing queue; hop to the main actor yourself.
    var onEpoch: ((EpochFeatures) -> Void)?
    var onEvent: ((SoundEvent) -> Void)?
    /// true = interrupted (call, Siri …), false = running again.
    var onInterruption: ((Bool) -> Void)?

    private(set) var isRunning = false
    private(set) var noise: NoiseGenerator?

    private var engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "sleep.night-recorder", qos: .userInitiated)
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: analysisSampleRate,
                                             channels: 1, interleaved: false)!
    private var options = Options()
    private var converter: AVAudioConverter?
    private var analyzer = FrameAnalyzer(sampleRate: analysisSampleRate)
    private var accumulator = EpochAccumulator()
    private var aggregator = EventAggregator(windowDuration: SoundEventDetector.windowSeconds)
    private var detector: SoundEventDetector?
    private var pending: [Float] = []
    private var clockBase = Date()
    private var samplesSinceBase: Int = 0
    private var hotUntil = Date.distantPast
    private var previousChunk: AVAudioPCMBuffer?
    private var clipRing: [Float] = []
    private var clipsSaved = 0
    private var observers: [NSObjectProtocol] = []

    private var soundKind: NoiseKind = .off
    private var soundVolume: Double = 0
    private var soundEndsAt: Date?

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: - Lifecycle

    static func requestMicrophonePermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        default: return await AVAudioApplication.requestRecordPermission()
        }
    }

    /// Call from the foreground.
    func start(options: Options) throws {
        guard AVAudioApplication.shared.recordPermission == .granted else { throw RecorderError.microphoneDenied }
        self.options = options
        queue.sync {
            accumulator = EpochAccumulator(thresholdDb: options.thresholdDb)
            aggregator = EventAggregator(windowDuration: SoundEventDetector.windowSeconds)
            pending.removeAll()
            clipsSaved = 0
        }
        try configureSession()
        try buildAndStartEngine()
        observeSession()
        isRunning = true
    }

    /// Stops and returns the final partial epoch and any open events.
    func stop() -> (epoch: EpochFeatures?, events: [SoundEvent]) {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        if isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        isRunning = false
        detector?.finish()
        detector = nil
        var result: (EpochFeatures?, [SoundEvent]) = (nil, [])
        queue.sync {
            result = (accumulator.flush(), aggregator.flush())
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return result
    }

    /// Tries to get recording going again after an interruption (call when the app becomes active).
    @discardableResult
    func recover() -> Bool {
        guard isRunning, !engine.isRunning else { return engine.isRunning }
        do {
            try configureSession()
            try buildAndStartEngine()
            onInterruption?(false)
            return true
        } catch {
            return false
        }
    }

    var engineIsRunning: Bool { engine.isRunning }

    // MARK: - Sleep sounds

    func playSound(kind: NoiseKind, volume: Double, timerMinutes: Int) {
        soundKind = kind
        soundVolume = volume
        soundEndsAt = timerMinutes > 0 ? Date().addingTimeInterval(Double(timerMinutes) * 60) : nil
        noise?.play(kind: kind, volume: volume, timerMinutes: timerMinutes)
    }

    func setSoundVolume(_ volume: Double) {
        soundVolume = volume
        noise?.setVolume(volume)
    }

    func stopSound() {
        soundKind = .off
        noise?.stop()
    }

    /// Re-applies the current sound to a freshly built engine, keeping the original end time.
    private func resumeSound(on generator: NoiseGenerator) {
        guard soundKind != .off else { return }
        if let end = soundEndsAt {
            let minutesLeft = Int((end.timeIntervalSinceNow / 60).rounded(.up))
            guard minutesLeft > 0 else { return }
            generator.play(kind: soundKind, volume: soundVolume, timerMinutes: minutesLeft)
        } else {
            generator.play(kind: soundKind, volume: soundVolume, timerMinutes: 0)
        }
    }

    // MARK: - Setup

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default,
                                options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP])
        try session.setActive(true)
    }

    private func buildAndStartEngine() throws {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        engine = AVAudioEngine()

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw RecorderError.noInput }
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        // Sleep sounds: a fresh source node per engine, keeping the current sound settings.
        let outputRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let generator = NoiseGenerator(sampleRate: outputRate > 0 ? outputRate : 48_000)
        engine.attach(generator.node)
        engine.connect(generator.node, to: engine.mainMixerNode,
                       format: AVAudioFormat(standardFormatWithSampleRate: outputRate > 0 ? outputRate : 48_000, channels: 1))
        noise = generator
        resumeSound(on: generator)

        if options.detectEvents, detector == nil {
            let d = try? SoundEventDetector(format: targetFormat)
            d?.onDetection = { [weak self] kind, confidence, time in
                self?.queue.async { self?.handleDetection(kind: kind, confidence: confidence, at: time) }
            }
            detector = d
        }

        input.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat) { [weak self] buffer, _ in
            guard let self, let converted = self.convert(buffer) else { return }
            self.queue.async { self.process(converted) }
        }
        engine.prepare()
        try engine.start()
        queue.sync {
            clockBase = Date()
            samplesSinceBase = 0
            pending.removeAll()
        }
    }

    private func observeSession() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            switch type {
            case .began:
                self.onInterruption?(true)
            case .ended:
                // Try to resume even without .shouldResume; recovering in the background can fail,
                // in which case the app retries when it next becomes active.
                self.recover()
            @unknown default:
                break
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main) { [weak self] _ in
            self?.recover()
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
            // Route change (e.g. headphones) stopped the engine: rebuild with the new formats.
            guard let self, self.isRunning, !self.engine.isRunning else { return }
            self.recover()
        })
    }

    // MARK: - Processing

    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter else { return nil }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, out.frameLength > 0 else { return nil }
        return out
    }

    /// Runs on `queue`.
    private func process(_ chunk: AVAudioPCMBuffer) {
        guard let data = chunk.floatChannelData?[0] else { return }
        let samples = UnsafeBufferPointer(start: data, count: Int(chunk.frameLength))
        pending.append(contentsOf: samples)
        if options.saveClips {
            clipRing.append(contentsOf: samples)
            let maxRing = Int(Self.analysisSampleRate * 10)
            if clipRing.count > maxRing { clipRing.removeFirst(clipRing.count - maxRing) }
        }

        accumulator.soundPlaying = noise?.isAudible ?? false
        var chunkIsLoud = false
        while pending.count >= Self.frameSamples {
            let frame = Array(pending.prefix(Self.frameSamples))
            pending.removeFirst(Self.frameSamples)
            let stats = analyzer.analyze(frame)
            let time = clockBase.addingTimeInterval(Double(samplesSinceBase) / Self.analysisSampleRate)
            samplesSinceBase += Self.frameSamples
            if let floor = accumulator.currentFloorDb, stats.rmsDb > floor + accumulator.thresholdDb {
                chunkIsLoud = true
            }
            if let epoch = accumulator.add(stats, at: time) {
                onEpoch?(epoch)
            }
        }

        // Classifier gating: run only around sounds above the floor (with one chunk of pre-roll).
        if let detector {
            let now = Date()
            if chunkIsLoud {
                if now >= hotUntil, let previousChunk { detector.analyze(previousChunk) }
                hotUntil = now.addingTimeInterval(4)
            }
            if now < hotUntil { detector.analyze(chunk) }
            previousChunk = chunk
            for event in aggregator.close(before: now) { onEvent?(event) }
        }
    }

    /// Runs on `queue`.
    private func handleDetection(kind: SoundEvent.Kind, confidence: Double, at time: Date) {
        let wasOpen = aggregator.openKinds.contains(kind)
        for event in aggregator.add(kind: kind, confidence: confidence, at: time) { onEvent?(event) }
        if options.saveClips, !wasOpen, kind == .snoring || kind == .speech, clipsSaved < options.maxClips {
            // Save what we have now (up to the last 10 s); the episode's event gets the file name.
            if let name = writeClip(kind: kind, at: time) {
                clipsSaved += 1
                aggregator.attachClip(name, to: kind)
            }
        }
    }

    private func writeClip(kind: SoundEvent.Kind, at time: Date) -> String? {
        guard !clipRing.isEmpty else { return nil }
        let name = "\(kind.rawValue)-\(Int(time.timeIntervalSince1970)).caf"
        let url = ClipStore.directory.appendingPathComponent(name)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: AVAudioFrameCount(clipRing.count)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(clipRing.count)
        clipRing.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: src.count)
        }
        do {
            let file = try AVAudioFile(forWriting: url, settings: targetFormat.settings)
            try file.write(from: buffer)
            return name
        } catch {
            return nil
        }
    }
}

/// Snore/talk clips: optional, capped per night, deleted after 30 days.
enum ClipStore {
    static var directory: URL {
        let url = URL.applicationSupportDirectory.appendingPathComponent("Clips", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func url(for name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    static func purge(olderThan days: Int = 30) {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey]) else { return }
        for file in files {
            let created = (try? file.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            if created < cutoff { try? fm.removeItem(at: file) }
        }
    }

    static func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}
