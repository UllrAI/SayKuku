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
    var exactMatch: Bool?
    var ruleViolations: [String]?

    mutating func clearResult() {
        actual = nil
        error = nil
        elapsedSeconds = nil
        realtimeConnectSeconds = nil
        realtimeUploadSeconds = nil
        realtimeCommitSeconds = nil
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
                let reply: String
                switch transport {
                case .batch:
                    reply = try await batchClient.transcribeAudio(
                        apiKey: key, configuration: configuration, wav: wav,
                        recognitionLanguage: language, numberFormat: numberFormat, cleanup: .light
                    )
                case .realtime:
                    let pcm = try TypelessEvalAudio.pcmData(wav)
                    let client = QwenRealtimeClient()
                    let session = UUID()
                    do {
                        do {
                            let stage = Date()
                            defer { samples[index].realtimeConnectSeconds = Date().timeIntervalSince(stage) }
                            try await client.connect(
                                session: session, apiKey: key, configuration: configuration,
                                autoStop: false, onSpeechStopped: {}, onDelta: { _ in },
                                recognitionLanguage: language, numberFormat: numberFormat, cleanup: .light
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
                            reply = try await client.commit(session: session, timeout: .seconds(20 + duration / 4))
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
        while offset + 8 <= wav.count {
            let size = (0..<4).reduce(0) { $0 | (Int(wav[offset + 4 + $1]) << (8 * $1)) }
            guard size <= wav.count - offset - 8 else { throw QwenError.invalidResponse }
            if String(decoding: wav[offset..<offset + 4], as: UTF8.self) == "data" {
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
        var wav = Data("RIFF".utf8)
        wav.append(contentsOf: [0, 0, 0, 0])
        wav.append(Data("WAVEJUNK".utf8))
        wav.append(contentsOf: [3, 0, 0, 0, 7, 8, 9, 0])
        wav.append(Data("data".utf8))
        wav.append(contentsOf: [4, 0, 0, 0, 1, 2, 3, 4])
        #expect(try TypelessEvalAudio.pcmData(wav) == Data([1, 2, 3, 4]))
        #expect(throws: QwenError.invalidResponse) { try TypelessEvalAudio.pcmData(Data(wav.dropLast())) }
    }

    @Test("new runs clear old outputs and scores while retaining reference-only fields")
    func clearsOldResults() throws {
        let input = Data(#"[{"id":"fixture","wav":"sample.wav","expected":"周四见。","verbatim":"旧诊断文本","actual":"old","error":"old","elapsedSeconds":99,"realtimeConnectSeconds":99,"realtimeUploadSeconds":99,"realtimeCommitSeconds":99,"exactMatch":true,"ruleViolations":[]}]"#.utf8)
        var sample = try #require(JSONDecoder().decode([TypelessEvalSample].self, from: input).first)
        sample.clearResult()
        #expect(sample.typeless == nil)
        #expect(sample.expected == "周四见。")
        #expect(sample.verbatim == "旧诊断文本")
        #expect(sample.actual == nil && sample.error == nil && sample.elapsedSeconds == nil)
        #expect(sample.realtimeConnectSeconds == nil && sample.realtimeUploadSeconds == nil && sample.realtimeCommitSeconds == nil)
        #expect(sample.exactMatch == nil && sample.ruleViolations == nil)
    }
}
