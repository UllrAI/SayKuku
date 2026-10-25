import Foundation
import Testing
@testable import SayKuku

@Suite("Dictation settings live checks")
struct DictationSettingsLiveTests {
    @Test("layout off retains cleanup quality and explicit formatting")
    func combinations() async throws {
        guard ProcessInfo.processInfo.environment["SAYKUKU_CLEANUP_SETTINGS_EVAL"] == "1",
              let live = try LiveDictationEval(suite: "cleanup-settings", audioFolder: "unused") else { return }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var rows: [[String: Any]] = []
        let input = "这个，发布之前有三件事情需要确认。第一，数据库必须先备份，不要直接修改生产数据，如果备份失败就暂停发布，通知值班人员检查日志。第二，通知客服周五，不对，周六晚上上线，客服确认收到消息以后再切换流量。第三，保留旧版本至少七天，出现问题时先回滚，不要清空日志，所有操作都要记录时间和负责人。最后请把检查结果发给我。"
        let explicit = "请逐项检查：\n1. 数据库必须先备份，不要直接修改生产数据，如果备份失败就暂停发布，通知值班人员检查日志。\n2. 通知客服周六晚上上线，客服确认收到消息以后再切换流量。\n3. 保留旧版本至少七天，出现问题时先回滚，不要清空日志，所有操作都要记录时间和负责人。\n最后请把检查结果发给我。"
        for (id, source, structure) in [("long-inline", input, false), ("long-layout", input, true),
                                         ("explicit-layout", explicit, false), ("short-question", "这次修改是不是，呃，是不是还需要复核？", false)] {
            let outcome = try await DictationRefinement.refine(source, settings: .init(structure: structure),
                apiKey: live.apiKey, configuration: live.configuration, client: QwenReasoningClient())
            #expect(outcome.fallback == nil, "\(id): \(String(describing: outcome.fallback))")
            if id == "long-inline" {
                #expect(!outcome.text.contains("\n"))
                #expect(!outcome.text.contains("周五"))
                for word in ["备份失败", "暂停发布", "周六", "回滚", "不要清空日志", "负责人", "发给我"] {
                    #expect(outcome.text.contains(word), "\(id): missing \(word)")
                }
            } else if id == "long-layout" || id == "explicit-layout" {
                #expect(outcome.text.contains("\n1. ") && outcome.text.contains("\n3. "), "\(id)")
            } else {
                #expect(outcome.text == "这次修改是不是还需要复核？")
            }
            rows.append(["id": id, "text": outcome.text, "fallback": outcome.fallback?.rawValue ?? "none"])
        }
        // The existing short-audio fixture is reused unchanged for a paired realtime comparison.
        let pcm = try Data(contentsOf: root.appendingPathComponent("Build/eval-audio-polish/23.wav")).dropFirst(44)
        for structure in [false, true] {
            let result = try await DictationRealtimeLongformEvalTests.realtime(Data(pcm),
                instructions: QwenRealtimeClient.makeDictationInstructions(memoryPrompt: "", structure: structure),
                structuredOutput: true, userMessage: nil, live: live)
            if structure {
                #expect(result.text.contains("\n1. ") && result.text.contains("\n3. "))
            } else {
                #expect(!result.text.contains("\n"))
            }
            for word in ["打扫房间", "买菜", "电话"] { #expect(result.text.contains(word)) }
            rows.append(["id": "realtime-layout-\(structure)", "text": result.text])
        }
        try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
            .write(to: root.appendingPathComponent("Build/cleanup-settings-live.json"))
    }
}
