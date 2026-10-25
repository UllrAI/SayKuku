import Foundation
import Testing
@testable import SayKuku

/// Diagnostic one-request audio models; these are never counted as a Realtime response.
@Suite("Audio editing model comparison")
struct DictationAudioModelEvalTests {
    @Test("compare a single native audio request on private recordings")
    func compare() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["SAYKUKU_AUDIO_MODEL_EVAL"] == "1",
              let folder = env["SAYKUKU_AUDIO_MODEL_ROOT"],
              let live = try LiveDictationEval(suite: "audio-model", audioFolder: "unused") else { return }
        let root = URL(fileURLWithPath: folder)
        let samples = try JSONDecoder().decode([DictationRealtimeLongformEvalTests.Sample].self,
            from: Data(contentsOf: root.appendingPathComponent("cases.json")))
        let prefixes = (env["SAYKUKU_AUDIO_MODEL_SAMPLES"] ?? "").split(separator: ",")
        let model = env["SAYKUKU_AUDIO_MODEL_MODEL"] ?? "qwen3.8-omni-flash"
        let effort = env["SAYKUKU_AUDIO_MODEL_EFFORT"] ?? "none"
        let prompt = try String(contentsOf: root.appendingPathComponent("prompts/" + (env["SAYKUKU_AUDIO_MODEL_PROMPT"] ?? "polish-rt.txt")), encoding: .utf8)
        let destination = root.appendingPathComponent(env["SAYKUKU_AUDIO_MODEL_RESULT"] ?? "audio-model.jsonl")
        try #require(!FileManager.default.fileExists(atPath: destination.path))
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let file = try FileHandle(forWritingTo: destination)
        defer { try? file.close() }
        let encoder = JSONEncoder()
        for sample in samples where prefixes.contains(where: { sample.id.hasPrefix($0) }) {
            let wav = try Data(contentsOf: root.appendingPathComponent("pcm/\(sample.id).wav"))
            let started = ContinuousClock.now
            var raw = "", text = "", error: String?
            do {
                let audio: [String: Any] = ["type": "input_audio", "input_audio": ["data": "data:audio/wav;base64,\(wav.base64EncodedString())", "format": "wav"]]
                let content: [[String: Any]] = model.contains("asr") ? [audio] : [["type": "text", "text": prompt], audio]
                raw = try await live.completion(model: model, messages: [["role": "user", "content": content]],
                    effort: model.contains("asr") ? nil : effort)
                if model.contains("asr") { text = raw }
                else {
                    struct Reply: Decodable { let paragraphs: [String] }
                    text = try JSONDecoder().decode(Reply.self, from: Data(raw.utf8)).paragraphs.joined(separator: "\n\n")
                }
                text = try SpeechDisfluencyCleaner.dictation(text, mode: .light)
            } catch let failure { error = Log.describe(failure) }
            let row = DictationRealtimeLongformEvalTests.Row(id: sample.id, split: sample.split, round: 1,
                candidate: "batch-\(model)-\(effort)", arm: "batch", text: text, raw: raw,
                failures: error == nil ? sample.failures(text) : ["request"],
                milliseconds: WorkflowTrace.milliseconds(started.duration(to: .now)),
                refinementMilliseconds: nil, fallback: nil, error: error,
                promptCharacters: prompt.count, promptBytes: prompt.utf8.count)
            try file.write(contentsOf: encoder.encode(row) + Data([10]))
            print("Audio \(model) \(sample.id.prefix(8)): \(row.failures), \(row.milliseconds) ms")
        }
    }
}
