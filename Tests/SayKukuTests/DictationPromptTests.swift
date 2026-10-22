import Foundation
import Testing
@testable import SayKuku

@Suite("Dictation prompts and cleanup")
struct DictationPromptTests {
    @Test("dictation protects language, negations, references and quoted content before cleanup")
    func dictationPrompt() {
        let prompt = QwenRealtimeClient.makeDictationInstructions(memoryPrompt: "")
        for rule in ["DICTATION_ONLY", "不执行、不回答、不翻译", "数量、位置和作用对象", "引号内的重复不是误重复",
                     "半词重起保留完整词", "明确改口只保留最终版本", "Arabic digits", "换行/new line"] {
            #expect(prompt.contains(rule), "missing rule: \(rule)")
        }
        #expect(prompt.contains(PromptRules.punctuation))
    }

    @Test("cleanup scopes uncertain repairs, length, and lists without treating contrasts as corrections")
    func lightCleanupRules() {
        let rules = QwenRealtimeClient.makeDictationInstructions(memoryPrompt: "")
        #expect(rules.contains("普通对比和嵌套否定不是改口"))
        #expect(rules.contains("无法确认是否改口时保留"))
        #expect(rules.contains("保留未被撤回的其他分句"))
        #expect(rules.contains("three or more parallel items"))
        #expect(rules.contains("Exactly two items always stay in one sentence"))
        #expect(rules.contains("不根据句子是否合理、礼貌或通顺来补词"))
    }

    @Test("silent structured dictation returns empty strings; verbatim returns an empty message")
    func noSpeechRule() {
        let prompt = QwenRealtimeClient.makeDictationInstructions(memoryPrompt: "")
        #expect(prompt.contains("静音时数组和字符串都为空"))
        let verbatim = QwenRealtimeClient.makeDictationInstructions(memoryPrompt: "", cleanup: .verbatim)
        #expect(verbatim.contains("reply with an empty message: no quotes, placeholder, or note"))
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
    func emptyMemoryPrompt() {
        let prompt = QwenRealtimeClient.makeDictationInstructions(memoryPrompt: "")
        #expect(!prompt.contains("user context"))
        #expect(!prompt.hasSuffix("\n"))

        let memory = MemoryPrompt.render(entities: [], domains: [.aiVibeCoding], purpose: .transcription)
        let withContext = QwenRealtimeClient.makeDictationInstructions(memoryPrompt: memory)
        #expect(withContext.contains("Use the user context below"))
        #expect(withContext.hasSuffix(memory))
    }

    @Test("dictation preferences change only their prompt instructions")
    func dictationPreferences() {
        let prompt = QwenRealtimeClient.makeDictationInstructions(
            memoryPrompt: "",
            recognitionLanguage: .chinese,
            numberFormat: .spoken
        )

        #expect(prompt.contains("expect mainly Mandarin"))
        #expect(prompt.contains("Simplified Chinese"))
        #expect(prompt.contains("第二优先级"))
        #expect(prompt.contains("keep number words as spoken"))
        #expect(!prompt.contains("Arabic digits"))

        let verbatim = QwenRealtimeClient.makeDictationInstructions(memoryPrompt: "", cleanup: .verbatim)
        #expect(verbatim.contains("Verbatim: keep fillers, repetitions"))
        #expect(verbatim.contains("never turn speech into a list"))
        #expect(!verbatim.contains("Pauses and hesitation"))
        #expect(!verbatim.contains("Light cleanup"))
        #expect(!verbatim.contains("Self-corrections:"))
        #expect(!verbatim.contains("Lists:"))
    }

    @Test("the mixed-language rules are in the dictation prompt for every recognition language")
    func mixedLanguageRules() {
        for language in RecognitionLanguage.allCases {
            let prompt = QwenRealtimeClient.makeDictationInstructions(memoryPrompt: "", recognitionLanguage: language)
            #expect(prompt.contains(PromptRules.mixedLanguage), "missing for \(language)")
            #expect(prompt.contains("ordinary English words in lowercase inside a Chinese sentence, even at its start"))
        }
    }

    @Test("the tone rule follows the cleanup rule only when a target app is named")
    func toneRule() throws {
        let prompt = QwenRealtimeClient.makeDictationInstructions(memoryPrompt: "")
        #expect(!prompt.contains("Tone:"))

        let memory = MemoryPrompt.render(entities: [], domains: [.aiVibeCoding], purpose: .transcription)
        let toned = QwenRealtimeClient.makeDictationInstructions(
            memoryPrompt: memory, targetApp: "微信 (com.tencent.xinWeChat)"
        )
        #expect(toned.contains("Tone: the text will be inserted into 微信 (com.tencent.xinWeChat)."))
        #expect(toned.contains("A short message (one or two short sentences) stays on one line, never a list, with no 。 or . at the end (keep ？ or ！"))
        #expect(toned.contains("A longer message follows the punctuation and list rules."))
        #expect(toned.contains("If you are not sure what kind of app it is, use full punctuation."))
        let cleanup = try #require(toned.range(of: "第二优先级"))
        let tone = try #require(toned.range(of: "Tone:"))
        #expect(cleanup.upperBound < tone.lowerBound)
        #expect(toned.hasSuffix(memory))

        // Without ending punctuation, chat is not told to keep a final ？ or ！ the setting then removes.
        let bare = QwenRealtimeClient.makeDictationInstructions(
            memoryPrompt: "", targetApp: "微信 (com.tencent.xinWeChat)", keepEndingPunctuation: false
        )
        #expect(bare.contains("with no 。 or . at the end. A longer message"))
        #expect(!bare.contains("keep ？ or ！"))
        #expect(bare.contains("Final punctuation setting: do not add a period, question mark, or exclamation mark"))
    }

    @Test("prompt examples are not eval sentences")
    func examplesAvoidEvalFixtures() throws {
        let prompt = QwenRealtimeClient.makeDictationInstructions(memoryPrompt: "", targetApp: "微信 (com.tencent.xinWeChat)")
        var examples = prompt.split(separator: "\n").compactMap { line -> String? in
            guard line.hasPrefix("口述：") || line.hasPrefix("成稿：") else { return nil }
            return String(line.dropFirst(3))
        }
        let inline = try Regex("例如‘([^’]+)’整理为‘([^’]+)’")
        for match in prompt.matches(of: inline) {
            examples += [match.output[1].substring, match.output[2].substring].compactMap { $0.map(String.init) }
        }
        #expect(examples.count >= 14)

        let samples = try DictationPolishSample.loadFixture().flatMap { [$0.spoken, $0.expected] }
            + MixedLanguageSample.loadFixture().flatMap { [$0.spoken, $0.expected] }
        // Letters, digits and Han characters only, so punctuation or spacing can't hide a copy.
        let normalize = { (text: String) in String(text.lowercased().filter { $0.isLetter || $0.isNumber }) }
        for example in examples.map(normalize) {
            for sample in samples.map(normalize) {
                #expect(!sample.contains(example) && !example.contains(sample), "\(example) overlaps \(sample)")
            }
        }
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

    @Test("light cleanup drops hesitation sounds and the pauses around them")
    func interjections() throws {
        let clean = { (text: String) in SpeechDisfluencyCleaner.clean(text, mode: .light) }
        #expect(clean("可以先测试一下，这个客户端有对应的变更。然后客户端现在，嗯，也会自动登录 Web 端了")
            == "可以先测试一下，这个客户端有对应的变更。然后客户端现在也会自动登录 Web 端了")
        #expect(try SpeechDisfluencyCleaner.dictation("然后客户端现在，嗯，也会自动登录 Web 端了。", mode: .light)
            == "然后客户端现在也会自动登录 Web 端了。")
        #expect(clean("现在嗯也会") == "现在也会")
        #expect(clean("现在 嗯 也会") == "现在也会")
        #expect(clean("方案，呃，还可以") == "方案还可以")
        #expect(clean("方案呃还可以") == "方案还可以")
        #expect(clean("方案，嗯嗯，还可以，呃呃，再改") == "方案还可以再改")
        #expect(clean("可以，嗯。") == "可以。")
        #expect(clean("可以，嗯") == "可以")
        #expect(clean("步骤如下，嗯\n1. 安装") == "步骤如下\n1. 安装")
        #expect(clean("苹果、嗯、香蕉") == "苹果、香蕉")
        #expect(clean("然后，嗯，然后我们再开会") == "然后我们再开会")

        // Chinese next to an English word or a digit keeps its one space; two Chinese words get none.
        #expect(clean("用，嗯，GitHub 管理") == "用 GitHub 管理")
        #expect(clean("用 GitHub，呃，管理") == "用 GitHub 管理")
        #expect(clean("下午，嗯，3 点开会") == "下午 3 点开会")
        #expect(clean("We can, 嗯, ship it") == "We can ship it")

        // At the start of a sentence 呃、额、唔 go, and 嗯 goes when a pause and more words follow it.
        #expect(clean("呃，那就这么定了") == "那就这么定了")
        #expect(clean("好的。额，明天再说") == "好的。明天再说")
        #expect(clean("好的。\n唔，明天再说") == "好的。\n明天再说")
        #expect(clean("好的。呃。明天再说") == "好的。明天再说")
        #expect(clean("嗯，我觉得可以") == "我觉得可以")
        #expect(clean("嗯嗯，好的") == "好的")
        #expect(clean("嗯，好的") == "好的")
        #expect(clean("好的。嗯，明天见") == "好的。明天见")
        #expect(clean("嗯好的") == "好的")
        #expect(clean("嗯。好的") == "嗯。好的")

        // 额、唔、呃 inside a word, 嗯 used as a verb, and tone particles stay.
        #expect(clean("金额，还要再核对") == "金额，还要再核对")
        #expect(clean("这个额度不够") == "这个额度不够")
        #expect(clean("余额。") == "余额。")
        #expect(clean("他嗯了一声") == "他嗯了一声")
        #expect(clean("一直呃逆") == "一直呃逆")
        #expect(clean("现在唔该也") == "现在唔该也")
        #expect(clean("好啊，走吧，你呢，来啦，哦，哈") == "好啊，走吧，你呢，来啦，哦，哈")

        // A reply that is only the sound, quoted speech, and verbatim cleanup are left alone.
        for whole in ["嗯", "嗯。", "嗯嗯", "嗯嗯。", "呃，嗯", "嗯，", "那个，", "就是，", "Um,"] {
            #expect(clean(whole) == whole)
        }
        #expect(try SpeechDisfluencyCleaner.dictation("嗯。", mode: .light) == "嗯。")
        #expect(clean("他说“现在，嗯，也会”，嗯，然后走了") == "他说“现在，嗯，也会”，然后走了")
        #expect(clean("写上「呃」两个字") == "写上「呃」两个字")
        let spoken = "客户端现在，嗯，也会登录。呃，就这样"
        #expect(SpeechDisfluencyCleaner.clean(spoken, mode: .verbatim) == spoken)
    }

    @Test("light cleanup drops 那个 and 就是 used as pauses, English fillers, and restarted chunks")
    func fillerWordsAndRestarts() throws {
        let clean = { (text: String) in SpeechDisfluencyCleaner.clean(text, mode: .light) }
        // 那个 between pauses or opening a sentence before a pause is hesitation; 那个方案 is not.
        #expect(clean("这个 PR，那个，我晚上再看") == "这个 PR 我晚上再看")
        #expect(clean("这份文档，那个，下午再改") == "这份文档下午再改")
        #expect(clean("那个，明天的会改到下午") == "明天的会改到下午")
        #expect(clean("好的。那个，明天见") == "好的。明天见")
        #expect(clean("那个方案，然后提交") == "那个方案，然后提交")
        #expect(clean("我要那个，不要这个") == "我要那个，不要这个")
        #expect(clean("就选，那个方案") == "就选，那个方案")

        // 就是 goes only when it opens a sentence before a pause, also after a dropped 那个.
        #expect(clean("就是，明天的会改到下午") == "明天的会改到下午")
        #expect(clean("那个，就是，明天的会") == "明天的会")
        #expect(clean("嗯，那个，我们用 TypeScript 重写") == "我们用 TypeScript 重写")
        #expect(clean("问题就是，我们没时间") == "问题就是，我们没时间")
        #expect(clean("就是这个意思") == "就是这个意思")
        #expect(clean("然后，我们再开会") == "然后，我们再开会")

        // English fillers open a sentence before a comma or sit between commas.
        #expect(clean("You know, the demo is, um, almost ready") == "The demo is almost ready")
        #expect(clean("Um, let's start") == "Let's start")
        #expect(clean("uh, maybe later") == "maybe later")
        #expect(clean("It works, uh, most of the time.") == "It works most of the time.")
        #expect(clean("这个版本，um，下周发") == "这个版本下周发")
        #expect(clean("Do you know him?") == "Do you know him?")
        #expect(clean("Do you know, Sam?") == "Do you know, Sam?")
        #expect(clean("The umbrella, uhm, is wet") == "The umbrella, uhm, is wet")
        #expect(clean("Yum, tasty") == "Yum, tasty")

        // A whole clause of three or more characters said again collapses when the sentence goes on.
        #expect(clean("客户，客户那边已经同意了") == "客户，客户那边已经同意了")
        #expect(clean("我们先，我们先把预算定下来") == "我们先把预算定下来")
        #expect(clean("用，用 GitHub 管理") == "用，用 GitHub 管理")
        #expect(clean("这个文档，这个文档 v2 版") == "这个文档 v2 版")
        #expect(clean("嗯，我们先，我们先把预算定下来") == "我们先把预算定下来")
        #expect(clean("好的。我们先，我们先走") == "好的。我们先走")
        #expect(clean("预算没问题，我们先，我们先走") == "预算没问题，我们先走")
        // Anadiplosis repeats the end of a longer clause on purpose.
        #expect(clean("我们要学习，学习使人进步") == "我们要学习，学习使人进步")
        #expect(clean("这是好人，好人有好报") == "这是好人，好人有好报")
        #expect(clean("他说好，好的我知道了") == "他说好，好的我知道了")
        #expect(clean("他说“行”我们先，我们先走") == "他说“行”我们先，我们先走")
        // Two-character repeats are often a question or a list item, and 、 does not end a clause.
        #expect(clean("你好，你好吗？") == "你好，你好吗？")
        #expect(clean("苹果、香蕉，香蕉很好吃") == "苹果、香蕉，香蕉很好吃")
        #expect(clean("苹果、我们先，我们先走") == "苹果、我们先，我们先走")
        #expect(clean("谢谢，谢谢。") == "谢谢，谢谢。")
        #expect(clean("谢谢，谢谢") == "谢谢，谢谢")
        #expect(clean("好好学习") == "好好学习")
        #expect(clean("谢谢谢谢") == "谢谢谢谢")

        // Quoted speech and verbatim cleanup keep every word.
        #expect(clean("他说“那个，就是，客户，客户那边”") == "他说“那个，就是，客户，客户那边”")
        let spoken = "嗯，那个，客户，客户那边，就是，同意了。Um, you know, OK"
        #expect(SpeechDisfluencyCleaner.clean(spoken, mode: .verbatim) == spoken)
    }

    @Test("filler removal keeps list markers, quotes and English commas, and clears a run of fillers")
    func fillerRemovalEdges() {
        let clean = { (text: String) in SpeechDisfluencyCleaner.clean(text, mode: .light) }
        // A list marker at the start of a line opens a sentence; it keeps its space.
        #expect(clean("- 嗯，买牛奶\n- 呃，买鸡蛋") == "- 买牛奶\n- 买鸡蛋")
        #expect(clean("1) 嗯，买牛奶") == "1) 买牛奶")
        #expect(clean("• 嗯 买牛奶") == "• 买牛奶")
        #expect(clean("* 那个，买牛奶") == "* 买牛奶")
        #expect(clean("12、 呃，买牛奶") == "12、 买牛奶")
        #expect(clean("1. 嗯，买牛奶") == "1. 买牛奶")
        #expect(clean("差-嗯，不多") == "差-不多")

        // Removing one filler leaves the pause for the next one in the run.
        #expect(clean("我们，嗯，那个，就是，去") == "我们去")
        #expect(clean("这个方案，呃，嗯，还行") == "这个方案还行")
        #expect(clean("It is, um, uh, ready") == "It is ready")
        #expect(clean("问题就是，我们没时间") == "问题就是，我们没时间")
        #expect(clean("我们，嗯，就是这么想的") == "我们就是这么想的")

        // Quoted speech next to the filler keeps one pause mark.
        #expect(clean("他说“好”，嗯，走吧") == "他说“好”，走吧")
        #expect(clean("走吧，嗯，“好”他说") == "走吧，“好”他说")
        #expect(clean("He said \"fine\", um, let's go") == "He said \"fine\", let's go")
        #expect(clean("（备注），呃，明天发") == "（备注），明天发")

        // After an opening word English keeps one comma; otherwise, and in Chinese, the clause joins.
        #expect(clean("Well, uh, I think so") == "Well, I think so")
        #expect(clean("However, um, we can ship") == "However, we can ship")
        #expect(clean("Okay. So, um, we ship") == "Okay. So, we ship")
        #expect(clean("这个版本，um，下周发") == "这个版本下周发")

        // A sentence-initial 嗯 goes without a pause too, unless it is all that was said.
        #expect(clean("嗯我觉得可以") == "我觉得可以")
        #expect(clean("好的。嗯我们走") == "好的。我们走")
        #expect(clean("嗯嗯") == "嗯嗯")
        #expect(clean("嗯。好的") == "嗯。好的")

        // A pause on one side only stays; pauses on both sides join the clause.
        #expect(clean("你好，嗯我觉得行") == "你好，我觉得行")
        #expect(clean("我觉得嗯，可以") == "我觉得，可以")
        #expect(clean("现在嗯也会") == "现在也会")
        #expect(clean("现在，嗯，也会") == "现在也会")
        #expect(clean("价格是1.5 嗯，大概") == "价格是1.5，大概")
        #expect(clean("好的\n- 嗯，买牛奶") == "好的\n- 买牛奶")
        #expect(clean("- um, buy milk") == "- buy milk")
        #expect(clean("嗯嗯，好的") == "好的")
        #expect(clean("嗯，嗯，好") == "好")
        #expect(clean("Hi,um,there") == "Hi, there")
        #expect(clean("买苹果，苹果很好吃的") == "买苹果，苹果很好吃的")
    }

    @Test("verbatim cleanup leaves fillers and their pauses as spoken")
    func verbatimKeepsFillers() {
        for text in [
            "你好，嗯我觉得行", "我觉得嗯，可以", "现在嗯也会", "现在，嗯，也会", "价格是1.5 嗯，大概",
            "好的\n- 嗯，买牛奶", "- um, buy milk", "嗯嗯，好的", "嗯，嗯，好", "Hi,um,there", "买苹果，苹果很好吃的",
        ] {
            #expect(SpeechDisfluencyCleaner.clean(text, mode: .verbatim) == text)
        }
    }

    @Test("light cleanup leaves every reference rendering of the eval fixtures as it is")
    func cleanupKeepsFixtureReferences() throws {
        let references = try DictationPolishSample.loadFixture().map(\.expected)
            + MixedLanguageSample.loadFixture().map(\.expected)
        for reference in references {
            #expect(SpeechDisfluencyCleaner.clean(reference, mode: .light) == reference)
        }
    }

    @Test("hesitation removal preserves a standalone acknowledgment and meaningful repetition")
    func interjectionPrompt() {
        let prompt = QwenRealtimeClient.makeDictationInstructions(memoryPrompt: "")
        #expect(prompt.contains("删除纯犹豫和误重复"))
        #expect(prompt.contains("单独一个“嗯”是完整应答，保留"))
        #expect(prompt.contains("强调性重复"))
    }

    @Test("ending punctuation removal keeps internal marks, quoted speech, ellipses, and tokens")
    func endingPunctuation() {
        #expect(SpeechDisfluencyCleaner.withoutEndingPunctuation("第一句。第二句？！") == "第一句。第二句")
        #expect(SpeechDisfluencyCleaner.withoutEndingPunctuation("Hello!?") == "Hello")
        #expect(SpeechDisfluencyCleaner.withoutEndingPunctuation("他说“好。”。") == "他说“好。”")
        #expect(SpeechDisfluencyCleaner.withoutEndingPunctuation("等一下...") == "等一下...")
        #expect(SpeechDisfluencyCleaner.withoutEndingPunctuation("报告.pdf 和 3.14") == "报告.pdf 和 3.14")
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
