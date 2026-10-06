import AVFoundation

/// In-app smart-wake alarm: a melodic tone that ramps from ~10 % to full volume over 90 s.
/// Plays through the night's already-active `.playAndRecord` session, which isn't silenced by
/// the ring/silent switch. AlarmKit can't ramp, so this is the gentle part; the AlarmKit
/// backstop at the end of the window is the guaranteed part.
final class GentleAlarmPlayer {
    static let soundName = "gentle-alarm"
    static let rampSeconds: TimeInterval = 90

    private var player: AVAudioPlayer?

    var isPlaying: Bool { player?.isPlaying ?? false }

    func start() {
        guard let url = Bundle.main.url(forResource: Self.soundName, withExtension: "caf") else { return }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1
            p.volume = 0.1
            p.prepareToPlay()
            p.play()
            p.setVolume(1.0, fadeDuration: Self.rampSeconds)
            player = p
        } catch {
            player = nil
        }
    }

    func stop() {
        player?.stop()
        player = nil
    }
}
