import Foundation
import Testing
@testable import SayKuku

private struct TypelessEvalSample: Codable, Sendable {
    let id: String
    let wav: String
    var typeless: String?
    var expected: String?
    var verbatim: String?
    var actual: String?
    var error: String?
    var elapsedSeconds: Double?
    var realtimeConnectSeconds: Double?
    var realtimeUploadSeconds: Double?
    var realtimeCommitSeconds: Double?
    var realtimeCommitTimeoutSeconds: Double?
    var exactMatch: Bool?
    var ruleViolations: [String]?

    mutating func clearResult() {
        actual = nil
        error = nil
        elapsedSeconds = nil
        realtimeConnectSeconds = nil
        realtimeUploadSeconds = nil
        realtimeCommitSeconds = nil
        realtimeCommitTimeoutSeconds = nil
        exactMatch = nil
        ruleViolations = nil
    }
}

@Suite("Current single-pass sample eval")
struct TypelessSampleEvalTests {
    private enum Transport: String, Encodable {
        case realtime, batch
    }

    private struct Report: Encodable {
        let baselineSHA: String
        let source: String
        let dataset: String
        let model: String
        let transport: Transport
        let region: String
        let recognitionLanguage: String
        let numberFormat: String
        let cleanup = "light"
        let refinementEnabled = false
        let structureEnabled = true
        let audioFormat = "16 kHz mono PCM16 WAV"
        let keepEndingPunctuation = true
        let targetApp: String? = nil
        let expressionPreference = ""
        let memoryPrompt = ""
        let samples: [TypelessEvalSample]
    }

    @Test("explicit local WAV samples use the current production single-pass client")
    func liveEval() async throws {
        let environment = ProcessInfo.processInfo.environment
        // Ordinary tests do not load private files, read Keychain, or make requests.
        guard environment["SAYKUKU_TYPELESS_EVAL"] == "1" else { return }
        let transport = try #require(Transport(rawValue: environment["SAYKUKU_TYPELESS_TRANSPORT"] ?? "realtime"))
        let workspaceID = environment["SAYKUKU_TEST_WORKSPACE_ID"] ?? ""
        if transport == .realtime {
            try #require(!workspaceID.isEmpty, "Realtime eval requires an explicit development Workspace ID")
        }
        let input = URL(fileURLWithPath: try #require(environment["SAYKUKU_TYPELESS_SAMPLES"]))
        let output = URL(fileURLWithPath: try #require(environment["SAYKUKU_TYPELESS_REPORT"]))
        var samples = try JSONDecoder().decode([TypelessEvalSample].self, from: Data(contentsOf: input))
        try #require(!samples.isEmpty)
        for index in samples.indices { samples[index].clearResult() }
        let configuration = QwenConfiguration(
            region: environment["SAYKUKU_TEST_REGION"].flatMap(QwenRegion.init(rawValue:)) ?? .beijing,
            workspaceID: workspaceID,
            realtimeModel: QwenModelCatalog.defaultRealtimeModel,
            reasoningModel: QwenModelCatalog.defaultReasoningModel
        )
        let language = environment["SAYKUKU_TYPELESS_LANGUAGE"].flatMap(RecognitionLanguage.init(rawValue:)) ?? .automatic
        let numberFormat = environment["SAYKUKU_TYPELESS_NUMBER_FORMAT"].flatMap(DictationNumberFormat.init(rawValue:)) ?? .preferDigits
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        func saveReport() throws {
            let report = Report(
                baselineSHA: environment["SAYKUKU_TYPELESS_BASELINE_SHA"] ?? "unspecified",
                source: environment["SAYKUKU_TYPELESS_SOURCE"] ?? "explicit local samples",
                dataset: environment["SAYKUKU_TYPELESS_DATASET"] ?? "private-recordings",
                model: transport == .realtime ? configuration.realtimeModel : configuration.reasoningModel,
                transport: transport, region: configuration.region.rawValue,
                recognitionLanguage: language.rawValue, numberFormat: numberFormat.rawValue,
                samples: samples
            )
            try encoder.encode(report).write(to: output, options: .atomic)
        }
        try saveReport()
        let key = try #require(try KeychainStore(service: StorageIdentity.development.service).string(for: "qwen.apiKey"))
        let batchClient = QwenReasoningClient()
        var errors = 0
        for index in samples.indices {
            let started = Date()
            do {
                let wavURL = URL(fileURLWithPath: samples[index].wav, relativeTo: input.deletingLastPathComponent())
                let wav = try Data(contentsOf: wavURL)
                let pcm = try TypelessEvalAudio.pcmData(wav)
                let reply: String
                switch transport {
                case .batch:
                    reply = try await batchClient.transcribeAudio(
                        apiKey: key, configuration: configuration, wav: wav,
                        recognitionLanguage: language, numberFormat: numberFormat, cleanup: .light, structure: true
                    )
                case .realtime:
                    let client = QwenRealtimeClient()
                    let session = UUID()
                    do {
                        do {
                            let stage = Date()
                            defer { samples[index].realtimeConnectSeconds = Date().timeIntervalSince(stage) }
                            try await client.connect(
                                session: session, apiKey: key, configuration: configuration,
                                autoStop: false, onSpeechStopped: {}, onDelta: { _ in },
                                recognitionLanguage: language, numberFormat: numberFormat, cleanup: .light, structure: true
                            )
                        }
                        do {
                            let stage = Date()
                            defer { samples[index].realtimeUploadSeconds = Date().timeIntervalSince(stage) }
                            for start in stride(from: 0, to: pcm.count, by: 3_200) {
                                try await client.append(Data(pcm[start..<min(start + 3_200, pcm.count)]), session: session)
                            }
                        }
                        do {
                            let stage = Date()
                            defer { samples[index].realtimeCommitSeconds = Date().timeIntervalSince(stage) }
                            let duration = Double(pcm.count) / 32_000
                            let timeout = 15 + duration / 4
                            samples[index].realtimeCommitTimeoutSeconds = timeout
                            reply = try await client.commit(session: session, timeout: .seconds(timeout))
                        }
                        await client.cancel(session: session)
                    } catch {
                        await client.cancel(session: session)
                        throw error
                    }
                }
                let actual = try SpeechDisfluencyCleaner.dictation(reply, mode: .light)
                samples[index].actual = actual
                if let expected = samples[index].expected {
                    samples[index].exactMatch = actual == expected
                    samples[index].ruleViolations = MixedLanguageRule.violations(actual: actual, expected: expected).map(\.rawValue)
                }
                print("Sample \(index + 1)/\(samples.count): \(samples[index].id), OK")
            } catch {
                errors += 1
                samples[index].error = error.localizedDescription
                print("Sample \(index + 1)/\(samples.count): \(samples[index].id), \(Log.describe(error))")
            }
            samples[index].elapsedSeconds = Date().timeIntervalSince(started)
            try saveReport()
        }
        #expect(errors == 0, "Requests failed; inspect the private report before comparing quality")
    }
}

private enum TypelessEvalAudio {
    static func pcmData(_ wav: Data) throws -> Data {
        guard wav.count >= 12, String(decoding: wav[0..<4], as: UTF8.self) == "RIFF",
              String(decoding: wav[8..<12], as: UTF8.self) == "WAVE" else { throw QwenError.invalidResponse }
        var offset = 12
        var validFormat = false
        while offset + 8 <= wav.count {
            let size = (0..<4).reduce(0) { $0 | (Int(wav[offset + 4 + $1]) << (8 * $1)) }
            guard size <= wav.count - offset - 8 else { throw QwenError.invalidResponse }
            let chunk = String(decoding: wav[offset..<offset + 4], as: UTF8.self)
            if chunk == "fmt " {
                guard size >= 16 else { throw QwenError.invalidResponse }
                let start = offset + 8
                let encoding = Int(wav[start]) | Int(wav[start + 1]) << 8
                let channels = Int(wav[start + 2]) | Int(wav[start + 3]) << 8
                let sampleRate = (0..<4).reduce(0) { $0 | (Int(wav[start + 4 + $1]) << (8 * $1)) }
                let bits = Int(wav[start + 14]) | Int(wav[start + 15]) << 8
                guard encoding == 1, channels == 1, sampleRate == 16_000, bits == 16 else {
                    throw QwenError.invalidResponse
                }
                validFormat = true
            } else if chunk == "data" {
                guard validFormat else { throw QwenError.invalidResponse }
                return Data(wav[offset + 8..<offset + 8 + size])
            }
            offset += 8 + size + size % 2
        }
        throw QwenError.invalidResponse
    }
}

@Suite("Sample eval input handling")
struct TypelessSampleInputTests {
    @Test("WAV parsing skips variable-size and padded chunks instead of assuming a 44-byte header")
    func wavChunks() throws {
        let wav = recording(format: pcmFormat, junk: true)
        #expect(try TypelessEvalAudio.pcmData(wav) == Data([1, 2, 3, 4]))
        #expect(throws: QwenError.invalidResponse) { try TypelessEvalAudio.pcmData(Data(wav.dropLast())) }
    }

    @Test("sample eval rejects audio that is not 16 kHz mono PCM16", arguments: [
        "missingFormat", "sampleRate", "channels", "encoding", "bitDepth"
    ])
    func unsupportedAudio(kind: String) {
        var format = pcmFormat
        switch kind {
        case "sampleRate": format.replaceSubrange(4..<8, with: [0x44, 0xAC, 0, 0]) // 44.1 kHz
        case "channels": format[2] = 2
        case "encoding": format[0] = 3 // IEEE float
        case "bitDepth": format[14] = 32
        default: break
        }
        let wav = recording(format: kind == "missingFormat" ? nil : format)
        #expect(throws: QwenError.invalidResponse) { try TypelessEvalAudio.pcmData(wav) }
    }

    @Test("new runs clear old outputs and scores while retaining reference-only fields")
    func clearsOldResults() throws {
        let input = Data(#"[{"id":"fixture","wav":"sample.wav","expected":"周四见。","verbatim":"旧诊断文本","actual":"old","error":"old","elapsedSeconds":99,"realtimeConnectSeconds":99,"realtimeUploadSeconds":99,"realtimeCommitSeconds":99,"realtimeCommitTimeoutSeconds":99,"exactMatch":true,"ruleViolations":[]}]"#.utf8)
        var sample = try #require(JSONDecoder().decode([TypelessEvalSample].self, from: input).first)
        sample.clearResult()
        #expect(sample.typeless == nil)
        #expect(sample.expected == "周四见。")
        #expect(sample.verbatim == "旧诊断文本")
        #expect(sample.actual == nil && sample.error == nil && sample.elapsedSeconds == nil)
        #expect(sample.realtimeConnectSeconds == nil && sample.realtimeUploadSeconds == nil && sample.realtimeCommitSeconds == nil)
        #expect(sample.realtimeCommitTimeoutSeconds == nil)
        #expect(sample.exactMatch == nil && sample.ruleViolations == nil)
    }

    private var pcmFormat: [UInt8] {
        [1, 0, 1, 0, 0x80, 0x3E, 0, 0, 0, 0x7D, 0, 0, 2, 0, 16, 0]
    }

    private func recording(format: [UInt8]?, junk: Bool = false) -> Data {
        var wav = Data("RIFF".utf8)
        wav.append(contentsOf: [0, 0, 0, 0])
        wav.append(Data("WAVE".utf8))
        if let format {
            wav.append(Data("fmt ".utf8))
            wav.append(contentsOf: [16, 0, 0, 0])
            wav.append(contentsOf: format)
        }
        if junk {
            wav.append(Data("JUNK".utf8))
            wav.append(contentsOf: [3, 0, 0, 0, 7, 8, 9, 0])
        }
        wav.append(Data("data".utf8))
        wav.append(contentsOf: [4, 0, 0, 0, 1, 2, 3, 4])
        return wav
    }
}
