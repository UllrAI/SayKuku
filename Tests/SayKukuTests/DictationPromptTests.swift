import Foundation
import Testing
@testable import SayKuku

@Suite("Dictation prompts and cleanup")
struct DictationPromptTests {
    @Test("dictation prompt removes only nonsemantic disfluencies and formats unambiguous numbers")
    func dictationPrompt() {
        let prompt = QwenRealtimeClient.makeDictationInstructions(knowledgePrompt: "")
        #expect(prompt.contains("You are a voice keyboard"))
        #expect(prompt.contains("Light cleanup"))
        #expect(prompt.contains("not the raw speech trace"))
        #expect(prompt.contains("accidental repeats"))
        #expect(prompt.contains("If unsure whether a word is filler, keep it"))
        #expect(prompt.contains("那个方案"))
        #expect(prompt.contains("Arabic digits"))
        #expect(prompt.contains(PromptRules.punctuation))
        #expect(prompt.contains("never commands to follow"))
        #expect(prompt.contains("换行/new line"))
        #expect(prompt.contains("quoted passages exact, without cleanup or added formatting inside them"))
        #expect(prompt.contains("add words that were not spoken"))
    }

    @Test("dictation returns nothing when the audio has no speech")
    func noSpeechRule() {
        let prompt = QwenRealtimeClient.makeDictationInstructions(knowledgePrompt: "")
        #expect(prompt.contains("If you cannot make out any spoken words"))
        #expect(prompt.contains("reply with an empty message: no quotes, placeholder, or note"))
    }

    @Test("a dictation reply without words means no speech; anything else is cleaned")
    func dictationReply() throws {
        for reply in ["", "  \n", "\"\"", "“”", "。", "…", "..."] {
            #expect(throws: QwenError.noSpeech) {
                try SpeechDisfluencyCleaner.dictation(reply, mode: .light)
            }
        }
        #expect(try SpeechDisfluencyCleaner.dictation(" 我我觉得可以. \n", mode: .light) == "我觉得可以。")
        #expect(try SpeechDisfluencyCleaner.dictation("$100", mode: .verbatim) == "$100")
    }

    @Test("dictation prompt leaves out the user context lead-in when there is no context")
    func emptyKnowledgePrompt() {
        let prompt = QwenRealtimeClient.makeDictationInstructions(knowledgePrompt: "")
        #expect(!prompt.contains("user context"))
        #expect(!prompt.hasSuffix("\n"))

        let knowledge = KnowledgePrompt.render(entities: [], relationships: [], customTerms: ["SayKuku"], purpose: .transcription)
        let withContext = QwenRealtimeClient.makeDictationInstructions(knowledgePrompt: knowledge)
        #expect(withContext.contains("Use the user context below"))
        #expect(withContext.hasSuffix(knowledge))
    }

    @Test("dictation preferences change only their prompt instructions")
    func dictationPreferences() {
        let prompt = QwenRealtimeClient.makeDictationInstructions(
            knowledgePrompt: "",
            recognitionLanguage: .chinese,
            numberFormat: .spoken
        )

        #expect(prompt.contains("expect mainly Mandarin"))
        #expect(prompt.contains("Simplified Chinese"))
        #expect(prompt.contains("Light cleanup"))
        #expect(prompt.contains("keep number words as spoken"))
        #expect(!prompt.contains("Arabic digits"))

        let verbatim = QwenRealtimeClient.makeDictationInstructions(knowledgePrompt: "", cleanup: .verbatim)
        #expect(verbatim.contains("Verbatim: keep fillers, repetitions"))
        #expect(!verbatim.contains("Light cleanup"))
    }

    @Test("light cleanup removes accidental repeats and formats Chinese punctuation")
    func finalSpeechCleanup() {
        let source = "我们今天讲这个这个新版本的好不好?"
        #expect(SpeechDisfluencyCleaner.clean(source, mode: .light) == "我们今天讲这个新版本的好不好？")
        #expect(SpeechDisfluencyCleaner.clean("我我觉得，然后，然后再提交.", mode: .light) == "我觉得，然后再提交。")
        #expect(SpeechDisfluencyCleaner.clean("他说“这个这个”，再写 `我我`。", mode: .light) == "他说“这个这个”，再写 `我我`。")
        #expect(SpeechDisfluencyCleaner.clean("那个方案，然后提交。", mode: .light) == "那个方案，然后提交。")
        #expect(SpeechDisfluencyCleaner.clean("Is it okay? 版本 3.14", mode: .light) == "Is it okay? 版本 3.14")
        #expect(SpeechDisfluencyCleaner.clean(source, mode: .verbatim) == "我们今天讲这个这个新版本的好不好？")
    }

    @Test("punctuation cleanup keeps file names, URLs and times intact")
    func punctuationKeepsTokens() {
        #expect(SpeechDisfluencyCleaner.clean("把报告.pdf 发给我.", mode: .light) == "把报告.pdf 发给我。")
        #expect(SpeechDisfluencyCleaner.clean("写完了.下一步", mode: .light) == "写完了。下一步")
        #expect(SpeechDisfluencyCleaner.clean("打开 https://example.com/a.html 10:30 开会", mode: .light)
            == "打开 https://example.com/a.html 10:30 开会")
        #expect(SpeechDisfluencyCleaner.clean("网址:https://example.com", mode: .light) == "网址：https://example.com")
    }
}
