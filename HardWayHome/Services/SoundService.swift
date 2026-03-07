import AudioToolbox
import AVFoundation
import os

private let log = Logger(subsystem: "com.gwynmorfey.hardwayhome.native", category: "sound")

/// Plays bundled audio cues (e.g. km-split beep).
/// Uses AudioToolbox system sound for reliable background playback + vibration.
@MainActor
final class SoundService {

    static let shared = SoundService()

    private var soundID: SystemSoundID = 0

    private init() {
        configureSession()
        registerBeep()
    }

    func playBeep() {
        guard soundID != 0 else { return }
        AudioServicesPlaySystemSound(soundID)
    }

    private func registerBeep() {
        guard let url = Bundle.main.url(forResource: "beep", withExtension: "wav") else {
            log.warning("beep.wav not found in bundle")
            return
        }
        let status = AudioServicesCreateSystemSoundID(url as CFURL, &soundID)
        if status != kAudioServicesNoError {
            log.error("Failed to register beep sound: \(status)")
            soundID = 0
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
