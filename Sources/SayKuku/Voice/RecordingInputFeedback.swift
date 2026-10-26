import Foundation

/// Shared by dictation and the agent. Only successful starts count toward device notices.
struct RecordingInputFeedback {
    private var lastDeviceUID: String?
    private var lastStartedAt: Date?
    private var deviceNoticeUntil: Date?
    private var quietSince: Date?
    private(set) var input: AudioInputSelection?

    mutating func begin(_ input: AudioInputSelection, at now: Date) {
        let longPause = lastStartedAt.map { now.timeIntervalSince($0) > 12 * 60 * 60 } ?? true
        let showDevice = lastDeviceUID != input.device.uid || longPause || input.isFallback
        self.input = input
        deviceNoticeUntil = showDevice ? now.addingTimeInterval(3) : nil
        quietSince = now
        lastDeviceUID = input.device.uid
        lastStartedAt = now
    }

    /// Uses raw normalized levels, so smoothing never delays clearing the quiet warning.
    mutating func recordLevel(_ level: Double, at now: Date) {
        if level > 0.02 { quietSince = nil }
        else if quietSince == nil { quietSince = now }
    }

    func message(at now: Date) -> String? {
        guard let input else { return nil }
        if let quietSince, now.timeIntervalSince(quietSince) >= 2 {
            return localized("No sound heard · \(input.device.name)")
        }
        if let deviceNoticeUntil, now < deviceNoticeUntil { return localized("Using \(input.device.name)") }
        return nil
    }

    mutating func end() {
        input = nil
        quietSince = nil
        deviceNoticeUntil = nil
    }
}
