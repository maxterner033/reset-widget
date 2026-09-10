import AppKit

enum SystemSoundPlayer {
    static func play(_ name: String) {
        NSSound(named: NSSound.Name(name))?.play()
    }
}
