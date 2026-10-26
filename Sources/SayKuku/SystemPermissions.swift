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
        Log.permissions.notice("Permission changed: \(change, privacy: .public)")
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
    private(set) var activeInput: AudioInputSelection?

    /// The capture recordings use, so the test reuses its engine instead of building one on the main thread,
    /// which takes seconds with a Bluetooth input, and checks the same path a recording takes.
    @ObservationIgnored private let audioCapture: any AudioCapturing
    @ObservationIgnored private let microphoneAllowed: @MainActor () -> Bool
    /// Bumped by every start and stop, so a start or level that arrives late cannot revive a stopped test.
    @ObservationIgnored private var generation = 0

    init(audioCapture: any AudioCapturing, microphoneAllowed: @escaping @MainActor () -> Bool) {
        self.audioCapture = audioCapture
        self.microphoneAllowed = microphoneAllowed
    }

    var isRunning: Bool { phase == .running }

    func start() {
        guard microphoneAllowed() else {
            phase = .failed(.permissionRequired)
            return
        }

        stop(resetPhase: false)
        phase = .starting
        let generation = generation
        let started = audioCapture.start(
            onLevel: { [weak self] value in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == generation, self.phase == .running else { return }
                    self.level = AudioLevel.smoothed(previous: self.level, next: value)
                }
            },
            onChunk: { _ in },
            onInterruption: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == generation else { return }
                    self.stop()
                }
            }
        )
        Task { [weak self] in
            let result = await started.result
            guard let self, self.generation == generation else { return }
            do {
                try result.get()
                activeInput = audioCapture.activeInput
                phase = .running
            } catch {
                audioCapture.cancel()
                phase = .failed(error as? AudioCaptureError == .microphoneUnavailable ? .noInputDevice : .couldNotStart)
            }
        }
    }

    func stop() {
        stop(resetPhase: true)
    }

    /// Releases the capture only while the test holds it, so closing the guide never ends a recording.
    private func stop(resetPhase: Bool) {
        if phase == .starting || phase == .running { audioCapture.cancel() }
        generation += 1
        activeInput = nil
        level = 0
        if resetPhase { phase = .idle }
    }
}
