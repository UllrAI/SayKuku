import Foundation
import Testing
@testable import SayKuku

/// Reuses identical first-pass responses to compare text refiners without replaying private audio.
@Suite("Paired text refinement replay")
struct DictationRefinementReplayEvalTests {
    @Test("compare an optional refinement prompt over frozen realtime outputs")
    func replay() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["SAYKUKU_REFINEMENT_REPLAY"] == "1",
              let live = try LiveDictationEval(suite: "refinement-replay", audioFolder: "unused") else { return }
        let root = env["SAYKUKU_REFINEMENT_ROOT"].map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent("Build/longform-realtime-20261025")
        let source = root.appendingPathComponent(env["SAYKUKU_REFINEMENT_SOURCE"] ?? "final-long.jsonl")
        let rows = try String(contentsOf: source, encoding: .utf8).split(separator: "\n").map {
            try JSONDecoder().decode(DictationRealtimeLongformEvalTests.Row.self, from: Data($0.utf8))
        }.filter { $0.arm == "realtime" }
        let cases = try JSONDecoder().decode([DictationRealtimeLongformEvalTests.Sample].self,
            from: Data(contentsOf: root.appendingPathComponent("cases.json")))
        let production = env["SAYKUKU_REFINEMENT_PROMPT"] == "production"
        let prompt = production ? "" : try String(contentsOf: root.appendingPathComponent("prompts/" + (env["SAYKUKU_REFINEMENT_PROMPT"] ?? "semantic-flash.txt")), encoding: .utf8)
        let output = root.appendingPathComponent(env["SAYKUKU_REFINEMENT_RESULT"] ?? "semantic-flash.jsonl")
        try #require(!FileManager.default.fileExists(atPath: output.path), "Use a fresh result name")
        FileManager.default.createFile(atPath: output.path, contents: nil)
        let file = try FileHandle(forWritingTo: output)
        defer { try? file.close() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let model = env["SAYKUKU_REFINEMENT_MODEL"] ?? DictationRefinement.model
        let effort = env["SAYKUKU_REFINEMENT_EFFORT"]
        let overrideTimeout = env["SAYKUKU_REFINEMENT_TIMEOUT"].flatMap(Double.init)
        for row in rows {
            let sample = try #require(cases.first { $0.id == row.id })
            let started = ContinuousClock.now
            let id = UUID().uuidString
            let outcome: DictationRefinement.Outcome
            var proposed: String?
            do {
                if production {
                    outcome = try await DictationRefinement.refine(row.text, settings: .init(),
                        apiKey: live.apiKey, configuration: live.configuration, client: QwenReasoningClient(),
                        timeout: overrideTimeout.map { .seconds($0) }, id: id)
                } else {
                let reply = try await withThrowingTaskGroup(of: String.self) { group in
                    group.addTask {
                        if let effort { return try await Self.completion(live: live, model: model, effort: effort,
                            instructions: prompt, userMessage: DictationRefinement.userMessage(row.text, id: id)) }
                        return try await QwenReasoningClient().refineDictation(apiKey: live.apiKey,
                            configuration: live.configuration, instructions: prompt,
                            userMessage: DictationRefinement.userMessage(row.text, id: id))
                    }
                    group.addTask { try await Task.sleep(for: overrideTimeout.map { .seconds($0) } ?? DictationRefinement.timeout(for: row.text)); throw QwenError.timeout }
                    defer { group.cancelAll() }
                    return try await group.next() ?? ""
                }
                let cleanedReply: String
                if env["SAYKUKU_REFINEMENT_DECODE"] == "paragraphs" {
                    struct Structured: Decodable { let paragraphs: [String] }
                    cleanedReply = try JSONDecoder().decode(Structured.self, from: Data(reply.utf8)).paragraphs.joined(separator: "\n\n")
                } else { cleanedReply = reply }
                proposed = cleanedReply
                switch DictationRefinement.review(cleanedReply, input: row.text, id: id, longForm: true) {
                case .success(let text): outcome = .init(text: text, fallback: nil)
                case .failure(let reason): outcome = .init(text: row.text, fallback: reason)
                }
                }
            } catch {
                try Task.checkCancellation()
                outcome = .init(text: row.text, fallback: (error as? QwenError) == .timeout ? .timeout : .failed)
            }
            let elapsed = WorkflowTrace.milliseconds(started.duration(to: .now))
            let result = DictationRealtimeLongformEvalTests.Row(id: row.id, split: row.split, round: row.round,
                candidate: env["SAYKUKU_REFINEMENT_CANDIDATE"] ?? "semantic-flash", arm: "realtime-flash", text: outcome.text, raw: row.text,
                failures: sample.failures(outcome.text), milliseconds: row.milliseconds + elapsed,
                refinementMilliseconds: elapsed, fallback: outcome.fallback?.rawValue, error: row.error,
                promptCharacters: row.promptCharacters, promptBytes: row.promptBytes, proposedText: proposed, refinementModel: model, refinementEffort: effort)
            try file.write(contentsOf: encoder.encode(result) + Data([10]))
            print("Refinement \(row.id.prefix(8)) r\(row.round): \(result.failures), \(elapsed) ms, \(result.fallback ?? "no fallback")")
        }
    }
    @Test("rescore saved proposals through the current production fidelity guard")
    func reviewSaved() throws {
        let env = ProcessInfo.processInfo.environment
        guard let folder = env["SAYKUKU_REFINEMENT_REVIEW_ROOT"],
              let sourceName = env["SAYKUKU_REFINEMENT_REVIEW_SOURCE"],
              let outputName = env["SAYKUKU_REFINEMENT_REVIEW_RESULT"] else { return }
        let root = URL(fileURLWithPath: folder)
        let cases = try JSONDecoder().decode([DictationRealtimeLongformEvalTests.Sample].self,
            from: Data(contentsOf: root.appendingPathComponent("cases.json")))
        let rows = try String(contentsOf: root.appendingPathComponent(sourceName), encoding: .utf8).split(separator: "\n").map {
            try JSONDecoder().decode(DictationRealtimeLongformEvalTests.Row.self, from: Data($0.utf8))
        }
        let output = root.appendingPathComponent(outputName)
        try #require(!FileManager.default.fileExists(atPath: output.path))
        FileManager.default.createFile(atPath: output.path, contents: nil)
        let file = try FileHandle(forWritingTo: output)
        defer { try? file.close() }
        let encoder = JSONEncoder()
        for row in rows {
            let outcome: DictationRefinement.Outcome
            if let proposal = row.proposedText {
                switch DictationRefinement.review(proposal, input: row.raw, id: "review-rescore", longForm: true) {
                case .success(let text): outcome = .init(text: text, fallback: nil)
                case .failure(let reason): outcome = .init(text: row.raw, fallback: reason)
                }
            } else { outcome = .init(text: row.text, fallback: row.fallback.flatMap(DictationRefinement.Fallback.init(rawValue:))) }
            let sample = try #require(cases.first { $0.id == row.id })
            let revised = DictationRealtimeLongformEvalTests.Row(id: row.id, split: row.split, round: row.round,
                candidate: row.candidate + "-content-guard", arm: row.arm, text: outcome.text, raw: row.raw,
                failures: sample.failures(outcome.text), milliseconds: row.milliseconds,
                refinementMilliseconds: row.refinementMilliseconds, fallback: outcome.fallback?.rawValue, error: row.error,
                promptCharacters: row.promptCharacters, promptBytes: row.promptBytes,
                proposedText: row.proposedText, refinementModel: row.refinementModel, refinementEffort: row.refinementEffort)
            try file.write(contentsOf: encoder.encode(revised) + Data([10]))
        }
    }

    private static func completion(live: LiveDictationEval, model: String, effort: String,
                                   instructions: String, userMessage: String) async throws -> String {
        try await live.completion(model: model,
            messages: [["role": "system", "content": instructions], ["role": "user", "content": userMessage]], effort: effort)
    }
}
