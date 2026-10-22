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
    static let dictationLists = "- Lists: when the speaker enumerates three or more parallel items (marked by 第一/第二/第三、首先/其次/然后/最后、一是/二是/三是, first/second/third, by an ordinal opening each item such as 第一轮/第二轮/第三轮, or announced by a lead-in such as \"有三点\"), write the lead-in as a sentence ending in ：or :, then each item on its own line as \"1. \", \"2. \", \"3. \". Drop the spoken markers that only number the items; keep ordinals that are part of an item (第一轮, the first round). A closing sentence after the items goes on its own line after the list. Exactly two items always stay in one sentence, even with 第一/第二. A story of things that happened in order and a series inside one sentence (A、B 和 C) also stay ordinary sentences."

    /// Low for every request: transcripts must not drift from the audio, and JSON replies must stay parseable.
    static let temperature = 0.1

    /// Introduces a non-empty `MemoryPrompt.render` block; an empty block adds nothing.
    static func appending(_ memoryPrompt: String, to instructions: String, lead: String) -> String {
        memoryPrompt.isEmpty ? instructions : "\(instructions)\n\n\(lead)\n\n\(memoryPrompt)"
    }
}
