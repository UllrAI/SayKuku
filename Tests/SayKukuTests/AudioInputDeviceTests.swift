import AVFoundation
import Foundation
import os
import Testing
@testable import SayKuku

@Suite("Audio input selection")
struct AudioInputDeviceTests {
    private let builtIn = AudioInputDevice(id: 1, uid: "built-in", name: "Mac Microphone")
    private let virtual = AudioInputDevice(id: 2, uid: "virtual", name: "BlackHole 2ch")
    private let external = AudioInputDevice(id: 3, uid: "external", name: "DJI Mic Mini")

    @Test("default follows the system input, while explicit input overrides it")
    func resolvingInputs() {
        var snapshot = AudioInputSnapshot(devices: [builtIn, virtual, external], defaultDeviceID: virtual.id)
        #expect(snapshot.resolve(uid: nil) == AudioInputSelection(device: virtual, isFallback: false))
        #expect(snapshot.resolve(uid: builtIn.uid) == AudioInputSelection(device: builtIn, isFallback: false))
        // App selection never changes the snapshot's system default, including a virtual input.
        #expect(snapshot.defaultDeviceID == virtual.id)
        snapshot.defaultDeviceID = external.id
        #expect(snapshot.resolve(uid: nil)?.device == external)
        #expect(snapshot.resolve(uid: builtIn.uid)?.device == builtIn)
    }

    @Test("disconnect falls back without forgetting the UID and reconnect resolves it again")
    func disconnectAndReconnect() {
        var snapshot = AudioInputSnapshot(devices: [builtIn, external], defaultDeviceID: builtIn.id)
        #expect(snapshot.resolve(uid: external.uid)?.isFallback == false)
        snapshot.devices.removeAll { $0.uid == external.uid }
        #expect(snapshot.resolve(uid: external.uid) == AudioInputSelection(device: builtIn, isFallback: true))
        let reconnected = AudioInputDevice(id: 40, uid: external.uid, name: external.name)
        snapshot.devices.append(reconnected)
        #expect(snapshot.resolve(uid: external.uid)?.device == reconnected)
        #expect(snapshot.resolve(uid: external.uid)?.isFallback == false)
        #expect(AudioInputSnapshot().resolve(uid: external.uid) == nil)
    }

    @Test("refresh replaces the visible input devices after a hardware change")
    @MainActor
    func inventoryRefresh() {
        let hardware = OSAllocatedUnfairLock(initialState: AudioInputSnapshot(devices: [builtIn, external], defaultDeviceID: builtIn.id))
        let inventory = AudioInputDevices(read: { hardware.withLock { $0 } })
        inventory.refresh()
        #expect(inventory.snapshot.devices == [builtIn, external])
        hardware.withLock { _ = $0.devices.removeLast() }
        inventory.refresh()
        #expect(inventory.snapshot.devices == [builtIn])
        #expect(inventory.snapshot.resolve(uid: external.uid)?.isFallback == true)
    }

    @Test("hardware routing does not write system device properties")
    func noSystemDefaultMutation() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for file in ["AudioCapture.swift", "AudioInputDevices.swift"] {
            let source = try String(contentsOf: root.appendingPathComponent("Sources/SayKuku/Voice/\(file)"), encoding: .utf8)
            #expect(!source.contains("AudioObjectSetPropertyData"))
        }
    }

    @Test("UID choice persists across app states and applies to the shared capture")
    @MainActor
    func persistenceAndSharedCapture() async throws {
        let environment = AppStateTestEnvironment()
        defer { environment.clean() }
        let audio = FakeAudioCapturing()
        let state = environment.makeState(dependencies: .fake(audio: audio))
        #expect(state.settings.inputDeviceUID == nil)
        #expect(audio.selectedUID == nil)
        state.settings.inputDeviceUID = builtIn.uid
        #expect(audio.selectedUID == builtIn.uid)
        let nextAudio = FakeAudioCapturing()
        let restored = environment.makeState(dependencies: .fake(audio: nextAudio))
        #expect(restored.settings.inputDeviceUID == builtIn.uid)
        #expect(nextAudio.selectedUID == builtIn.uid)
        restored.microphoneTest.start()
        for _ in 0..<200 where !restored.microphoneTest.isRunning {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(restored.microphoneTest.activeInput == nextAudio.activeInput)
        restored.microphoneTest.stop()
        restored.settings.inputDeviceUID = nil
        #expect(nextAudio.selectedUID == nil)
        #expect(environment.makeState(dependencies: .fake()).settings.inputDeviceUID == nil)
    }
}

@Suite("Recording input feedback")
struct RecordingInputFeedbackTests {
    private let mic = AudioInputDevice(id: 1, uid: "mic", name: "Microphone")
    private let start = Date(timeIntervalSince1970: 100)

    @Test("first successful start, device change, twelve hours, and each fallback show the actual device")
    func deviceNoticeTiming() {
        var feedback = RecordingInputFeedback()
        let input = AudioInputSelection(device: mic, isFallback: false)
        feedback.begin(input, at: start)
        #expect(feedback.message(at: start) == localized("Using \(mic.name)"))
        feedback.recordLevel(0.5, at: start)
        #expect(feedback.message(at: start.addingTimeInterval(3)) == nil)
        feedback.end()
        feedback.begin(input, at: start.addingTimeInterval(10))
        #expect(feedback.message(at: start.addingTimeInterval(10)) == nil)
        feedback.begin(input, at: start.addingTimeInterval(12 * 3600 + 11))
        #expect(feedback.message(at: start.addingTimeInterval(12 * 3600 + 11)) != nil)
        let changed = AudioInputDevice(id: 2, uid: "new", name: "New microphone")
        feedback.begin(AudioInputSelection(device: changed, isFallback: false), at: start)
        #expect(feedback.message(at: start) == localized("Using \(changed.name)"))
        for _ in 0..<2 {
            feedback.end()
            feedback.begin(AudioInputSelection(device: changed, isFallback: true), at: start)
            #expect(feedback.message(at: start) == localized("Using \(changed.name)"))
        }
    }

    @Test("quiet warning waits two seconds, clears on sound, and can return after later silence")
    func silenceAndRecovery() {
        var feedback = RecordingInputFeedback()
        feedback.begin(AudioInputSelection(device: mic, isFallback: false), at: start)
        feedback.recordLevel(0.001, at: start.addingTimeInterval(1))
        #expect(feedback.message(at: start.addingTimeInterval(1.99)) == localized("Using \(mic.name)"))
        #expect(feedback.message(at: start.addingTimeInterval(2)) == localized("No sound heard · \(mic.name)"))
        feedback.recordLevel(0.5, at: start.addingTimeInterval(3))
        #expect(feedback.message(at: start.addingTimeInterval(3)) == nil)
        feedback.recordLevel(0, at: start.addingTimeInterval(4))
        #expect(feedback.message(at: start.addingTimeInterval(5.9)) == nil)
        #expect(feedback.message(at: start.addingTimeInterval(6)) == localized("No sound heard · \(mic.name)"))
        feedback.end()
        #expect(feedback.message(at: start.addingTimeInterval(7)) == nil)
    }

    @Test("speaking straight away never warns about silence")
    func immediateSpeech() {
        var feedback = RecordingInputFeedback()
        feedback.begin(AudioInputSelection(device: mic, isFallback: false), at: start)
        feedback.recordLevel(0.1, at: start.addingTimeInterval(0.05))
        #expect(feedback.message(at: start.addingTimeInterval(4)) == nil)
    }
}

@Suite("Audio engine configuration changes")
struct AudioEngineConfigurationTests {
    private func configuration(
        deviceID: UInt32 = 1, rate: Double = 48_000, channels: AVAudioChannelCount = 1
    ) -> AudioCapture.InputConfiguration {
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels)!
        return AudioCapture.InputConfiguration(deviceID: deviceID, hardwareFormat: format, outputFormat: format)
    }

    @Test("unchanged startup notifications preserve prewarmed and recording engines")
    func unchangedConfiguration() {
        let previous = configuration()
        #expect(!previous.requiresRebuild(after: configuration(), isRecording: false, engineIsRunning: false))
        #expect(!previous.requiresRebuild(after: configuration(), isRecording: true, engineIsRunning: true))
    }

    @Test("an actual device, hardware format, or tap format change invalidates the engine")
    func changedConfiguration() {
        let previous = configuration()
        for next in [configuration(deviceID: 2), configuration(rate: 44_100), configuration(channels: 2)] {
            #expect(previous.requiresRebuild(after: next, isRecording: true, engineIsRunning: true))
            #expect(previous.requiresRebuild(after: next, isRecording: false, engineIsRunning: false))
        }
        let differentFormat = configuration(rate: 44_100).hardwareFormat
        let hardwareOnly = AudioCapture.InputConfiguration(
            deviceID: 1, hardwareFormat: differentFormat, outputFormat: previous.outputFormat
        )
        let outputOnly = AudioCapture.InputConfiguration(
            deviceID: 1, hardwareFormat: previous.hardwareFormat, outputFormat: differentFormat
        )
        #expect(previous.requiresRebuild(after: hardwareOnly, isRecording: true, engineIsRunning: true))
        #expect(previous.requiresRebuild(after: outputOnly, isRecording: true, engineIsRunning: true))
    }

    @Test("a stopped engine still interrupts an active recording even if its format is unchanged")
    func stoppedEngine() {
        let previous = configuration()
        #expect(previous.requiresRebuild(after: configuration(), isRecording: true, engineIsRunning: false))
    }
}
