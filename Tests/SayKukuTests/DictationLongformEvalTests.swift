import Foundation
import Testing
@testable import SayKuku

/// Private datasets and generated replies stay outside the source tree. Live calls are opt-in.
@Suite("Longform dictation evaluation")
struct DictationLongformEvalTests {
    struct Dataset: Decodable {
        struct Sample: Decodable {
            let id: String
            let actual: String
            let typeless: String
        }
        let samples: [Sample]
    }

    struct Row: Codable {
        let id: String
        let arm: String
        let input: String
        let reference: String
        let output: String
        let milliseconds: Int
        let fallback: String?
    }

    @Test("replay existing longform transcripts through the text refinement model")
    func replay() async throws {
        let env = ProcessInfo.processInfo.environment
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Build/longform-eval")
        if env["SAYKUKU_LONGFORM_SNAPSHOT"] == "1" {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let snapshot = directory.appendingPathComponent("baseline.txt")
            try #require(!FileManager.default.fileExists(atPath: snapshot.path), "Preserve the existing baseline")
            try DictationRefinement.instructions(.init()).write(to: snapshot, atomically: true, encoding: .utf8)
            return
        }
        guard env["SAYKUKU_LONGFORM_EVAL"] == "1",
              let datasetPath = env["SAYKUKU_LONGFORM_DATASET"],
              let live = try LiveDictationEval(suite: "longform", audioFolder: "unused") else { return }
        let dataset = try JSONDecoder().decode(Dataset.self, from: Data(contentsOf:
            URL(fileURLWithPath: datasetPath).appendingPathComponent("evaluations/current-realtime-light.json")))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let baselineURL = directory.appendingPathComponent("baseline.txt")
        let baseline = FileManager.default.fileExists(atPath: baselineURL.path)
            ? try String(contentsOf: baselineURL, encoding: .utf8) : nil
        let outputURL = directory.appendingPathComponent(env["SAYKUKU_LONGFORM_RESULT"] ?? "comparison.jsonl")
        try #require(!FileManager.default.fileExists(atPath: outputURL.path), "Use a fresh result name")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? output.close() }
        let client = QwenReasoningClient()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        for sample in dataset.samples where env["SAYKUKU_LONGFORM_SAMPLES"]?.split(separator: ",").contains(where: { sample.id.hasPrefix($0) }) ?? true {
            var arms = [("current", DictationRefinement.instructions(.init()))]
            if let baseline { arms.insert(("baseline", baseline), at: 0) }
            for (arm, instructions) in arms where env["SAYKUKU_LONGFORM_ARMS"]?.split(separator: ",").contains(Substring(arm)) ?? true {
                try instructions.write(to: directory.appendingPathComponent("\(outputURL.deletingPathExtension().lastPathComponent)-\(arm)-prompt.txt"), atomically: true, encoding: .utf8)
                let id = UUID().uuidString
                let started = ContinuousClock.now
                // Allow measurement beyond the production deadline, then report whether it would fit.
                let reply = try await client.refineDictation(
                    apiKey: live.apiKey, configuration: live.configuration, instructions: instructions,
                    userMessage: DictationRefinement.userMessage(sample.actual, id: id)
                )
                let milliseconds = Int((started.duration(to: .now) / .milliseconds(1)).rounded())
                let text: String
                let fallback: String?
                switch DictationRefinement.review(reply, input: sample.actual, id: id) {
                case .success(let accepted): text = accepted; fallback = nil
                case .failure(let reason): text = reply; fallback = reason.rawValue
                }
                let row = Row(id: sample.id, arm: arm, input: sample.actual, reference: sample.typeless,
                              output: text, milliseconds: milliseconds, fallback: fallback)
                try output.write(contentsOf: encoder.encode(row) + Data([10]))
                print("Longform \(sample.id) \(arm): \(milliseconds) ms, \(fallback ?? "accepted")")
            }
        }
        print("Longform results: \(outputURL.path)")
    }

    @Test("batch audio holdout follows the structure switch through both passes")
    func audioHoldout() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["SAYKUKU_LONGFORM_AUDIO"] == "1",
              let datasetPath = env["SAYKUKU_LONGFORM_DATASET"],
              let audioPath = env["SAYKUKU_LONGFORM_WAV"],
              let live = try LiveDictationEval(suite: "longform-audio", audioFolder: "unused") else { return }
        struct Sample: Decodable { let id: String; let typeless: String }
        let samples = try JSONDecoder().decode([Sample].self, from: Data(contentsOf:
            URL(fileURLWithPath: datasetPath).appendingPathComponent("splits/holdout.json")))
        let outputURL = URL(fileURLWithPath: audioPath).deletingLastPathComponent()
            .appendingPathComponent(env["SAYKUKU_LONGFORM_RESULT"] ?? "audio-holdout.jsonl")
        try #require(!FileManager.default.fileExists(atPath: outputURL.path), "Use a fresh result name")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? output.close() }
        let client = QwenReasoningClient()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var replayed = 0
        for sample in samples {
            let wavURL = URL(fileURLWithPath: audioPath).appendingPathComponent("\(sample.id).wav")
            guard FileManager.default.fileExists(atPath: wavURL.path) else { continue }
            let wav = try Data(contentsOf: wavURL)
            replayed += 1
            for enabled in [true, false] {
                let started = ContinuousClock.now
                let firstPass = try SpeechDisfluencyCleaner.dictation(await client.transcribeAudio(
                    apiKey: live.apiKey, configuration: live.configuration, wav: wav, structure: enabled
                ), mode: .light)
                let refined = try await DictationRefinement.refine(firstPass, settings: .init(structure: enabled),
                    apiKey: live.apiKey, configuration: live.configuration, client: client)
                let row = Row(id: sample.id, arm: enabled ? "audio-on" : "audio-off", input: firstPass,
                    reference: sample.typeless, output: refined.text,
                    milliseconds: Int((started.duration(to: .now) / .milliseconds(1)).rounded()),
                    fallback: refined.fallback?.rawValue)
                try output.write(contentsOf: encoder.encode(row) + Data([10]))
                print("Longform audio \(sample.id) \(row.arm): \(row.milliseconds) ms, \(row.fallback ?? "accepted")")
            }
        }
        #expect(replayed > 0, "Provide at least one decoded holdout recording")
    }

    @Test("live short list regression")
    func shortLists() async throws {
        guard ProcessInfo.processInfo.environment["SAYKUKU_STRUCTURE_LIST_EVAL"] == "1",
              let live = try LiveDictationEval(suite: "longform-lists", audioFolder: "eval-audio-polish") else { return }
        let client = QwenReasoningClient()
        var passed = 0
        var total = 0
        for (index, sample) in try DictationPolishSample.loadFixture().enumerated() where sample.category == .list {
            let (name, wav) = try live.recording(at: index, spoken: sample.spoken)
            let run = try await live.dictate(wav, targetApp: sample.targetApp, client: client)
            let failures = sample.failures(actual: run.text)
            total += 1
            if failures.isEmpty { passed += 1 }
            print("List \(name): \(failures.map(\.description).joined(separator: "; ")); fallback \(run.fallback?.rawValue ?? "none")")
            print("First pass: \(run.firstPass)")
            print("Final: \(run.text)")
        }
        print("Short list eval: \(passed)/\(total)")
    }

}
