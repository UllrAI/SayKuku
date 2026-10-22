import Foundation
import Testing
@testable import SayKuku

@Suite("Dictation polish fixture and scoring checks")
struct DictationPolishRuleTests {
    @Test("the fixture has 58 distinct samples whose checks are well formed and measure something")
    func fixtureFormat() throws {
        let data = try Data(contentsOf: DictationPolishSample.fixtureURL)
        let objects = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let allowed: Set<String> = [
            "spoken", "expected", "category", "targetApp", "mustContain", "mustNotContain",
            "listItems", "maxLengthRatio", "noTrailingPeriod",
        ]
        for object in objects {
            #expect(Set(object.keys).isSubset(of: allowed), "\(object)")
            #expect(Set(["spoken", "expected", "category"]).isSubset(of: object.keys), "\(object)")
        }

        let samples = try DictationPolishSample.loadFixture()
        let counts = Dictionary(grouping: samples, by: \.category).mapValues(\.count)
        #expect(counts == [.fillers: 11, .selfCorrection: 19, .list: 10, .noExpansion: 10, .chatTone: 8])
        #expect(Set(samples.map(\.spoken)).count == samples.count)

        for sample in samples {
            // The script reads each sentence with plutil and speaks it with say, one line per sample.
            #expect(!sample.spoken.isEmpty && !sample.spoken.contains(where: \.isNewline), "\(sample.spoken)")
            for text in [sample.spoken, sample.expected] {
                #expect(text == text.trimmingCharacters(in: .whitespacesAndNewlines), "\(text)")
            }
            #expect(!(sample.mustContain ?? []).isEmpty, "every sample checks that its meaning survives: \(sample.spoken)")
            #expect((sample.targetApp != nil) == (sample.category == .chatTone), "\(sample.spoken)")
            #expect((sample.noTrailingPeriod == true) == (sample.category == .chatTone), "\(sample.spoken)")
            if sample.category == .list { #expect(sample.listItems != nil, "\(sample.spoken)") }
            if sample.category == .noExpansion { #expect((sample.maxLengthRatio ?? 0) >= 1, "\(sample.spoken)") }
            if let listItems = sample.listItems { #expect(listItems == 0 || listItems >= 3, "\(sample.spoken)") }

            // A phrase to drop has to be said, or the check could never fail.
            for phrase in sample.mustNotContain ?? [] {
                #expect(DictationPolishRule.contains(sample.spoken, phrase), "\(phrase) is not in \(sample.spoken)")
            }
            #expect(sample.failures(actual: sample.expected).isEmpty, "\(sample.expected): \(sample.failures(actual: sample.expected))")
            // Writing down the speech unchanged must fail a sample that asks for cleanup or a list.
            if !(sample.mustNotContain ?? []).isEmpty || (sample.listItems ?? 0) > 0 {
                #expect(!sample.failures(actual: sample.spoken).isEmpty, "\(sample.spoken)")
            }
        }
    }

    @Test("Chinese phrases match ignoring spacing, punctuation and case; English phrases match whole words")
    func contains() {
        #expect(DictationPolishRule.contains("明天上午 11 点在 3 楼会议室见。", "11点"))
        #expect(DictationPolishRule.contains("我们先，我们先把预算定下来", "我们先我们先"))
        #expect(DictationPolishRule.contains("这个PR我晚上再review。", "PR"))
        #expect(DictationPolishRule.contains("You know, the demo is ready.", "you know"))
        #expect(DictationPolishRule.contains("I’ll ship it.", "I'll ship"))
        #expect(!DictationPolishRule.contains("Here is the summary.", "um"))
        #expect(!DictationPolishRule.contains("Send it to Mike.", "Mark"))
        #expect(!DictationPolishRule.contains("我们周四开会。", "周三"))
    }

    @Test("numbered items are counted one per line, and bullets or line breaks are not a paragraph")
    func lists() {
        #expect(DictationPolishRule.numberedItemCount("要做 3 件事：\n1. 打扫\n2、买菜\n3) 打电话\n（4）返程\n就这些。") == 4)
        #expect(DictationPolishRule.numberedItemCount("1.5 GB 的文件已经传完了。") == 0)
        #expect(DictationPolishRule.numberedItemCount("- 打扫\n- 买菜\n- 打电话") == 0)
        #expect(DictationPolishRule.hasListMarker("- 打扫\n- 买菜"))
        #expect(!DictationPolishRule.hasListMarker("第一，交周报，第二，约牙医。"))

        let list = DictationPolishSample(spoken: "s", expected: "e", category: .list, mustContain: ["买菜"], listItems: 3)
        #expect(list.failures(actual: "要做：\n1. 打扫\n2. 买菜\n3. 打电话").isEmpty)
        #expect(list.failures(actual: "要做：1、打扫，2、买菜，3、打电话") == [.init(check: .list, detail: "0/3 items")])
        let paragraph = DictationPolishSample(spoken: "s", expected: "e", category: .list, mustContain: ["约牙医"], listItems: 0)
        #expect(paragraph.failures(actual: "第一，交周报，第二，约牙医。").isEmpty)
        #expect(paragraph.failures(actual: "第一，交周报\n第二，约牙医").map(\.check) == [.list])
    }

    @Test("length counts letters and digits only, against the expected text")
    func length() {
        #expect(DictationPolishRule.contentLength("1. Fix it!\n2. 打扫房间。") == 9)
        let sample = DictationPolishSample(
            spoken: "s", expected: "今天天气怎么样？", category: .noExpansion, mustContain: ["今天天气怎么样"], maxLengthRatio: 1.5
        )
        #expect(sample.failures(actual: "今天天气怎么样呢？").isEmpty)
        #expect(sample.failures(actual: "今天天气怎么样？今天晴，最高气温 25 度。") == [.init(check: .length, detail: "2.43 > 1.50")])
    }

    @Test("a trailing period is caught, while question marks and ellipses are not periods")
    func trailingPeriod() {
        #expect(DictationPolishRule.endsWithPeriod("好的，我马上过来。"))
        #expect(DictationPolishRule.endsWithPeriod("See you tomorrow. "))
        #expect(!DictationPolishRule.endsWithPeriod("好的，我马上过来"))
        #expect(!DictationPolishRule.endsWithPeriod("你今天怎么这么忙呢？"))
        #expect(!DictationPolishRule.endsWithPeriod("等一下..."))
    }

    @Test("mixed-language format rules apply line by line, past list markers")
    func formatRules() {
        let sample = DictationPolishSample(spoken: "s", expected: "e", category: .list, mustContain: ["PR"])
        #expect(sample.failures(actual: "这个 PR 有 3 个问题：\n1. 缺少单元测试\n2. 没有更新文档").isEmpty)
        #expect(sample.failures(actual: "这个PR有3个问题 ：\n1. 缺少单元测试").map(\.check) == [.spacing, .punctuation])
    }

    @Test("failures name each broken check in order, with the phrases involved")
    func failureOrder() {
        let sample = DictationPolishSample(
            spoken: "s", expected: "我们周四开会", category: .chatTone,
            mustContain: ["周四开会"], mustNotContain: ["周三", "不对"], noTrailingPeriod: true
        )
        let failures = sample.failures(actual: "我们周三开会，不对，周五开会。")
        #expect(failures.map(\.description) == ["mustContain: 周四开会", "mustNotContain: 周三, 不对", "trailingPeriod"])
    }
}

@Suite("Dictation polish eval")
struct DictationPolishEvalTests {
    /// Measures the prompts rather than gating on them: failed checks are reported, and only errors fail the test.
    /// The refinement pass runs as in the app; `SAYKUKU_EVAL_TWO_PASS=0` leaves it out.
    @Test("live batch dictation of the polish fixture")
    func liveEval() async throws {
        guard let live = try LiveDictationEval(suite: "dictation-polish", audioFolder: "eval-audio-polish") else { return }
        let client = QwenReasoningClient()
        let samples = try DictationPolishSample.loadFixture()
        var passed: [DictationPolishSample.Category: Int] = [:]
        var total: [DictationPolishSample.Category: Int] = [:]
        var checkFailures: [DictationPolishCheck: Int] = [:]
        var errors = 0
        var exact = 0
        var runs: [LiveDictationEval.Dictation] = []

        for (index, sample) in samples.enumerated() {
            let (name, wav) = try live.recording(at: index, spoken: sample.spoken)
            total[sample.category, default: 0] += 1

            var actual = ""
            var firstPass = ""
            var failure: String?
            do {
                // Default dictation settings plus the sample's target app, finished as the app does before writing.
                let run = try await live.dictate(wav, targetApp: sample.targetApp, client: client)
                runs.append(run)
                actual = run.text
                firstPass = run.firstPass + (run.fallback.map { "  (kept: \($0.rawValue))" } ?? "")
            } catch {
                failure = error.localizedDescription
            }

            let verdict: String
            if let failure {
                errors += 1
                verdict = "ERROR (\(failure))"
            } else {
                let failed = sample.failures(actual: actual)
                for item in failed { checkFailures[item.check, default: 0] += 1 }
                if actual == sample.expected { exact += 1 }
                if failed.isEmpty {
                    passed[sample.category, default: 0] += 1
                    verdict = "PASS"
                } else {
                    verdict = "FAIL (\(failed.map(\.description).joined(separator: "; ")))"
                }
            }
            // Newlines are escaped so every sample prints as five lines and two runs diff line by line.
            let escape = { (text: String) in text.replacingOccurrences(of: "\n", with: "\\n") }
            print("""
            [\(name)] \(sample.category.rawValue) \(verdict)
              spoken:   \(sample.spoken)
              expected: \(escape(sample.expected))
              pass 1:   \(escape(firstPass))
              actual:   \(escape(actual))
            """)
        }

        let passedCount = passed.values.reduce(0, +)
        let rate = String(format: "%.1f", Double(passedCount) * 100 / Double(samples.count))
        let categories = DictationPolishSample.Category.allCases.map {
            "\($0.rawValue) \(passed[$0, default: 0])/\(total[$0, default: 0])"
        }
        let checks = DictationPolishCheck.allCases.map { "\($0.rawValue) \(checkFailures[$0, default: 0])" }
        print("""

        Polish eval: \(passedCount)/\(samples.count) passed (\(rate)%), \(errors) errors; \(categories.joined(separator: ", "))
        Check failures: \(checks.joined(separator: ", "))
        Exact matches: \(exact)/\(samples.count)
        \(LiveDictationEval.refinementSummary(runs))
        """)
        #expect(errors == 0, "Requests failed, so this run can't be compared with another")
    }
}
