import Foundation

/// One fixture sentence: what is said, and the text SayKuku should write for it.
struct MixedLanguageSample: Decodable, Sendable {
    let spoken: String
    let expected: String

    /// Read from the repository next to this file, as `LocalizationTests` reads the string catalog.
    static let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/mixed-language.json")

    static func loadFixture() throws -> [MixedLanguageSample] {
        try JSONDecoder().decode([MixedLanguageSample].self, from: Data(contentsOf: fixtureURL))
    }
}

/// The mixed Chinese-English writing rules the eval counts failures by.
enum MixedLanguageRule: String, CaseIterable, Sendable {
    /// Chinese directly next to an English letter or a digit.
    case spacing
    /// An English word in a different case than expected.
    case casing
    /// An expected English word missing, or an unexpected one added: translated, or misheard.
    case translation
    /// Space around Chinese punctuation, English punctuation next to Chinese, or Chinese punctuation in English.
    case punctuation

    /// The rules `actual` breaks, in declaration order.
    static func violations(actual: String, expected: String) -> [MixedLanguageRule] {
        allCases.filter { rule in
            switch rule {
            case .spacing: lacksSpace(actual)
            case .casing: hasMiscasedWord(actual: actual, expected: expected)
            case .translation: hasTranslatedWord(actual: actual, expected: expected)
            case .punctuation: misplacesPunctuation(actual)
            }
        }
    }

    static func lacksSpace(_ text: String) -> Bool {
        text.contains(#/\p{Script=Han}[A-Za-z0-9]|[A-Za-z0-9]\p{Script=Han}/#)
    }

    static func hasMiscasedWord(actual: String, expected: String) -> Bool {
        let written = englishWords(in: actual)
        let lowercased = Set(written.map { $0.lowercased() })
        return englishWords(in: expected).contains { !written.contains($0) && lowercased.contains($0.lowercased()) }
    }

    static func hasTranslatedWord(actual: String, expected: String) -> Bool {
        Set(englishWords(in: actual).map { $0.lowercased() }) != Set(englishWords(in: expected).map { $0.lowercased() })
    }

    static func misplacesPunctuation(_ text: String) -> Bool {
        let spacedChinese = #/\s[，。？！：；、（）《》]|[，。？！：；、（）《》]\s/#
        // A period followed by a letter or digit belongs to a file name or number, as in 报告.pdf.
        let englishNextToChinese = #/\p{Script=Han}[,?!;:]|\p{Script=Han}\.(?![A-Za-z0-9])|[,.?!;:]\s*\p{Script=Han}/#
        let chineseInEnglish = !text.contains(#/\p{Script=Han}/#) && text.contains(#/[，。？！：；、（）《》]/#)
        return text.contains(spacedChinese) || text.contains(englishNextToChinese) || chineseInEnglish
    }

    /// Words such as `Wi-Fi` and `I'll`, with a curly apostrophe read as a straight one.
    private static func englishWords(in text: String) -> Set<String> {
        Set(text.replacing("’", with: "'").matches(of: #/[A-Za-z][A-Za-z0-9]*(?:['-][A-Za-z0-9]+)*/#).map { String($0.output) })
    }
}
