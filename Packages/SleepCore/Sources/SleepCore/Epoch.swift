import Foundation

/// Length of one scoring epoch. 30 s matches the polysomnography convention.
public let epochDuration: TimeInterval = 30

/// Acoustic statistics for one short analysis frame (100 ms by default).
/// Computed on the audio thread by the app; everything downstream is pure Swift.
public struct FrameStats: Sendable, Equatable {
    /// RMS level in dBFS (≤ 0).
    public var rmsDb: Float
    /// Zero-crossing rate, crossings per sample (0…1).
    public var zeroCrossingRate: Float
    /// Spectral centroid in Hz.
    public var spectralCentroid: Float
    /// Positive spectral flux relative to the previous frame (normalised magnitude).
    public var spectralFlux: Float

    public init(rmsDb: Float, zeroCrossingRate: Float = 0, spectralCentroid: Float = 0, spectralFlux: Float = 0) {
        self.rmsDb = rmsDb
        self.zeroCrossingRate = zeroCrossingRate
        self.spectralCentroid = spectralCentroid
        self.spectralFlux = spectralFlux
    }
}

/// Derived features for one 30 s epoch. Only these (never raw audio) are persisted.
public struct EpochFeatures: Sendable, Equatable, Codable {
    /// Start of the epoch.
    public var start: Date
    /// Mean frame level in dBFS.
    public var meanDb: Float
    /// Loudest frame in dBFS.
    public var maxDb: Float
    /// Adaptive noise floor at the end of the epoch, dBFS.
    public var noiseFloorDb: Float
    /// Number of distinct sound events (rising edges above the floor + threshold).
    public var transientCount: Int
    /// Number of frames above the floor + threshold.
    public var activeFrames: Int
    /// Total frames analysed in this epoch (300 for a full 30 s epoch of 100 ms frames).
    public var totalFrames: Int
    /// Mean spectral centroid of active frames (Hz), 0 if none.
    public var spectralCentroid: Float
    /// Mean positive spectral flux across frames.
    public var spectralFlux: Float
    /// Mean zero-crossing rate across frames.
    public var zeroCrossingRate: Float
    /// True if the app was playing sleep sounds during this epoch (detection is less trustworthy).
    public var soundPlaying: Bool

    public init(start: Date, meanDb: Float, maxDb: Float, noiseFloorDb: Float, transientCount: Int,
                activeFrames: Int, totalFrames: Int, spectralCentroid: Float = 0, spectralFlux: Float = 0,
                zeroCrossingRate: Float = 0, soundPlaying: Bool = false) {
        self.start = start
        self.meanDb = meanDb
        self.maxDb = maxDb
        self.noiseFloorDb = noiseFloorDb
        self.transientCount = transientCount
        self.activeFrames = activeFrames
        self.totalFrames = totalFrames
        self.spectralCentroid = spectralCentroid
        self.spectralFlux = spectralFlux
        self.zeroCrossingRate = zeroCrossingRate
        self.soundPlaying = soundPlaying
    }

    public var end: Date { start.addingTimeInterval(epochDuration) }

    /// Movement/sound activity index. Combines how many separate sounds happened with
    /// how much of the epoch was above the noise floor. Roughly 0 (silent) to ~10 (very busy).
    public var activity: Double {
        guard totalFrames > 0 else { return 0 }
        let activeFraction = Double(activeFrames) / Double(totalFrames)
        return Double(transientCount) * 0.5 + activeFraction * 10
    }
}

/// A discrete classified sound event (snore, talk, cough …).
public struct SoundEvent: Sendable, Equatable, Codable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case snoring, speech, cough, sneeze, other

        public var label: String {
            switch self {
            case .snoring: "Snoring"
            case .speech: "Sleep talking"
            case .cough: "Cough"
            case .sneeze: "Sneeze"
            case .other: "Sound"
            }
        }
    }

    public var id: UUID
    public var kind: Kind
    public var start: Date
    public var end: Date
    /// Peak classifier confidence 0…1.
    public var confidence: Double
    /// File name of an optional saved clip (clips are off by default).
    public var clipFileName: String?

    public init(id: UUID = UUID(), kind: Kind, start: Date, end: Date, confidence: Double, clipFileName: String? = nil) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
        self.confidence = confidence
        self.clipFileName = clipFileName
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// A period during the night where recording was not running (interruption, crash, …).
public struct RecordingGap: Sendable, Equatable, Codable {
    public var start: Date
    public var end: Date
    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

public enum Gaps {
    /// Finds holes in an epoch series longer than `tolerance` and holes at the start/end of the session.
    public static func detect(epochs: [EpochFeatures], sessionStart: Date, sessionEnd: Date,
                              tolerance: TimeInterval = 90) -> [RecordingGap] {
        var gaps: [RecordingGap] = []
        var cursor = sessionStart
        for epoch in epochs.sorted(by: { $0.start < $1.start }) {
            if epoch.start.timeIntervalSince(cursor) > tolerance {
                gaps.append(RecordingGap(start: cursor, end: epoch.start))
            }
            cursor = max(cursor, epoch.end)
        }
        if sessionEnd.timeIntervalSince(cursor) > tolerance {
            gaps.append(RecordingGap(start: cursor, end: sessionEnd))
        }
        return gaps
    }
}
