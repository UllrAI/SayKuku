import Foundation

/// The microphone level shown by the pill waveform and the microphone test meter.
enum AudioLevel {
    /// Maps an RMS amplitude onto 0...1 across the 58 dB below full scale.
    static func normalized(rms: Double) -> Double {
        let decibels = 20 * log10(max(rms, 0.000_001))
        return min(1, max(0, (decibels + 58) / 58))
    }

    /// Moves part of the way from `previous` to `next`, so the level eases instead of flickering.
    static func smoothed(previous: Double, next: Double) -> Double {
        (previous * 0.55) + (next * 0.45)
    }
}
