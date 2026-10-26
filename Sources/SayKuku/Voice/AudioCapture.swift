import AVFoundation
import CoreAudio
import Foundation
import os

enum AudioCaptureError: LocalizedError {
    case microphoneUnavailable
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .microphoneUnavailable, .unsupportedFormat:
            localized("Couldn’t use the microphone. Check your input device and microphone access.")
        }
    }
}

/// The microphone as the voice workflows use it; tests pass a fake.
protocol AudioCapturing: AnyObject, Sendable {
    var activeInput: AudioInputSelection? { get }
    func selectInput(uid: String?)
    /// Gets the microphone ready ahead of the first recording, so pressing the shortcut starts it quickly.
    func prepare()
    func start(
        onLevel: @escaping @Sendable (Double) -> Void,
        onChunk: @escaping @Sendable (Data) -> Void,
        onInterruption: @escaping @Sendable () -> Void
    ) -> Task<Void, Error>
    func stop() -> AudioCapture.Recording
    func cancel()
}

final class AudioCapture: AudioCapturing, @unchecked Sendable {
    struct InputConfiguration: Equatable {
        let deviceID: AudioDeviceID
        let hardwareFormat: AVAudioFormat
        let outputFormat: AVAudioFormat

        func requiresRebuild(after next: Self, isRecording: Bool, engineIsRunning: Bool) -> Bool {
            self != next || (isRecording && !engineIsRunning)
        }
    }

    struct Recording: Sendable {
        let wav: Data
        let duration: Double
        let hasNonzeroSamples: Bool
    }

    /// One engine kept across recordings and only stopped in between, which leaves the microphone idle.
    /// With a Bluetooth input, building a new engine can block for about three seconds, mostly in its
    /// first `inputNode` read; starting a built one takes under 100 ms. A reused engine can keep a stale input
    /// format, so it is rebuilt when the selected device or hardware format changes, or it fails to start.
    /// The engine, its observer, its input device and the last input device are only touched on `queue`.
    private var engine: AVAudioEngine?
    private var engineInputConfiguration: InputConfiguration?
    private var engineFollowsSystemDefault = true
    private var configurationObserver: NSObjectProtocol?
    private var lastDeviceID: UInt32?
    private var deviceObservation: AudioInputDeviceObservation?
    private var selectedUID: String?
    private var engineInvalidated = false
    private var capturedInput: AudioInputSelection?
    var activeInput: AudioInputSelection? { lock.withLock { capturedInput } }

    func selectInput(uid: String?) {
        queue.async { [self] in
            selectedUID = uid
            if deviceObservation != nil { prewarm() }
        }
    }
    /// Starting an engine can take hundreds of milliseconds with Bluetooth inputs, so it runs here rather
    /// than on the caller's thread. `stop` and `cancel` go through the same queue, so they always follow
    /// a start that is still in flight and come before the next one.
    private let queue = DispatchQueue(label: "com.saykuku.audio-capture")
    private let signposter = OSSignposter.performance
    private let lock = NSLock()
    private var pcm = Data()
    private var converter: AVAudioConverter?
    private var chunkHandler: (@Sendable (Data) -> Void)?
    private var levelHandler: (@Sendable (Double) -> Void)?
    private var interruptionHandler: (@Sendable () -> Void)?
    private var running = false
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    /// Builds the engine for the selected input and refreshes it on hardware changes, off the caller's thread.
    /// Building it does not turn the microphone on. Without microphone access it waits for the first recording.
    func prepare() {
        queue.async { [weak self] in
            guard let self, AVAudioApplication.shared.recordPermission == .granted else { return }
            if self.deviceObservation == nil {
                self.deviceObservation = AudioInputDeviceObservation { [weak self] in
                    guard let self else { return }
                    queue.async {
                        let snapshot = CoreAudioInputs.snapshot()
                        let deviceID = self.engineInputConfiguration?.deviceID
                        let inputChanged: Bool
                        if self.lock.withLock({ self.running }), let deviceID {
                            inputChanged = !snapshot.keepsRecordingInput(
                                deviceID, followsSystemDefault: self.engineFollowsSystemDefault
                            )
                        } else {
                            inputChanged = snapshot.resolve(uid: self.selectedUID)?.device.id != deviceID
                        }
                        if inputChanged {
                            self.engineInvalidated = true
                            self.interrupt()
                        }
                        self.prewarm()
                    }
                }
            }
            self.prewarm()
        }
    }

    /// Runs on `queue`. A recording in progress keeps its engine; the next start replaces it if needed.
    private func prewarm() {
        guard !lock.withLock({ running }) else { return }
        let interval = signposter.beginInterval("audio prewarm")
        defer { signposter.endInterval("audio prewarm", interval) }
        // Reading the input node is the slow part; it opens the device without starting it.
        _ = try? currentEngine().engine.inputNode
    }

    /// Queues an engine start and returns at once; the task finishes once the engine runs.
    /// Queuing before returning keeps call order: a later `start`, `stop` or `cancel` always runs after this one.
    /// `onInterruption` fires once, on an arbitrary thread, when an audio device change stops the engine.
    func start(
        onLevel: @escaping @Sendable (Double) -> Void,
        onChunk: @escaping @Sendable (Data) -> Void,
        onInterruption: @escaping @Sendable () -> Void
    ) -> Task<Void, Error> {
        // Used as a one-shot result: finishes empty once the engine runs, or with the error.
        let (outcome, continuation) = AsyncThrowingStream<Void, Error>.makeStream()
        queue.async {
            do {
                try self.startEngine(onLevel: onLevel, onChunk: onChunk, onInterruption: onInterruption)
                continuation.finish()
            } catch {
                Log.audio.error("Engine start failed: \(Log.describe(error), privacy: .public)")
                continuation.finish(throwing: error)
            }
        }
        return Task { for try await _ in outcome {} }
    }

    private func startEngine(
        onLevel: @escaping @Sendable (Double) -> Void,
        onChunk: @escaping @Sendable (Data) -> Void,
        onInterruption: @escaping @Sendable () -> Void
    ) throws {
        let interval = signposter.beginInterval("audio start")
        defer { signposter.endInterval("audio start", interval) }
        stopEngine()
        do {
            let (engine, reused) = try currentEngine()
            do {
                try run(engine, reused: reused, onLevel: onLevel, onChunk: onChunk, onInterruption: onInterruption)
            } catch where reused {
                // A fresh engine decides whether a kept input has become stale.
                discardEngine()
                let (engine, _) = try currentEngine()
                try run(engine, reused: false, onLevel: onLevel, onChunk: onChunk, onInterruption: onInterruption)
            }
        } catch {
            discardEngine()
            // A device may still enumerate but refuse to open. Try the system input in that case.
            guard let selectedUID, let fallback = CoreAudioInputs.snapshot().resolve(uid: nil),
                  fallback.device.uid != selectedUID else { throw error }
            let (engine, _) = try currentEngine(useSystemDefault: true)
            try run(engine, reused: false, onLevel: onLevel, onChunk: onChunk, onInterruption: onInterruption)
        }
    }

    private func run(
        _ engine: AVAudioEngine,
        reused: Bool,
        onLevel: @escaping @Sendable (Double) -> Void,
        onChunk: @escaping @Sendable (Data) -> Void,
        onInterruption: @escaping @Sendable () -> Void
    ) throws {
        let input = engine.inputNode
        // Selecting a different device can leave the output bus in the old device's format.
        // Installing the tap below applies the selected hardware format to that unconnected bus.
        let sourceFormat = input.inputFormat(forBus: 0)
        guard sourceFormat.channelCount > 0, sourceFormat.sampleRate > 0 else {
            discardEngine()
            throw AudioCaptureError.microphoneUnavailable
        }
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw AudioCaptureError.unsupportedFormat
        }
        // Mix every input channel; by default the converter keeps only the first one.
        converter.downmix = true

        lock.withLock {
            pcm.removeAll(keepingCapacity: true)
            self.converter = converter
            chunkHandler = onChunk
            levelHandler = onLevel
            interruptionHandler = onInterruption
            running = true
        }

        input.installTap(onBus: 0, bufferSize: 1_024, format: sourceFormat) { [weak self] buffer, _ in
            self?.consume(buffer, sourceFormat: sourceFormat)
        }
        engineInputConfiguration = InputConfiguration(
            deviceID: input.auAudioUnit.deviceID,
            hardwareFormat: input.inputFormat(forBus: 0), outputFormat: input.outputFormat(forBus: 0)
        )
        engine.prepare()
        do {
            try engine.start()
        } catch {
            stopEngine()
            throw error
        }
        let deviceID = input.auAudioUnit.deviceID
        let actualDevice = CoreAudioInputs.snapshot().devices.first { $0.id == deviceID }
        lock.withLock {
            capturedInput = actualDevice.map { AudioInputSelection(device: $0, isFallback: selectedUID != nil && selectedUID != $0.uid) }
        }
        let deviceChanged = lastDeviceID.map { $0 != deviceID } ?? false
        lastDeviceID = deviceID
        let sampleRate = Int(sourceFormat.sampleRate)
        let channels = Int(sourceFormat.channelCount)
        Log.audio.info(
            "Engine started: \(sampleRate, privacy: .public) Hz, \(channels, privacy: .public) ch, reused: \(reused, privacy: .public), device changed: \(deviceChanged, privacy: .public)"
        )
    }

    /// Keeps the prepared engine only while its selected device and hardware configuration still match.
    private func currentEngine(useSystemDefault: Bool = false) throws -> (engine: AVAudioEngine, reused: Bool) {
        guard let selection = CoreAudioInputs.snapshot().resolve(uid: useSystemDefault ? nil : selectedUID) else {
            throw AudioCaptureError.microphoneUnavailable
        }
        let inputDevice = selection.device.id
        engineFollowsSystemDefault = useSystemDefault || selectedUID == nil || selection.isFallback
        if let engine, inputDevice == engineInputConfiguration?.deviceID, !engineInvalidated { return (engine, true) }
        discardEngine()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        try input.auAudioUnit.setDeviceID(inputDevice)
        engineInputConfiguration = InputConfiguration(
            deviceID: input.auAudioUnit.deviceID,
            hardwareFormat: input.inputFormat(forBus: 0), outputFormat: input.outputFormat(forBus: 0)
        )
        // Hardware/profile changes stop the engine's tap. Interrupt this recording and rebuild before reuse.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self, weak engine] _ in
            guard let self, let engine else { return }
            self.queue.async {
                guard self.engine === engine, let previous = self.engineInputConfiguration else { return }
                let input = engine.inputNode
                let hardware = input.inputFormat(forBus: 0)
                let output = input.outputFormat(forBus: 0)
                let next = InputConfiguration(
                    deviceID: input.auAudioUnit.deviceID, hardwareFormat: hardware, outputFormat: output
                )
                // setDeviceID can post a startup notification while the same input still runs normally.
                // Keep it only when the route, both formats, and the running recording are unchanged.
                guard previous.requiresRebuild(
                    after: next, isRecording: self.lock.withLock { self.running }, engineIsRunning: engine.isRunning
                ) else { return }
                self.engineInvalidated = true
                self.interrupt()
            }
        }
        self.engineInvalidated = false
        self.engine = engine
        return (engine, false)
    }

    func stop() -> Recording {
        let data = queue.sync { () -> Data in
            lock.withLock {
                running = false
                chunkHandler = nil
                levelHandler = nil
                interruptionHandler = nil
            }
            stopEngine()
            return lock.withLock { () -> Data in
                converter = nil
                return pcm
            }
        }
        return Recording(
            wav: Self.makeWAV(pcm16: data, sampleRate: 16_000, channels: 1),
            duration: Double(data.count) / (16_000 * 2),
            hasNonzeroSamples: Self.containsNonzeroSamples(in: data)
        )
    }

    /// Returns at once, without waiting for a start still in flight; the queue runs this right after it.
    func cancel() {
        queue.async {
            self.lock.withLock {
                self.running = false
                self.chunkHandler = nil
                self.levelHandler = nil
                self.interruptionHandler = nil
            }
            self.stopEngine()
            self.lock.withLock {
                self.pcm.removeAll()
                self.converter = nil
            }
        }
    }

    /// Stops the engine and keeps it for the next recording.
    private func stopEngine() {
        guard let engine else { return }
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
    }

    private func discardEngine() {
        stopEngine()
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
        engine = nil
        engineInputConfiguration = nil
    }

    private func interrupt() {
        let handler = lock.withLock { () -> (@Sendable () -> Void)? in
            defer { interruptionHandler = nil }
            return interruptionHandler
        }
        handler?()
    }

    private func consume(_ input: AVAudioPCMBuffer, sourceFormat: AVAudioFormat) {
        guard let converter = lock.withLock({ running ? self.converter : nil }) else { return }
        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * ratio)) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
        // `convert` calls the input block synchronously on this thread, so nothing is shared concurrently.
        nonisolated(unsafe) var supplied = false
        nonisolated(unsafe) let source = input
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return source
        }
        guard conversionError == nil, status != .error,
              output.frameLength > 0, let samples = output.int16ChannelData?[0] else { return }
        let chunk = Data(bytes: samples, count: Int(output.frameLength) * MemoryLayout<Int16>.size)
        let handlers = lock.withLock { () -> ((@Sendable (Data) -> Void), (@Sendable (Double) -> Void))? in
            guard running, let chunkHandler, let levelHandler else { return nil }
            pcm.append(chunk)
            return (chunkHandler, levelHandler)
        }
        handlers?.0(chunk)
        handlers?.1(Self.normalizedLevel(in: chunk))
    }

    private static func normalizedLevel(in pcm16: Data) -> Double {
        pcm16.withUnsafeBytes { bytes in
            let samples = bytes.bindMemory(to: Int16.self)
            guard !samples.isEmpty else { return 0 }
            var squareSum: Double = 0
            for sample in samples {
                let normalized = Double(Int16(littleEndian: sample)) / Double(Int16.max)
                squareSum += normalized * normalized
            }
            return AudioLevel.normalized(rms: sqrt(squareSum / Double(samples.count)))
        }
    }

    private static func makeWAV(pcm16: Data, sampleRate: UInt32, channels: UInt16) -> Data {
        var result = Data()
        let byteRate = sampleRate * UInt32(channels) * 2
        let blockAlign = channels * 2
        result.append(contentsOf: "RIFF".utf8)
        result.appendLittleEndian(UInt32(36 + pcm16.count))
        result.append(contentsOf: "WAVEfmt ".utf8)
        result.appendLittleEndian(UInt32(16))
        result.appendLittleEndian(UInt16(1))
        result.appendLittleEndian(channels)
        result.appendLittleEndian(sampleRate)
        result.appendLittleEndian(byteRate)
        result.appendLittleEndian(blockAlign)
        result.appendLittleEndian(UInt16(16))
        result.append(contentsOf: "data".utf8)
        result.appendLittleEndian(UInt32(pcm16.count))
        result.append(pcm16)
        return result
    }

    /// Only rejects empty or all-zero PCM; the model decides whether other audio contains speech.
    static func containsNonzeroSamples(in pcm16: Data) -> Bool {
        pcm16.contains { $0 != 0 }
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
