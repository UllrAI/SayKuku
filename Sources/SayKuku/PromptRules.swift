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
    /// Low for every request: transcripts must not drift from the audio, and JSON replies must stay parseable.
    static let temperature = 0.1

    /// Introduces a non-empty `MemoryPrompt.render` block; an empty block adds nothing.
    static func appending(_ memoryPrompt: String, to instructions: String, lead: String) -> String {
        memoryPrompt.isEmpty ? instructions : "\(instructions)\n\n\(lead)\n\n\(memoryPrompt)"
    }
}
