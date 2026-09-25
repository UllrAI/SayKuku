import AVFoundation
import Foundation
import os

enum AudioCaptureError: LocalizedError {
    case microphoneUnavailable
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .microphoneUnavailable: "No microphone is available"
        case .unsupportedFormat: "The microphone audio format is unsupported"
        }
    }
}

final class AudioCapture: @unchecked Sendable {
    struct Recording: Sendable {
        let wav: Data
        let duration: Double
        let hasSpeech: Bool
    }

    /// A fresh engine per recording, with its tap installed; a reused engine can keep a stale input format.
    /// The engine, its observer and the last input device are only touched on `queue`.
    private var engine: AVAudioEngine?
    private var configurationObserver: NSObjectProtocol?
    private var lastDeviceID: UInt32?
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

    /// Queues a fresh engine start and returns at once; the task finishes once the engine runs.
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
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let sourceFormat = input.outputFormat(forBus: 0)
        guard sourceFormat.channelCount > 0, sourceFormat.sampleRate > 0 else {
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
        self.engine = engine
        engine.prepare()
        do {
            try engine.start()
        } catch {
            stopEngine()
            throw error
        }
        // The engine stops itself when the audio hardware changes, so the tap goes quiet.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            self?.interrupt()
        }
        let deviceID = input.auAudioUnit.deviceID
        let deviceChanged = lastDeviceID.map { $0 != deviceID } ?? false
        lastDeviceID = deviceID
        let sampleRate = Int(sourceFormat.sampleRate)
        let channels = Int(sourceFormat.channelCount)
        Log.audio.info(
            "Engine started: \(sampleRate, privacy: .public) Hz, \(channels, privacy: .public) ch, device changed: \(deviceChanged, privacy: .public)"
        )
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
            hasSpeech: Self.containsSpeech(in: data)
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

    private func stopEngine() {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
        guard let engine else { return }
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        self.engine = nil
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
            let rms = sqrt(squareSum / Double(samples.count))
            let decibels = 20 * log10(max(rms, 0.000_001))
            return min(1, max(0, (decibels + 58) / 58))
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

    static func containsSpeech(in pcm16: Data) -> Bool {
        let samplesPerWindow = 320
        return pcm16.withUnsafeBytes { bytes in
            let samples = bytes.bindMemory(to: Int16.self)
            guard samples.count >= samplesPerWindow else { return false }
            var audibleWindows = 0
            for start in stride(from: 0, to: samples.count - samplesPerWindow + 1, by: samplesPerWindow) {
                var squareSum: Double = 0
                for sample in samples[start..<(start + samplesPerWindow)] {
                    let normalized = Double(Int16(littleEndian: sample)) / Double(Int16.max)
                    squareSum += normalized * normalized
                }
                if sqrt(squareSum / Double(samplesPerWindow)) >= 0.012 {
                    audibleWindows += 1
                    if audibleWindows >= 3 { return true }
                }
            }
            return false
        }
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
