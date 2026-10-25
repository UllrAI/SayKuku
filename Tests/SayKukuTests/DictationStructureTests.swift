import Foundation
import Testing
@testable import SayKuku

@Suite("Dictation structure")
struct DictationStructureTests {
    @Test("one compact editing profile respects cleanup and structure modes")
    func profiles() {
        let prompt = QwenRealtimeClient.makeDictationInstructions(memoryPrompt: "")
        #expect(prompt.contains(DictationStructure.realtimeInstructions))
        #expect(prompt.count < 2_700)
        #expect(DictationRefinement.instructions(.init()).count < 4_500)
        #expect(QwenRealtimeClient.makeDictationInstructions(memoryPrompt: "", structure: false).contains(DictationStructure.disabledInstruction))
        #expect(!QwenRealtimeClient.makeDictationInstructions(memoryPrompt: "", cleanup: .verbatim).contains("\"draft\""))
    }

    @Test("structured output exposes final text only and rejects broken or lossy output")
    func decoding() throws {
        let json = #"{"draft":"先检查日志，不对，先备份数据，然后重启服务。","paragraphs":["1. 先备份数据。","2. 然后重启服务。"]}"#
        let text = "先备份数据。然后重启服务。"
        #expect(try DictationStructure.decode(json).text == text)
        #expect(DictationStructure.preview(json) == text)
        for partial in [#"{"draft":"private""#, #"{"draft":"private","paragraphs":["1. partially"#] {
            #expect(DictationStructure.preview(partial).isEmpty)
        }
        #expect(throws: QwenError.invalidResponse) { try DictationStructure.decode(#"{"paragraphs":["text"]}"#) }
        let missing = try DictationStructure.decode(#"{"draft":"保留原文。"}"#)
        #expect(missing == .init(text: "保留原文。", fallback: .invalidStructure))
        let original = String(repeating: "这个数据需要完整保留。", count: 30)
        let lossy = String(decoding: try JSONSerialization.data(withJSONObject: ["draft": original, "paragraphs": ["摘要。"]]), as: UTF8.self)
        #expect(try DictationStructure.decode(lossy) == .init(text: original, fallback: .lengthChanged))
        #expect(try DictationStructure.decode(#"{"draft":"","paragraphs":[]}"#).text.isEmpty)
    }

    @Test("model-selected short chat formatting needs app context and keeps meaningful punctuation")
    func chatEnding() throws {
        func encoded(_ text: String) throws -> String {
            String(decoding: try JSONSerialization.data(withJSONObject:
                ["draft": text, "paragraphs": [text], "omit_final_period": true]), as: UTF8.self)
        }
        for (original, expected) in [("周五见。", "周五见"), ("See you soon.", "See you soon"),
                                     ("几点见？", "几点见？"), ("Great!", "Great!"), ("Maybe...", "Maybe..."),
                                     ("他说“周五见。”", "他说“周五见。”")] {
            let json = try encoded(original)
            #expect(try DictationStructure.decode(json, usesAppTone: true).text == expected)
            #expect(DictationStructure.preview(json, usesAppTone: true) == expected)
            #expect(try DictationStructure.decode(json).text == original)
        }
        let long = String(repeating: "这是一封需要完整标点的长邮件。", count: 12)
        #expect(try DictationStructure.decode(encoded(long), usesAppTone: true).text == long)
    }

    @Test("brief two-item messages stay inline while longer and explicitly formatted lists survive")
    func shortMessageLayout() throws {
        func reply(_ draft: String, _ paragraphs: [String]) throws -> String {
            let json = try JSONSerialization.data(withJSONObject: ["draft": draft, "paragraphs": paragraphs])
            return try DictationStructure.decode(String(decoding: json, as: UTF8.self)).text
        }
        #expect(try reply("先收拾书桌，再带伞。", ["1. 先收拾书桌。", "2. 再带伞。"]) == "先收拾书桌。再带伞。")
        #expect(try reply("Call Alice, then buy bread.", ["Two tasks:", "1. Call Alice.", "2. Buy bread."]) == "Two tasks: Call Alice. Buy bread.")
        for draft in ["先收拾书桌，换行，再带伞。", "他说“先收拾书桌，再带伞”。"] {
            #expect(try reply(draft, ["1. 先收拾书桌。", "2. 再带伞。"]).contains("\n\n"))
        }
        let long = String(repeating: "保留详细的条件与说明。", count: 8)
        #expect(try reply(long + long, ["1. " + long, "2. " + long]).contains("\n\n"))
        #expect(try reply("收拾书桌、带伞、买水。", ["1. 收拾书桌。", "2. 带伞。", "3. 买水。"]).contains("\n\n"))
    }

    @Test("structured dictation makes one response and never leaks JSON into the pill")
    func realtimeResponse() async throws {
        let client = QwenRealtimeClient()
        let session = UUID()
        let sent = EventTypes()
        await client.begin(session: session, send: { await sent.record($0) }, structuredOutput: true)
        try await client.append(Data([0, 0]), session: session)
        let json = #"{"draft":"你好。","paragraphs":["你好。"]}"#
        await client.handle(try JSONSerialization.data(withJSONObject: ["type": "response.text.done", "text": json]), session: session)
        #expect(try await client.commit(session: session, timeout: .seconds(1)) == "你好。")
        #expect(await sent.types == ["input_audio_buffer.append", "input_audio_buffer.commit", "response.create"])
        await client.cancel(session: session)
        let next = UUID()
        await client.begin(session: next, send: { await sent.record($0) })
        await client.handle(try JSONSerialization.data(withJSONObject: ["type": "response.text.done", "text": "短句。"]), session: next)
        #expect(try await client.commit(session: next, timeout: .seconds(1)) == "短句。")
    }

    @Test("the global structure switch also applies to app-specific cleanup formats")
    @MainActor
    func appFormats() {
        let env = AppStateTestEnvironment()
        defer { env.clean() }
        let settings = env.makeState().settings
        settings.dictationCleanup = .verbatim
        settings.saveDictationAppFormat(.init(bundleID: "com.example.editor", cleanup: .light))
        #expect(settings.dictationFormat(for: "com.example.editor").structure)
        settings.structureDictation = false
        #expect(!settings.dictationFormat(for: "com.example.editor").structure)
        #expect(settings.dictationFormat(for: "com.example.editor").cleanup == .light)
    }
}

private actor EventTypes {
    private(set) var types: [String] = []
    func record(_ event: String) {
        let object = try? JSONSerialization.jsonObject(with: Data(event.utf8)) as? [String: Any]
        types.append(object?["type"] as? String ?? "")
    }
}
