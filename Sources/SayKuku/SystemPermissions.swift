import ApplicationServices
import AppKit
import AVFAudio
import AVFoundation
import Observation
import os

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

/// The macOS "Press fn key to" setting. SayKuku's monitor can't stop the system action,
/// so anything other than Do Nothing competes with the Fn gestures.
enum FnKeyUsage: Int {
    case doNothing = 0
    case changeInputSource = 1
    case showEmoji = 2
    case startDictation = 3

    /// Stored as `AppleFnUsageType` in `com.apple.HIToolbox`; nil when unset or unknown.
    static func read(from defaults: UserDefaults?) -> FnKeyUsage? {
        (defaults?.object(forKey: "AppleFnUsageType") as? Int).flatMap(FnKeyUsage.init(rawValue:))
    }

    /// Matches the option names in Keyboard Settings.
    var title: String {
        switch self {
        case .doNothing: localized("Do Nothing")
        case .changeInputSource: localized("Change Input Source")
        case .showEmoji: localized("Show Emoji & Symbols")
        case .startDictation: localized("Start Dictation")
        }
    }
}

@MainActor
@Observable
final class SystemPermissionController {
    private(set) var microphoneStatus: SystemPermissionStatus = .notDetermined
    private(set) var accessibilityStatus: SystemPermissionStatus = .notDetermined
    private(set) var fnKeyUsage: FnKeyUsage?
    private(set) var requesting: SystemPermissionKind?
    /// macOS shows the Accessibility prompt only once per app, so later requests open System Settings.
    private(set) var hasPromptedForAccessibility = false
    /// Runs in place of `refresh()` when the system reports an Accessibility change,
    /// so the owner can react to the new status.
    @ObservationIgnored var accessibilityChangeHandler: (@MainActor () -> Void)?

    @ObservationIgnored private nonisolated(unsafe) var accessibilityObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var accessibilityRetryTask: Task<Void, Never>?
    /// Tests pass a fixed status, so they never depend on this Mac's microphone grant.
    @ObservationIgnored private let readMicrophoneStatus: @MainActor () -> SystemPermissionStatus

    init(microphoneStatus: @escaping @MainActor () -> SystemPermissionStatus = SystemPermissionController.systemMicrophoneStatus) {
        readMicrophoneStatus = microphoneStatus
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
        let previousMicrophone = microphoneStatus
        let previousAccessibility = accessibilityStatus
        microphoneStatus = readMicrophoneStatus()

        if AXIsProcessTrusted() {
            accessibilityStatus = .authorized
        } else {
            accessibilityStatus = .denied
        }
        // SayKuku isn't sandboxed, so it can read the system keyboard domain directly.
        fnKeyUsage = FnKeyUsage.read(from: UserDefaults(suiteName: "com.apple.HIToolbox"))
        Self.logChange(.microphone, from: previousMicrophone, to: microphoneStatus)
        Self.logChange(.accessibility, from: previousAccessibility, to: accessibilityStatus)
    }

    static func systemMicrophoneStatus() -> SystemPermissionStatus {
        switch AVAudioApplication.shared.recordPermission {
        case .undetermined: return .notDetermined
        case .denied: return .denied
        case .granted: return .authorized
        @unknown default: return .restricted
        }
    }

    /// Only changes are logged: `refresh` runs on every activation and permission check.
    private static func logChange(
        _ kind: SystemPermissionKind, from old: SystemPermissionStatus, to new: SystemPermissionStatus
    ) {
        guard old != new else { return }
        let change = "\(kind.rawValue) \(old) -> \(new)"
        Log.permissions.info("Permission changed: \(change, privacy: .public)")
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
    case voiceProcessingUnavailable
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

    func start(voiceProcessingEnabled: Bool) {
        guard AVAudioApplication.shared.recordPermission == .granted else {
            phase = .failed(.permissionRequired)
            return
        }

        stop(resetPhase: false)
        refreshDeviceName()
        phase = .starting

        let engine = AVAudioEngine()
        let input = engine.inputNode
        do {
            try AudioCapture.configureVoiceProcessing(on: input, enabled: voiceProcessingEnabled)
        } catch {
            phase = .failed(.voiceProcessingUnavailable)
            return
        }
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
                self.level = AudioLevel.smoothed(previous: self.level, next: value)
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

        return AudioLevel.normalized(rms: Double(sqrt(sum / Float(frameCount * channelCount))))
    }
}
