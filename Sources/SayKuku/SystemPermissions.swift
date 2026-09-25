import ApplicationServices
import AppKit
import AVFAudio
import AVFoundation
import Observation

enum SystemPermissionKind: String, Identifiable, CaseIterable {
    case microphone
    case accessibility

    var id: String { rawValue }
}

enum SystemPermissionStatus: Equatable {
    case notDetermined
    case denied
    case restricted
    case authorized

    var isAuthorized: Bool { self == .authorized }
}

@MainActor
@Observable
final class SystemPermissionController {
    private(set) var microphoneStatus: SystemPermissionStatus = .notDetermined
    private(set) var accessibilityStatus: SystemPermissionStatus = .notDetermined
    private(set) var requesting: SystemPermissionKind?
    /// macOS shows the Accessibility prompt only once per app, so later requests open System Settings.
    private(set) var hasPromptedForAccessibility = false
    /// Runs in place of `refresh()` when the system reports an Accessibility change,
    /// so the owner can react to the new status.
    @ObservationIgnored var accessibilityChangeHandler: (@MainActor () -> Void)?

    @ObservationIgnored private nonisolated(unsafe) var accessibilityObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var accessibilityRetryTask: Task<Void, Never>?

    init() {
        refresh()
        // Posted when any app's Accessibility trust changes, so a grant is seen without reactivating SayKuku.
        accessibilityObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.accessibilityDidChange() }
        }
    }

    deinit {
        if let accessibilityObserver {
            DistributedNotificationCenter.default().removeObserver(accessibilityObserver)
        }
    }

    var allRequiredPermissionsGranted: Bool {
        microphoneStatus.isAuthorized && accessibilityStatus.isAuthorized
    }

    func status(for kind: SystemPermissionKind) -> SystemPermissionStatus {
        switch kind {
        case .microphone: microphoneStatus
        case .accessibility: accessibilityStatus
        }
    }

    func refresh() {
        switch AVAudioApplication.shared.recordPermission {
        case .undetermined:
            microphoneStatus = .notDetermined
        case .denied:
            microphoneStatus = .denied
        case .granted:
            microphoneStatus = .authorized
        @unknown default:
            microphoneStatus = .restricted
        }

        if AXIsProcessTrusted() {
            accessibilityStatus = .authorized
        } else {
            accessibilityStatus = .denied
        }
    }

    private func accessibilityDidChange() {
        refreshAfterAccessibilityChange()
        accessibilityRetryTask?.cancel()
        guard !accessibilityStatus.isAuthorized else { return }
        // The notification can arrive before AXIsProcessTrusted() flips, so check once more.
        accessibilityRetryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.refreshAfterAccessibilityChange()
        }
    }

    private func refreshAfterAccessibilityChange() {
        if let accessibilityChangeHandler {
            accessibilityChangeHandler()
        } else {
            refresh()
        }
    }

    @discardableResult
    func request(_ kind: SystemPermissionKind) async -> Bool {
        requesting = kind
        let granted: Bool
        switch kind {
        case .microphone:
            granted = await requestMicrophone()
        case .accessibility:
            granted = await requestAccessibility()
        }
        requesting = nil
        return granted
    }

    func openSystemSettings(for kind: SystemPermissionKind) {
        let anchor: String
        switch kind {
        case .microphone:
            anchor = "Privacy_Microphone"
        case .accessibility:
            anchor = "Privacy_Accessibility"
        }

        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func requestMicrophone() async -> Bool {
        switch microphoneStatus {
        case .authorized:
            return true
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
            refresh()
            return granted && microphoneStatus.isAuthorized
        case .denied, .restricted:
            openSystemSettings(for: .microphone)
            return false
        }
    }

    private func requestAccessibility() async -> Bool {
        if AXIsProcessTrusted() {
            refresh()
            return true
        }

        guard !hasPromptedForAccessibility else {
            openSystemSettings(for: .accessibility)
            return false
        }

        hasPromptedForAccessibility = true
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refresh()
        return accessibilityStatus.isAuthorized
    }
}

enum MicrophoneTestFailure: Equatable {
    case permissionRequired
    case noInputDevice
    case couldNotStart
}

@MainActor
@Observable
final class MicrophoneTestController {
    enum Phase: Equatable {
        case idle
        case starting
        case running
        case failed(MicrophoneTestFailure)
    }

    private(set) var phase: Phase = .idle
    private(set) var level: Double = 0
    private(set) var deviceName = ""

    /// A fresh engine per test, with its tap installed; a reused engine can keep a stale input format.
    @ObservationIgnored private var engine: AVAudioEngine?

    init() {
        refreshDeviceName()
    }

    var isRunning: Bool { phase == .running }

    func start() {
        guard AVAudioApplication.shared.recordPermission == .granted else {
            phase = .failed(.permissionRequired)
            return
        }

        stop(resetPhase: false)
        refreshDeviceName()
        phase = .starting

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            phase = .failed(.noInputDevice)
            return
        }

        let levelHandler: @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void = { [weak self] buffer, _ in
            guard let self else { return }
            let value = Self.normalizedLevel(from: buffer)
            Task { @MainActor [weak self] in
                guard let self, self.phase == .running else { return }
                self.level = (self.level * 0.55) + (value * 0.45)
            }
        }
        input.installTap(onBus: 0, bufferSize: 2_048, format: format, block: levelHandler)

        do {
            engine.prepare()
            try engine.start()
            self.engine = engine
            phase = .running
        } catch {
            input.removeTap(onBus: 0)
            phase = .failed(.couldNotStart)
        }
    }

    func stop() {
        stop(resetPhase: true)
    }

    private func stop(resetPhase: Bool) {
        if let engine {
            if engine.isRunning { engine.stop() }
            engine.inputNode.removeTap(onBus: 0)
            self.engine = nil
        }
        level = 0
        if resetPhase { phase = .idle }
    }

    private func refreshDeviceName() {
        deviceName = AVCaptureDevice.default(for: .audio)?.localizedName ?? ""
    }

    nonisolated private static func normalizedLevel(from buffer: AVAudioPCMBuffer) -> Double {
        guard let channels = buffer.floatChannelData else { return 0 }
        let channelCount = max(1, Int(buffer.format.channelCount))
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }

        var sum: Float = 0
        for channel in 0..<channelCount {
            let samples = channels[channel]
            for frame in 0..<frameCount {
                let sample = samples[frame]
                sum += sample * sample
            }
        }

        let rms = sqrt(sum / Float(frameCount * channelCount))
        let decibels = 20 * log10(max(rms, 0.000_001))
        return Double(min(1, max(0, (decibels + 58) / 58)))
    }
}
