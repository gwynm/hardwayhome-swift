import AVFoundation
import os

private let log = Logger(subsystem: "com.gwynmorfey.hardwayhome.native", category: "sound")

/// Plays bundled audio cues (e.g. km-split beep) with background-safe audio session.
@MainActor
final class SoundService {

    static let shared = SoundService()

    private var player: AVAudioPlayer?

    private init() {
        configureSession()
    }

    func playBeep() {
        guard let url = Bundle.main.url(forResource: "beep", withExtension: "wav") else {
            log.warning("beep.wav not found in bundle")
            return
        }
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.play()
        } catch {
            log.error("Failed to play beep: \(error)")
        }
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
