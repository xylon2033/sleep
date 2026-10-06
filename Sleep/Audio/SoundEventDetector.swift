import AVFoundation
import CoreMedia
import SoundAnalysis
import SleepCore

/// Runs Apple's built-in sound classifier (303 classes, no training needed) and reports
/// snoring / speech / cough / sneeze detections.
final class SoundEventDetector: NSObject, SNResultsObserving {
    static let windowSeconds = 1.5
    /// Minimum classifier confidence that counts as a detection.
    var confidenceThreshold: Double = 0.6
    /// Called on the analysis queue.
    var onDetection: ((SoundEvent.Kind, Double, Date) -> Void)?

    private let analyzer: SNAudioStreamAnalyzer
    private let queue = DispatchQueue(label: "sleep.sound-analysis", qos: .utility)
    private var framePosition: AVAudioFramePosition = 0

    private static let labels: [(String, SoundEvent.Kind)] = [
        ("snoring", .snoring),
        ("speech", .speech),
        ("cough", .cough),
        ("sneeze", .sneeze),
    ]

    init(format: AVAudioFormat) throws {
        analyzer = SNAudioStreamAnalyzer(format: format)
        super.init()
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        request.windowDuration = CMTime(seconds: Self.windowSeconds, preferredTimescale: 1000)
        request.overlapFactor = 0.5
        try analyzer.add(request, withObserver: self)
    }

    /// Feeds audio. Only called while there is sound above the noise floor, so the classifier
    /// doesn't burn battery on silence; positions stay contiguous for the analyzer.
    func analyze(_ buffer: AVAudioPCMBuffer) {
        queue.async { [self] in
            analyzer.analyze(buffer, atAudioFramePosition: framePosition)
            framePosition += AVAudioFramePosition(buffer.frameLength)
        }
    }

    func finish() {
        queue.sync { analyzer.completeAnalysis() }
    }

    // MARK: SNResultsObserving

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        let now = Date()
        for (identifier, kind) in Self.labels {
            if let c = result.classification(forIdentifier: identifier), c.confidence >= confidenceThreshold {
                onDetection?(kind, c.confidence, now)
            }
        }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {}
}
