import Foundation
import Testing
@testable import SayKuku

@Suite("Short dictation paired regression")
struct DictationShortRegressionEvalTests {
    private struct Sample: Sendable {
        let id: String
        let suite: String
        let category: String
        let index: Int
        let spoken: String
        let targetApp: String?
        let polish: DictationPolishSample?
        let mixed: MixedLanguageSample?

        func failures(_ text: String) -> [String] {
            if let polish {
                var result = polish.failures(actual: text).map(\.description)
                if suite == "boundary", polish.noTrailingPeriod == false, !DictationPolishRule.endsWithPeriod(text) {
                    result.append("document ending period")
                }
                return result
            }
            return MixedLanguageRule.violations(actual: text, expected: mixed!.expected).map(\.rawValue)
        }
    }

    struct Row: Codable, Sendable {
        let id: String
        let category: String
        let candidate: String
        let arm: String
        let raw: String
        let text: String
        let failures: [String]
        let milliseconds: Int
        let fallback: String?
        let error: String?
    }

    @Test("legacy and unified prompts on the same short audio and unchanged scoring rules")
    func compare() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["SAYKUKU_SHORT_PAIRED_EVAL"] == "1",
              let live = try LiveDictationEval(suite: "short-paired", audioFolder: "unused") else { return }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let outputRoot = root.appendingPathComponent("Build/longform-realtime-20261025")
        let fixtures = root.appendingPathComponent("Tests/SayKukuTests/Fixtures")
        var samples = try DictationPolishSample.loadFixture().enumerated().map { index, sample in
            Sample(id: "polish-\(index + 1)", suite: "polish", category: sample.category.rawValue, index: index + 1,
                   spoken: sample.spoken, targetApp: sample.targetApp, polish: sample, mixed: nil)
        }
        samples += try MixedLanguageSample.loadFixture().enumerated().map { index, sample in
            Sample(id: "mixed-\(index + 1)", suite: "mixed", category: "mixed", index: index + 1,
                   spoken: sample.spoken, targetApp: nil, polish: nil, mixed: sample)
        }
        for suite in ["validation", "hardening"] {
            samples += try JSONDecoder().decode([DictationPolishSample].self, from: Data(contentsOf:
                fixtures.appendingPathComponent("single-pass-realtime-\(suite).json"))).enumerated().map { index, sample in
                Sample(id: "\(suite)-\(index + 1)", suite: suite, category: suite + "/" + sample.category.rawValue,
                       index: index + 1, spoken: sample.spoken, targetApp: sample.targetApp, polish: sample, mixed: nil)
            }
        }
        if env["SAYKUKU_SHORT_PAIRED_BOUNDARIES"] == "1" {
            let boundaries = try JSONDecoder().decode([DictationPolishSample].self,
                from: Data(contentsOf: fixtures.appendingPathComponent("dictation-regression-boundaries.json")))
            samples += boundaries.enumerated().map { index, sample in
                Sample(id: "boundary-\(index + 1)", suite: "boundary", category: "boundary/" + sample.category.rawValue,
                       index: index + 1, spoken: sample.spoken, targetApp: sample.targetApp, polish: sample, mixed: nil)
            }
        }
        if let ids = env["SAYKUKU_SHORT_PAIRED_SAMPLES"]?.split(separator: ",").map(String.init) {
            samples = samples.filter { ids.contains($0.id) }
        }
        let batchSize = max(1, min(2, Int(env["SAYKUKU_SHORT_PAIRED_WORKERS"] ?? "2") ?? 2))
        let candidates = (env["SAYKUKU_SHORT_PAIRED_CANDIDATES"] ?? "legacy,production").split(separator: ",").map(String.init)
        let output = outputRoot.appendingPathComponent(env["SAYKUKU_SHORT_PAIRED_RESULT"] ?? "short-paired.jsonl")
        try #require(!FileManager.default.fileExists(atPath: output.path), "Use a fresh result name")
        FileManager.default.createFile(atPath: output.path, contents: nil)
        let file = try FileHandle(forWritingTo: output)
        defer { try? file.close() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        for candidate in candidates {
            for start in stride(from: 0, to: samples.count, by: batchSize) {
                let batch = Array(samples[start..<min(start + batchSize, samples.count)])
                try await withThrowingTaskGroup(of: [Row].self) { group in
                    for sample in batch { group.addTask { try await Self.run(sample, candidate: candidate, root: root, live: live) } }
                    for try await rows in group {
                        for row in rows {
                            try file.write(contentsOf: encoder.encode(row) + Data([10]))
                            print("Short \(row.id) \(row.candidate) \(row.arm): \(row.failures.isEmpty ? "PASS" : row.failures.joined(separator: "; ")), \(row.milliseconds) ms, \(row.fallback ?? "no fallback"), \(row.error ?? "no error")")
                        }
                    }
                }
                try await Task.sleep(for: .seconds(1))
            }
        }
    }

    private static func run(_ sample: Sample, candidate: String, root: URL, live: LiveDictationEval) async throws -> [Row] {
        let folder: String
        switch sample.suite {
        case "polish": folder = "eval-audio-polish"
        case "mixed": folder = "eval-audio"
        case "boundary": folder = "longform-realtime-20261025/v2/boundary-audio"
        default: folder = "eval-single-pass-20261022/\(sample.suite)-audio"
        }
        let stem = root.appendingPathComponent("Build/\(folder)/\(String(format: "%02d", sample.index))")
        try #require(try String(contentsOf: stem.appendingPathExtension("txt"), encoding: .utf8) == sample.spoken)
        let wav = try Data(contentsOf: stem.appendingPathExtension("wav"))
        let pcm = try pcmData(wav)
        let prompt: String
        var legacyFlash = ""
        if candidate == "legacy" {
            prompt = try String(contentsOf: root.appendingPathComponent("Build/eval-single-pass-20261022/prompts/current-system.txt"), encoding: .utf8)
                + (sample.targetApp.map { "\n\n" + QwenRealtimeClient.toneInstruction(for: $0, keepEndingPunctuation: true) } ?? "")
            legacyFlash = try String(contentsOf: root.appendingPathComponent("Build/longform-eval/baseline.txt"), encoding: .utf8)
            if let app = sample.targetApp, let end = legacyFlash.range(of: "\n\nReply with only the cleaned text:") {
                legacyFlash.insert(contentsOf: "\n\n" + QwenRealtimeClient.toneInstruction(for: app, keepEndingPunctuation: true), at: end.lowerBound)
            }
        } else if candidate == "production" {
            prompt = QwenRealtimeClient.makeDictationInstructions(memoryPrompt: "", targetApp: sample.targetApp)
        } else {
            prompt = try String(contentsOf: root.appendingPathComponent("Build/longform-realtime-20261025/prompts/\(candidate).txt"), encoding: .utf8)
                + (sample.targetApp.map { "\n\n" + QwenRealtimeClient.toneInstruction(for: $0, keepEndingPunctuation: true) } ?? "")
            legacyFlash = try String(contentsOf: root.appendingPathComponent("Build/longform-realtime-20261025/prompts/\(candidate)-flash.txt"), encoding: .utf8)
            if let app = sample.targetApp { legacyFlash += "\n\n" + QwenRealtimeClient.toneInstruction(for: app, keepEndingPunctuation: true) }
        }
        let started = ContinuousClock.now
        do {
            let reply = try await DictationRealtimeLongformEvalTests.realtime(pcm, instructions: prompt,
                structuredOutput: candidate != "legacy", userMessage: nil, live: live, options: .init(usesAppTone: sample.targetApp != nil))
            let first = (try? SpeechDisfluencyCleaner.dictation(reply.text, mode: .light)) ?? ""
            let firstMilliseconds = WorkflowTrace.milliseconds(started.duration(to: .now))
            let firstRow = Row(id: sample.id, category: sample.category, candidate: candidate, arm: "realtime", raw: reply.raw,
                text: first, failures: sample.failures(first), milliseconds: firstMilliseconds, fallback: nil, error: nil)
            let outcome: DictationRefinement.Outcome
            if candidate != "production" {
                let instructions = legacyFlash
                let id = UUID().uuidString
                do {
                    let raw = try await QwenReasoningClient().refineDictation(apiKey: live.apiKey, configuration: live.configuration,
                        instructions: instructions, userMessage: DictationRefinement.userMessage(first, id: id))
                    switch DictationRefinement.review(raw, input: first, id: id, longForm: candidate != "legacy") {
                    case .success(let text): outcome = .init(text: text, fallback: nil)
                    case .failure(let reason): outcome = .init(text: first, fallback: reason)
                    }
                } catch { outcome = .init(text: first, fallback: (error as? QwenError) == .timeout ? .timeout : .failed) }
            } else {
                outcome = try await DictationRefinement.refine(first, settings: .init(targetApp: sample.targetApp), apiKey: live.apiKey,
                    configuration: live.configuration, client: QwenReasoningClient())
            }
            return [firstRow, Row(id: sample.id, category: sample.category, candidate: candidate, arm: "realtime-flash", raw: first,
                text: outcome.text, failures: sample.failures(outcome.text), milliseconds: WorkflowTrace.milliseconds(started.duration(to: .now)),
                fallback: outcome.fallback?.rawValue, error: nil)]
        } catch {
            return ["realtime", "realtime-flash"].map { arm in
                Row(id: sample.id, category: sample.category, candidate: candidate, arm: arm, raw: "", text: "", failures: ["request"],
                    milliseconds: WorkflowTrace.milliseconds(started.duration(to: .now)), fallback: nil, error: Log.describe(error))
            }
        }
    }

    private static func pcmData(_ wav: Data) throws -> Data {
        var offset = 12
        while offset + 8 <= wav.count {
            let length = (0..<4).reduce(0) { $0 | (Int(wav[offset + 4 + $1]) << (8 * $1)) }
            try #require(length <= wav.count - offset - 8)
            if String(decoding: wav[offset..<offset + 4], as: UTF8.self) == "data" {
                return Data(wav[offset + 8..<offset + 8 + length])
            }
            offset += 8 + length + length % 2
        }
        throw QwenError.invalidResponse
    }
}
