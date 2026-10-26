import CoreAudio
import Foundation
import Observation

struct AudioInputDevice: Equatable, Identifiable, Sendable {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

struct AudioInputSelection: Equatable, Sendable {
    let device: AudioInputDevice
    let isFallback: Bool

    var description: String {
        isFallback
            ? localized("Selected microphone unavailable. Using \(device.name).")
            : localized("Using \(device.name)")
    }
}

struct AudioInputSnapshot: Equatable, Sendable {
    var devices: [AudioInputDevice] = []
    var defaultDeviceID: AudioDeviceID?

    /// An active recording stays on its actual input; a failed preferred device is retried next time.
    func keepsRecordingInput(_ deviceID: AudioDeviceID, followsSystemDefault: Bool) -> Bool {
        devices.contains { $0.id == deviceID } && (!followsSystemDefault || defaultDeviceID == deviceID)
    }

    func resolve(uid: String?) -> AudioInputSelection? {
        if let uid, let device = devices.first(where: { $0.uid == uid }) {
            return AudioInputSelection(device: device, isFallback: false)
        }
        guard let device = devices.first(where: { $0.id == defaultDeviceID }) else { return nil }
        return AudioInputSelection(device: device, isFallback: uid != nil)
    }
}

/// Reads hardware properties only. Device selection belongs to the app's audio unit.
enum CoreAudioInputs {
    static let selectors: [AudioObjectPropertySelector] = [
        kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice
    ]

    static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func snapshot() -> AudioInputSnapshot {
        var address = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return AudioInputSnapshot() }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        let status = ids.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(system, &address, 0, nil, &size, $0.baseAddress!)
        }
        guard status == noErr else { return AudioInputSnapshot() }
        let devices = ids.compactMap { id -> AudioInputDevice? in
            guard hasInputChannels(id), let uid = string(id, kAudioDevicePropertyDeviceUID),
                  let name = string(id, kAudioObjectPropertyName) else { return nil }
            return AudioInputDevice(id: id, uid: uid, name: name)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        address = Self.address(kAudioHardwarePropertyDefaultInputDevice)
        var defaultID = AudioDeviceID(kAudioObjectUnknown)
        size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let result = AudioObjectGetPropertyData(system, &address, 0, nil, &size, &defaultID)
        return AudioInputSnapshot(devices: devices, defaultDeviceID: result == noErr ? defaultID : nil)
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private static func hasInputChannels(_ id: AudioDeviceID) -> Bool {
        var address = address(kAudioDevicePropertyStreamConfiguration, scope: kAudioDevicePropertyScopeInput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { storage.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, storage) == noErr else { return false }
        let buffers = storage.assumingMemoryBound(to: AudioBufferList.self)
        return UnsafeMutableAudioBufferListPointer(buffers).contains { $0.mNumberChannels > 0 }
    }
}

/// Retains the exact blocks required to unregister the hardware listeners.
final class AudioInputDeviceObservation: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.saykuku.input-devices")
    private let listener: AudioObjectPropertyListenerBlock

    init(onChange: @escaping @Sendable () -> Void) {
        listener = { _, _ in onChange() }
        for selector in CoreAudioInputs.selectors {
            var address = CoreAudioInputs.address(selector)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, listener)
        }
    }

    deinit {
        for selector in CoreAudioInputs.selectors {
            var address = CoreAudioInputs.address(selector)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, listener)
        }
    }
}

@MainActor
@Observable
final class AudioInputDevices {
    private(set) var snapshot: AudioInputSnapshot
    @ObservationIgnored private let read: @Sendable () -> AudioInputSnapshot
    @ObservationIgnored private var observation: AudioInputDeviceObservation?

    init(read: @escaping @Sendable () -> AudioInputSnapshot = CoreAudioInputs.snapshot) {
        self.read = read
        snapshot = AudioInputSnapshot()
    }

    /// Started with the app's system services, keeping construction free of hardware work in tests.
    func startMonitoring() {
        refresh()
        guard observation == nil else { return }
        observation = AudioInputDeviceObservation { [weak self] in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    func refresh() { snapshot = read() }
}
