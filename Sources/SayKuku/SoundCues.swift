import AppKit

/// Short chimes for when the microphone opens and closes; the pill is often out of sight while you talk.
@MainActor
final class SoundCues {
    enum Cue: String, CaseIterable {
        case start, stop

        var url: URL? { Bundle.appResources.url(forResource: rawValue, withExtension: "aiff") }
    }

    /// Decoded on first use and reused afterwards.
    private lazy var sounds: [Cue: NSSound] = Dictionary(uniqueKeysWithValues: Cue.allCases.compactMap { cue in
        cue.url.flatMap { NSSound(contentsOf: $0, byReference: true) }.map { (cue, $0) }
    })

    func play(_ cue: Cue) {
        guard let sound = sounds[cue] else { return }
        // `play()` does nothing while the clip is still sounding, so restart it instead.
        sound.stop()
        sound.play()
    }
}
