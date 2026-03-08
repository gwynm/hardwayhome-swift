import AVFoundation
import os

private let log = Logger(subsystem: "com.gwynmorfey.hardwayhome.native", category: "sound")

/// Plays bundled audio cues (e.g. km-split beep).
/// Uses AVAudioPlayer with .playback session so it ignores the mute switch
/// and works in background (requires UIBackgroundModes audio).
@MainActor
final class SoundService {

    static let shared = SoundService()

    private var player: AVAudioPlayer?

    private init() {
        if let url = Bundle.main.url(forResource: "beep", withExtension: "wav") {
            do {
                player = try AVAudioPlayer(contentsOf: url)
                player?.prepareToPlay()
            } catch {
                log.error("Failed to load beep.wav: \(error)")
            }
        } else {
            log.warning("beep.wav not found in bundle")
        }
    }

    func playBeep() {
        configureSession()
        player?.currentTime = 0
        player?.play()
    }

    private func configureSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: .duckOthers)
            try session.setActive(true)
        } catch {
            log.error("Failed to configure audio session: \(error)")
        }
    }
}
