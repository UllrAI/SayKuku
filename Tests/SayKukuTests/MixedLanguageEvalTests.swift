import Foundation
import Testing
@testable import SayKuku

@Suite("Mixed-language fixture and rule checks")
struct MixedLanguageRuleTests {
    @Test("the fixture has 40 distinct samples, each written by the rules it measures")
    func fixtureFormat() throws {
        let data = try Data(contentsOf: MixedLanguageSample.fixtureURL)
        let objects = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: String]])
        #expect(objects.count == 40)
        for object in objects {
            #expect(Set(object.keys) == ["spoken", "expected"], "\(object)")
        }

        let samples = try MixedLanguageSample.loadFixture()
        #expect(Set(samples.map(\.spoken)).count == samples.count)
        for sample in samples {
            for text in [sample.spoken, sample.expected] {
                #expect(!text.isEmpty && text == text.trimmingCharacters(in: .whitespacesAndNewlines), "\(text)")
            }
            #expect(MixedLanguageRule.violations(actual: sample.expected, expected: sample.expected).isEmpty, "\(sample.expected)")
        }
    }

    @Test("Chinese needs a space before and after English words and digits")
    func spacing() {
        #expect(MixedLanguageRule.lacksSpace("把这个PR merge 一下"))
        #expect(MixedLanguageRule.lacksSpace("下午3点"))
        #expect(MixedLanguageRule.lacksSpace("用 ChatGPT查一下"))
        #expect(!MixedLanguageRule.lacksSpace("把这个 PR merge 一下，iOS 那边"))
        #expect(!MixedLanguageRule.lacksSpace("转化率涨了 15%。"))
        #expect(!MixedLanguageRule.lacksSpace("Let's push the release to next Monday."))
    }

    @Test("English words keep the expected case and are neither dropped nor added")
    func casingAndTranslation() {
        let expected = "我用 ChatGPT 查了一下，这个 bug 在 GitHub 上已经有人提了。"
        #expect(MixedLanguageRule.hasMiscasedWord(actual: "我用 ChatGPT 查了一下，这个 bug 在 Github 上已经有人提了。", expected: expected))
        #expect(!MixedLanguageRule.hasTranslatedWord(actual: "我用 chatgpt 查了一下，这个 BUG 在 github 上已经有人提了。", expected: expected))
        #expect(MixedLanguageRule.hasTranslatedWord(actual: "我用 ChatGPT 查了一下，这个问题在 GitHub 上已经有人提了。", expected: expected))
        #expect(MixedLanguageRule.hasTranslatedWord(actual: "今天的 meeting 改到下午了。", expected: "今天的会改到下午了。"))
        #expect(!MixedLanguageRule.hasMiscasedWord(actual: "I’ll update the README.", expected: "I'll update the README."))
        #expect(!MixedLanguageRule.hasTranslatedWord(actual: "I’ll update the README.", expected: "I'll update the README."))
    }

    @Test("punctuation follows the sentence's language with no space around Chinese marks")
    func punctuation() {
        #expect(MixedLanguageRule.misplacesPunctuation("iOS 那边的 API 明天上线 。"))
        #expect(MixedLanguageRule.misplacesPunctuation("先 review ， 没问题就 approve"))
        #expect(MixedLanguageRule.misplacesPunctuation("会议室的 Wi-Fi 又断了, 你那边能连上吗?"))
        #expect(MixedLanguageRule.misplacesPunctuation("Thanks，I'll take a look."))
        #expect(!MixedLanguageRule.misplacesPunctuation("会议室的 Wi-Fi 又断了，你那边能连上吗？"))
        #expect(!MixedLanguageRule.misplacesPunctuation("把报告.pdf 发给我。"))
        #expect(!MixedLanguageRule.misplacesPunctuation("Thanks, I'll take a look this afternoon."))
    }

    @Test("violations list every broken rule in declaration order")
    func violations() {
        #expect(MixedLanguageRule.violations(actual: "把这个pr merge 一下 。", expected: "把这个 PR merge 一下。")
            == [.spacing, .casing, .punctuation])
        #expect(MixedLanguageRule.violations(actual: "把这个 PR 合并一下。", expected: "把这个 PR merge 一下。") == [.translation])
    }
}

@Suite("Mixed-language eval")
struct MixedLanguageEvalTests {
    /// `NN.wav` for fixture line NN and `NN.txt` with the text it was spoken from, written by
    /// `Scripts/eval-mixed-language.sh`.
    private static let audioDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Build/eval-audio")

    /// Measures the prompt rather than gating on it: mismatches are reported, and only errors fail the test.
    @Test("live batch dictation of the mixed-language fixture")
    func liveEval() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["SAYKUKU_LIVE_QWEN_TEST"] == "1" else { return }
        let key = try #require(try KeychainStore().string(for: "qwen.apiKey"))
        let configuration = QwenConfiguration(
            region: environment["SAYKUKU_TEST_REGION"].flatMap(QwenRegion.init(rawValue:)) ?? .beijing,
            workspaceID: environment["SAYKUKU_TEST_WORKSPACE_ID"] ?? "",
            realtimeModel: QwenModelCatalog.defaultRealtimeModel,
            reasoningModel: QwenModelCatalog.defaultReasoningModel
        )
        let client = QwenReasoningClient()
        let samples = try MixedLanguageSample.loadFixture()
        var passed = 0
        var errors = 0
        var ruleFailures: [MixedLanguageRule: Int] = [:]

        for (index, sample) in samples.enumerated() {
            let name = String(format: "%02d", index + 1)
            let spoken = try String(contentsOf: Self.audioDirectory.appendingPathComponent("\(name).txt"), encoding: .utf8)
            try #require(spoken == sample.spoken, "\(name).wav is out of date; run Scripts/eval-mixed-language.sh")
            let wav = try Data(contentsOf: Self.audioDirectory.appendingPathComponent("\(name).wav"))

            var actual = ""
            var failure: String?
            do {
                // Default dictation settings, cleaned and trimmed as the app does before writing a reply.
                let reply = try await client.transcribeAudio(apiKey: key, configuration: configuration, wav: wav)
                actual = try SpeechDisfluencyCleaner.dictation(reply, mode: .light)
            } catch {
                failure = error.localizedDescription
            }

            let verdict: String
            if let failure {
                errors += 1
                verdict = "ERROR (\(failure))"
            } else if actual == sample.expected {
                passed += 1
                verdict = "PASS"
            } else {
                let broken = MixedLanguageRule.violations(actual: actual, expected: sample.expected)
                for rule in broken { ruleFailures[rule, default: 0] += 1 }
                verdict = "FAIL" + (broken.isEmpty ? "" : " (\(broken.map(\.rawValue).joined(separator: ", ")))")
            }
            print("""
            [\(name)] \(verdict)
              spoken:   \(sample.spoken)
              expected: \(sample.expected)
              actual:   \(actual)
            """)
        }

        let rate = String(format: "%.1f", Double(passed) * 100 / Double(samples.count))
        let rules = MixedLanguageRule.allCases.map { "\($0.rawValue) \(ruleFailures[$0, default: 0])" }
        print("""

        Mixed-language eval: \(passed)/\(samples.count) passed (\(rate)%), \(errors) errors
        Rule failures: \(rules.joined(separator: ", "))
        """)
        #expect(errors == 0, "Requests failed, so this run can't be compared with another")
    }
}
