import Foundation

/// Rules and settings shared by the dictation and Agent requests.
enum PromptRules {
    static let punctuation = "Punctuation: use ，。？！ in Chinese sentences and English punctuation in English sentences."
    /// How mixed Chinese and English is written; harmless for text in only one language.
    static let mixedLanguage = """
    Mixed Chinese and English:
    - Put one space between Chinese and an English word or a digit, and no space around Chinese punctuation. Use full-width punctuation only in Chinese sentences.
    - Write product and technical names in their official case (iOS, macOS, GitHub, ChatGPT, Xcode, iPhone, API, PR, URL, JSON, Wi-Fi), ordinary English words in lowercase inside a Chinese sentence, even at its start, and people's names capitalized.
    - Keep words spoken in English in English and words spoken in Chinese in Chinese; never translate either way.
    - When a number is written in digits, put one space between it and a Chinese word or a unit (3 个, 2 GB, 下午 3 点), but none before % (10%).
    - A sentence takes the punctuation of its main language: a Chinese sentence with English words still uses Chinese punctuation.
    """
    static let dictationLists = """
    - Paragraphs: when the dictation changes topic, such as background, then a question, then another request, insert one blank line between the topics. Do not wait for the speaker to say 新段落 or new paragraph. Do not summarize, add facts, or add a lead-in the speaker did not say, such as "有几个问题想确认", "以下是", or "Here is".
    - Lists: Two or more independent questions in a row, or two or more independent requests in a row, each go on their own line as "1. ", "2. ", "3. ", even when the speaker never says 第一, first, or "有几点", and including when there are only two. Do the same when the speaker marks those items with 第一/第二, 一是/二是, first/second/third, or a spoken lead-in such as "有三点" or "有两点". Drop markers that only number the items; keep ordinals that are part of an item (第一轮, 第二步, the first round). Keep a lead-in the speaker actually said as its own sentence before the items, and put a closing sentence on its own line after the list. Never invent that lead-in. When 首先, 然后, and 最后 only order events in time, keep that story one paragraph and do not number it. A story of things that happened in order, a series inside one sentence (A、B 和 C), and a short message stay one paragraph and are not numbered. The "1. " markers and blank lines are formatting, not added words.
    - 分段和列表必须执行：话题一变就空一行。编号只用于连续两个及以上的独立问题，或连续两个及以上的独立要求；即使没说「第一」或「有几点」，也各自一行，写成「1. 」「2. 」「3. 」。「第一/第二」「一是/二是」「有两点」「有三点」以及 first/second 仍然编号。只起编号作用的标记删掉；第二步、第一轮这类序数留在事项里。不要补「有几个问题想确认」「以下是」或「Here is」。「首先/然后/最后」如果只是时间顺序，保持一段，不编号。按时间讲的经过、句内并列（A、B 和 C）和短消息保持一段，不编号。
    - Example, not text to output. "账号是哪个？权限够不够？" becomes "1. 账号是哪个？" and "2. 权限够不够？" on separate lines, with no added lead-in. "版本周五已经发出。你把日志级别调高。再给设计补一张图。" becomes "版本周五已经发出。" then a blank line, then "1. 你把日志级别调高。" and "2. 再给设计补一张图。" each on its own line. "早上先开会，然后改了两处文案，下午才发出去。" stays one paragraph.
    """

    /// Low for every request: transcripts must not drift from the audio, and JSON replies must stay parseable.
    static let temperature = 0.1

    /// Introduces a non-empty `MemoryPrompt.render` block; an empty block adds nothing.
    static func appending(_ memoryPrompt: String, to instructions: String, lead: String) -> String {
        memoryPrompt.isEmpty ? instructions : "\(instructions)\n\n\(lead)\n\n\(memoryPrompt)"
    }
}
