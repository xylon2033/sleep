import AVFoundation

/// Procedurally generated sleep sounds (no assets, seamless, no licensing questions),
/// rendered in an `AVAudioSourceNode`.
///
/// Evidence for continuous noise is weak and one 2026 PSG trial found pink noise reduced REM,
/// so the defaults are conservative: a capped output gain, a fade-in, and a timer that fades
/// out over the final minutes unless the user opts into "all night".
final class NoiseGenerator {
    /// Hard ceiling on output amplitude (≈ −10 dBFS) regardless of the volume slider.
    static let maxGain: Float = 0.32

    let node: AVAudioSourceNode
    private let state: RenderState

    init(sampleRate: Double) {
        let state = RenderState(sampleRate: Float(sampleRate))
        self.state = state
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        node = AVAudioSourceNode(format: format) { isSilence, _, frameCount, bufferList -> OSStatus in
            state.render(isSilence: isSilence, frameCount: Int(frameCount), bufferList: bufferList)
            return noErr
        }
    }

    /// Starts (or switches) the sound. `timerMinutes == 0` plays all night.
    func play(kind: NoiseKind, volume: Double, timerMinutes: Int) {
        state.configure(kind: kind, volume: Float(volume) * Self.maxGain, timerSeconds: Float(timerMinutes * 60))
    }

    func setVolume(_ volume: Double) {
        state.targetGain = Float(volume) * Self.maxGain
    }

    /// Fades out over a few seconds.
    func stop() {
        state.targetGain = 0
    }

    /// True while sound is audible: the recorder then raises its detection threshold.
    var isAudible: Bool { state.currentGain > 0.002 && state.kind != .off }
}

/// Mutable state touched by the real-time render thread. Plain stored floats: a torn read of a
/// gain value is harmless, and nothing here allocates or locks.
private final class RenderState {
    let sampleRate: Float
    var kind: NoiseKind = .off
    var targetGain: Float = 0
    var currentGain: Float = 0
    /// Samples remaining before silence; < 0 means "all night".
    var remaining: Float = -1
    var fadeOutSamples: Float = 1

    private var rng: UInt32 = 0x1234_5678
    private var b0: Float = 0, b1: Float = 0, b2: Float = 0, b3: Float = 0, b4: Float = 0, b5: Float = 0, b6: Float = 0
    private var brown: Float = 0
    private var lowpass: Float = 0
    private var lfoPhase: Float = 0
    private var dropEnvelope: Float = 0
    private var dropLowpass: Float = 0
    private let smoothing: Float

    init(sampleRate: Float) {
        self.sampleRate = sampleRate
        // ≈ 8 s time constant for fades in and out.
        smoothing = 1 / (sampleRate * 2.5)
    }

    func configure(kind: NoiseKind, volume: Float, timerSeconds: Float) {
        self.kind = kind
        targetGain = kind == .off ? 0 : volume
        if timerSeconds > 0 {
            remaining = timerSeconds * sampleRate
            // Long fade over the final third of the timer, at most 10 minutes.
            fadeOutSamples = min(timerSeconds / 3, 600) * sampleRate
        } else {
            remaining = -1
        }
    }

    @inline(__always) private func white() -> Float {
        // xorshift32
        rng ^= rng << 13
        rng ^= rng >> 17
        rng ^= rng << 5
        return Float(rng) / Float(UInt32.max) * 2 - 1
    }

    @inline(__always) private func pink(_ w: Float) -> Float {
        // Paul Kellet's refined pink filter.
        b0 = 0.99886 * b0 + w * 0.0555179
        b1 = 0.99332 * b1 + w * 0.0750759
        b2 = 0.96900 * b2 + w * 0.1538520
        b3 = 0.86650 * b3 + w * 0.3104856
        b4 = 0.55000 * b4 + w * 0.5329522
        b5 = -0.7616 * b5 - w * 0.0168980
        let out = b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362
        b6 = w * 0.115926
        return out * 0.11
    }

    func render(isSilence: UnsafeMutablePointer<ObjCBool>, frameCount: Int, bufferList: UnsafeMutablePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        if (kind == .off || targetGain == 0) && currentGain < 0.0001 {
            for buffer in buffers {
                memset(buffer.mData, 0, Int(buffer.mDataByteSize))
            }
            isSilence.pointee = true
            return
        }
        let twoPi: Float = 2 * .pi
        let lfoStep = twoPi / (sampleRate * 9) // ~9 s wave period
        for frame in 0..<frameCount {
            var envelope: Float = 1
            if remaining >= 0 {
                remaining -= 1
                if remaining <= 0 {
                    envelope = 0
                    targetGain = 0
                } else if remaining < fadeOutSamples {
                    let x = remaining / fadeOutSamples
                    envelope = x * x
                }
            }
            currentGain += (targetGain - currentGain) * smoothing
            let w = white()
            var sample: Float
            switch kind {
            case .off:
                sample = 0
            case .white:
                sample = w * 0.5
            case .pink:
                sample = pink(w)
            case .brown:
                brown = (brown + 0.02 * w) / 1.02
                sample = brown * 3.5
            case .waves:
                lfoPhase += lfoStep
                if lfoPhase > twoPi { lfoPhase -= twoPi }
                let swell = sin(lfoPhase)
                let amp = 0.2 + 0.8 * swell * swell
                lowpass += (pink(w) - lowpass) * (0.05 + 0.25 * amp)
                sample = lowpass * amp * 2.2
            case .rain:
                let hiss = pink(w) * 0.55
                if dropEnvelope < 0.01, white() > 0.9993 { dropEnvelope = 0.6 + 0.4 * abs(white()) }
                dropEnvelope *= 0.9965
                dropLowpass += (white() * dropEnvelope - dropLowpass) * 0.35
                sample = hiss + dropLowpass * 0.6
            }
            let value = max(-1, min(1, sample * currentGain * envelope))
            for buffer in buffers {
                buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = value
            }
        }
        isSilence.pointee = false
    }
}
