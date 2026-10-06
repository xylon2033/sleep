import Foundation

/// Rolling low-percentile estimate of the background level, in dB.
///
/// Uses a quantised histogram plus a ring buffer so that adding a frame and reading the
/// percentile are both O(bins), with no per-frame allocation (safe to call from audio code).
public struct NoiseFloorEstimator: Sendable {
    public let windowFrames: Int
    public let percentile: Double
    private static let minDb: Float = -120
    private static let binWidth: Float = 0.5
    private var histogram: [Int]
    private var ring: [Int]
    private var ringIndex = 0
    private var count = 0

    /// - Parameters:
    ///   - windowFrames: How many frames the window spans (3000 × 100 ms = 5 min).
    ///   - percentile: Which percentile counts as the floor (0.1 = 10th percentile).
    public init(windowFrames: Int = 3000, percentile: Double = 0.1) {
        precondition(windowFrames > 0)
        self.windowFrames = windowFrames
        self.percentile = percentile
        histogram = Array(repeating: 0, count: Int(-Self.minDb / Self.binWidth) + 1)
        ring = Array(repeating: 0, count: windowFrames)
    }

    private func bin(for db: Float) -> Int {
        let clamped = min(max(db, Self.minDb), 0)
        return Int(((clamped - Self.minDb) / Self.binWidth).rounded())
    }

    public mutating func add(_ db: Float) {
        let b = bin(for: db)
        if count == windowFrames {
            histogram[ring[ringIndex]] -= 1
        } else {
            count += 1
        }
        ring[ringIndex] = b
        histogram[b] += 1
        ringIndex = (ringIndex + 1) % windowFrames
    }

    /// Current floor in dB, or nil before any frame was added.
    public var floorDb: Float? {
        guard count > 0 else { return nil }
        let target = max(1, Int((Double(count) * percentile).rounded(.up)))
        var seen = 0
        for (i, n) in histogram.enumerated() where n > 0 {
            seen += n
            if seen >= target { return Self.minDb + Float(i) * Self.binWidth }
        }
        return 0
    }
}

/// Turns a stream of 100 ms `FrameStats` into 30 s `EpochFeatures`.
///
/// A frame is "active" when it is `thresholdDb` above the adaptive noise floor. Rising edges
/// of activity are counted as transients (separate sounds: rustling sheets, a cough …).
public struct EpochAccumulator: Sendable {
    public var frameDuration: TimeInterval
    /// dB above the floor for a frame to count as active. Lower = more sensitive.
    public var thresholdDb: Float
    /// Extra dB added while the app plays sleep sounds, so our own playback is not read as movement.
    public var playbackPenaltyDb: Float = 4
    public var soundPlaying = false

    private var floor: NoiseFloorEstimator
    private var epochStart: Date?
    private var framesPerEpoch: Int
    private var frames = 0
    private var sumDb: Float = 0
    private var maxDb: Float = -160
    private var active = 0
    private var transients = 0
    private var wasActive = false
    private var centroidSum: Float = 0
    private var fluxSum: Float = 0
    private var zcrSum: Float = 0
    private var playedThisEpoch = false

    public init(frameDuration: TimeInterval = 0.1, thresholdDb: Float = 6, floorWindow: TimeInterval = 300) {
        self.frameDuration = frameDuration
        self.thresholdDb = thresholdDb
        framesPerEpoch = Int((epochDuration / frameDuration).rounded())
        floor = NoiseFloorEstimator(windowFrames: max(1, Int((floorWindow / frameDuration).rounded())))
    }

    public var currentFloorDb: Float? { floor.floorDb }

    /// Adds a frame captured at `time`. Returns a finished epoch when one completes.
    public mutating func add(_ frame: FrameStats, at time: Date) -> EpochFeatures? {
        var finished: EpochFeatures?
        // If time jumped (interruption), close the partial epoch and start fresh.
        if let start = epochStart, time.timeIntervalSince(start) >= epochDuration + frameDuration * 2 {
            finished = flush()
        }
        if epochStart == nil { epochStart = time }

        floor.add(frame.rmsDb)
        let floorDb = floor.floorDb ?? frame.rmsDb
        let threshold = thresholdDb + (soundPlaying ? playbackPenaltyDb : 0)
        let isActive = frame.rmsDb > floorDb + threshold

        frames += 1
        sumDb += frame.rmsDb
        maxDb = max(maxDb, frame.rmsDb)
        fluxSum += frame.spectralFlux
        zcrSum += frame.zeroCrossingRate
        if soundPlaying { playedThisEpoch = true }
        if isActive {
            active += 1
            centroidSum += frame.spectralCentroid
            if !wasActive { transients += 1 }
        }
        wasActive = isActive

        if frames >= framesPerEpoch {
            // A jump-flush and a full epoch cannot both happen on the same frame.
            return flush() ?? finished
        }
        return finished
    }

    /// Emits the partial epoch (e.g. when the night ends). Returns nil if empty.
    public mutating func flush() -> EpochFeatures? {
        guard let start = epochStart, frames > 0 else {
            reset()
            return nil
        }
        let n = Float(frames)
        let features = EpochFeatures(
            start: start,
            meanDb: sumDb / n,
            maxDb: maxDb,
            noiseFloorDb: floor.floorDb ?? sumDb / n,
            transientCount: transients,
            activeFrames: active,
            totalFrames: frames,
            spectralCentroid: active > 0 ? centroidSum / Float(active) : 0,
            spectralFlux: fluxSum / n,
            zeroCrossingRate: zcrSum / n,
            soundPlaying: playedThisEpoch
        )
        reset()
        return features
    }

    private mutating func reset() {
        epochStart = nil
        frames = 0
        sumDb = 0
        maxDb = -160
        active = 0
        transients = 0
        wasActive = false
        centroidSum = 0
        fluxSum = 0
        zcrSum = 0
        playedThisEpoch = false
    }
}
