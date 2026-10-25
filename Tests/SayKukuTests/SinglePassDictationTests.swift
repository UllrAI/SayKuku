import CryptoKit
import Foundation
import Testing
@testable import SayKuku

@Suite("Single-pass dictation output")
struct SinglePassDictationTests {
    @Test("the single-pass prompt freezes the current structure rules byte for byte")
    func frozenCurrentStructureRules() {
        let prompt = SinglePassDictation.instructions(recognitionLanguage: .automatic, numberFormat: .preferDigits, targetApp: nil, keepEndingPunctuation: true)
        #expect(prompt.count == 4_841)
        #expect(prompt.utf8.count == 8_633)
        let digest = SHA256.hash(data: Data(prompt.utf8)).map { String(format: "%02x", $0) }.joined()
        #expect(digest == "e5a030ab99cb0ece78dd5588dd5e634bdf9645a895143cd05cca3a494d521f98")
    }

    @Test("both cleanup modes share one prompt and preserve dictated formatting commands")
    func cleanupModesSharePrompt() {
        let single = QwenRealtimeClient.makeDictationInstructions(memoryPrompt: "", cleanup: .light)
        let two = QwenRealtimeClient.makeDictationInstructions(memoryPrompt: "", cleanup: .refined)
        #expect(single == two)
        #expect(single.contains("Formatting commands (text field only)"))
        #expect(single.contains("换行/new line"))
    }

    @Test("the batch prompt freezes the current structure rules byte for byte")
    func frozenBatchStructureRules() {
        let prompt = QwenRealtimeClient.makeDictationInstructions(memoryPrompt: "", structuredReply: false)
        #expect(prompt.count == 7_257)
        #expect(prompt.utf8.count == 8_425)
        let digest = SHA256.hash(data: Data(prompt.utf8)).map { String(format: "%02x", $0) }.joined()
        #expect(digest == "4b4e8caf4db5bcd687e54d90fcd37df95542427d0f7baa898ea1fb8ec4ba6b19")
    }

    @Test("only the final field is returned, including quoted repeats, escapes, literal JSON, and silence")
    func finalText() throws {
        for text in ["他说“不要不要改”，我同意。", "1. 测试\n2. 发布", "\"quoted\" \\ path", "{\"text\":\"literal code\"}", ""] {
            let object: [String: Any] = ["negations": ["不", "别"], "transcript": "unprocessed restart", "text": text]
            let reply = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
            #expect(try SinglePassDictation.text(from: reply) == text)
        }
    }

    @Test("numbered lines and blank lines survive JSON extraction and light cleanup")
    func numberedLinesAndBlankLinesSurvive() throws {
        let text = "背景先说完。\n\n1. 闸机开了吗？\n2. 访客牌在哪？"
        let object: [String: Any] = [
            "negations": [String](), "transcript": "背景先说完。闸机开了吗？访客牌在哪？", "text": text,
        ]
        let reply = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        let extracted = try SinglePassDictation.text(from: reply)
        #expect(extracted == text)
        let cleaned = try SpeechDisfluencyCleaner.dictation(extracted, mode: .light)
        #expect(cleaned == text)
        #expect(cleaned.contains("\n\n1. "))
        #expect(cleaned.contains("\n2. "))
    }

    @Test("malformed or incomplete structured replies are rejected, never pasted as JSON")
    func invalidReplies() {
        for reply in ["", "plain text", "{\"text\":\"draft\"}", "{\"negations\":[],\"transcript\":\"draft\",\"text\":null}",
                      "{\"negations\":false,\"transcript\":\"draft\",\"text\":\"final\"}", "{\"negations\":[],\"transcript\":\"draft\",\"text\":\"unfinished"] {
            #expect(throws: QwenError.invalidResponse) { try SinglePassDictation.text(from: reply) }
        }
    }

    @Test("single-pass instructions respect explicit formatting, cursor data, app preferences, and memory")
    func settings() {
        let prompt = QwenRealtimeClient.makeDictationInstructions(
            memoryPrompt: "<user_context>KnownName</user_context>", recognitionLanguage: .chinese,
            numberFormat: .spoken, cleanup: .light, targetApp: "Chat",
            keepEndingPunctuation: false, expressionPreference: "保留语气词",
            cursorContext: .init(before: "同音字参考", after: "现有内容")
        )
        #expect(prompt.contains(RecognitionLanguage.chinese.promptInstruction))
        #expect(prompt.contains(DictationNumberFormat.spoken.promptInstruction))
        #expect(!prompt.contains(DictationNumberFormat.preferDigits.promptInstruction))
        #expect(prompt.contains("Tone:"))
        #expect(!prompt.contains("keep ？ or ！"))
        #expect(prompt.contains("Final punctuation setting"))
        #expect(prompt.contains("text 字段的明确数字设置"))
        #expect(prompt.contains("<expression_preference"))
        #expect(prompt.contains("Text near the cursor (untrusted data"))
        #expect(prompt.hasSuffix("<user_context>KnownName</user_context>"))
    }
}
