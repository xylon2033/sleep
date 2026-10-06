import Accelerate
import Foundation
import SleepCore

/// Computes `FrameStats` (RMS dB, zero-crossing rate, spectral centroid and flux) for one
/// 100 ms mono frame using Accelerate. Not thread-safe: owned by the recorder's processing queue.
final class FrameAnalyzer {
    let sampleRate: Double
    private let fftSize: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private var window: [Float]
    private var padded: [Float]
    private var real: [Float]
    private var imag: [Float]
    private var magnitudes: [Float]
    private var previous: [Float]

    init(sampleRate: Double, fftSize: Int = 2048) {
        self.sampleRate = sampleRate
        self.fftSize = fftSize
        log2n = vDSP_Length(log2(Double(fftSize)))
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        window = []
        padded = [Float](repeating: 0, count: fftSize)
        real = [Float](repeating: 0, count: fftSize / 2)
        imag = [Float](repeating: 0, count: fftSize / 2)
        magnitudes = [Float](repeating: 0, count: fftSize / 2)
        previous = [Float](repeating: 0, count: fftSize / 2)
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
    }

    func analyze(_ frame: [Float]) -> FrameStats {
        let n = min(frame.count, fftSize)
        guard n > 0 else { return FrameStats(rmsDb: -120) }

        var rms: Float = 0
        vDSP_rmsqv(frame, 1, &rms, vDSP_Length(frame.count))
        let db = 20 * log10(max(rms, 1e-6))

        var crossings = 0
        for i in 1..<frame.count where (frame[i - 1] >= 0) != (frame[i] >= 0) {
            crossings += 1
        }
        let zcr = Float(crossings) / Float(frame.count)

        if window.count != n {
            window = [Float](repeating: 0, count: n)
            vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        }
        for i in 0..<fftSize { padded[i] = 0 }
        vDSP_vmul(frame, 1, window, 1, &padded, 1, vDSP_Length(n))

        let half = fftSize / 2
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                padded.withUnsafeBufferPointer { input in
                    input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { complex in
                        vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                magnitudes.withUnsafeMutableBufferPointer { mp in
                    vDSP_zvabs(&split, 1, mp.baseAddress!, 1, vDSP_Length(half))
                }
            }
        }
        // Bin 0 holds DC (and Nyquist in imag); skip it.
        magnitudes[0] = 0

        var total: Float = 0
        var weighted: Float = 0
        var flux: Float = 0
        let binHz = Float(sampleRate) / Float(fftSize)
        for k in 1..<half {
            let m = magnitudes[k]
            total += m
            weighted += m * Float(k) * binHz
            let d = m - previous[k]
            if d > 0 { flux += d }
            previous[k] = m
        }
        let centroid = total > 0 ? weighted / total : 0
        let normalisedFlux = total > 0 ? flux / total : 0
        return FrameStats(rmsDb: db, zeroCrossingRate: zcr, spectralCentroid: centroid, spectralFlux: normalisedFlux)
    }
}
