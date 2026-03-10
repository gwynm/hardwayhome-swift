import AVFoundation
import os

private let log = Logger(subsystem: "com.gwynmorfey.hardwayhome.native", category: "sound")

/// Plays bundled audio cues (e.g. km-split beep).
/// Uses AVAudioPlayer with .playback session so it ignores the mute switch
/// and works in background (requires UIBackgroundModes audio).
@MainActor
final class SoundService: NSObject, AVAudioPlayerDelegate {

    static let shared = SoundService()

    private var player: AVAudioPlayer?

    private override init() {
        super.init()
        if let url = Bundle.main.url(forResource: "beep", withExtension: "wav") {
            do {
                player = try AVAudioPlayer(contentsOf: url)
                player?.delegate = self
                player?.volume = 0.75
                player?.prepareToPlay()
            } catch {
                log.error("Failed to load beep.wav: \(error)")
            }
        } else {
            log.warning("beep.wav not found in bundle")
        }
    }

    func playBeep() {
        activateSession()
        player?.currentTime = 0
        player?.play()
    }

    // MARK: - AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.deactivateSession()
        }
    }

    // MARK: - Audio session

    private func activateSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: .duckOthers)
            try session.setActive(true)
        } catch {
            log.error("Failed to activate audio session: \(error)")
        }
    }

    private func deactivateSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(
                false, options: .notifyOthersOnDeactivation)
        } catch {
            log.error("Failed to deactivate audio session: \(error)")
        }
    }
}
