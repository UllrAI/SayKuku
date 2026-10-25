import CryptoKit
import Foundation
import Testing
@testable import SayKuku

@Suite("Single-pass dictation output")
struct SinglePassDictationTests {
    @Test("the single-pass prompt freezes the current structure rules byte for byte")
    func frozenCurrentStructureRules() {
        let prompt = SinglePassDictation.instructions(recognitionLanguage: .automatic, numberFormat: .preferDigits, targetApp: nil, keepEndingPunctuation: true)
        #expect(prompt.count == 4_617)
        #expect(prompt.utf8.count == 8_125)
        let digest = SHA256.hash(data: Data(prompt.utf8)).map { String(format: "%02x", $0) }.joined()
        #expect(digest == "84f22452756acf618b64ac32040f4d557afbc7085004eee9317f91c1d7844e46")
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
        #expect(prompt.count == 7_128)
        #expect(prompt.utf8.count == 8_180)
        let digest = SHA256.hash(data: Data(prompt.utf8)).map { String(format: "%02x", $0) }.joined()
        #expect(digest == "39d7af15a79db3c1f5dd4f7f5cd4d51dca64f450778d158d9854b8caa41daaa4")
    }

    @Test("only the final field is returned, including quoted repeats, escapes, literal JSON, and silence")
    func finalText() throws {
        for text in ["他说“不要不要改”，我同意。", "1. 测试\n2. 发布", "\"quoted\" \\ path", "{\"text\":\"literal code\"}", ""] {
            let object: [String: Any] = ["negations": ["不", "别"], "transcript": "unprocessed restart", "text": text]
            let reply = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
            #expect(try SinglePassDictation.text(from: reply) == text)
        }
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
