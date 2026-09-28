import AVFoundation
import Foundation

@MainActor
enum MessageSounds {
    private static var players: [String: AVAudioPlayer] = [:]

    static func playSent() { play("message_sent") }
    static func playReceived() { play("message_received") }

    private static func play(_ name: String) {
        let enabled = UserDefaults.standard.object(forKey: "blackmarket.messageSounds") as? Bool ?? true
        guard enabled else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, options: [.mixWithOthers])
            try session.setActive(true)
            if players[name] == nil,
               let url = Bundle.main.url(forResource: name, withExtension: "wav") {
                players[name] = try AVAudioPlayer(contentsOf: url)
                players[name]?.prepareToPlay()
            }
            players[name]?.currentTime = 0
            players[name]?.play()
        } catch {
            // Keep chat usable when audio is unavailable or muted by the device.
        }
    }
}
