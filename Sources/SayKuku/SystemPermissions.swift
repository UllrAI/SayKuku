import ApplicationServices
import AppKit
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

    init() {
        refresh()
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
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            microphoneStatus = .notDetermined
        case .restricted:
            microphoneStatus = .restricted
        case .denied:
            microphoneStatus = .denied
        case .authorized:
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
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            refresh()
            return microphoneStatus.isAuthorized
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
final class MicrophoneTestController: @unchecked Sendable {
    enum Phase: Equatable {
        case idle
        case starting
        case running
        case failed(MicrophoneTestFailure)
    }

    private(set) var phase: Phase = .idle
    private(set) var level: Double = 0
    private(set) var deviceName = ""

    @ObservationIgnored private lazy var engine = AVAudioEngine()
    @ObservationIgnored private var tapInstalled = false

    init() {
        refreshDeviceName()
    }

    var isRunning: Bool { phase == .running }

    func start() {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            phase = .failed(.permissionRequired)
            return
        }

        stop(resetPhase: false)
        refreshDeviceName()
        phase = .starting

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
        tapInstalled = true

        do {
            engine.prepare()
            try engine.start()
            phase = .running
        } catch {
            if tapInstalled {
                input.removeTap(onBus: 0)
                tapInstalled = false
            }
            phase = .failed(.couldNotStart)
        }
    }

    func stop() {
        stop(resetPhase: true)
    }

    private func stop(resetPhase: Bool) {
        if engine.isRunning {
            engine.stop()
        }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
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
