import Foundation

enum SpeechDisfluencyCleaner {
    private static let nonSpeech = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters).union(.symbols)

    /// Cleans a dictation reply. One with only whitespace, punctuation or symbols (a stray "。" or `""`)
    /// means nothing was said.
    static func dictation(_ reply: String, mode: DictationCleanup) throws -> String {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.trimmingCharacters(in: nonSpeech).isEmpty else { throw QwenError.noSpeech }
        return clean(text, mode: mode)
    }

    private static let repeatedLeadIn = try! NSRegularExpression(
        pattern: #"(这个|那个|就是|然后|其实|所以|我)(?:[ \t，,、]*\1)+"#
    )

    static func clean(_ text: String, mode: DictationCleanup) -> String {
        var result = ""
        var segment = ""
        var closingQuote: Character?
        let quotes: [Character: Character] = ["“": "”", "「": "」", "『": "』", "\"": "\"", "`": "`"]

        for character in text {
            if let quote = closingQuote {
                result.append(character)
                if character == quote { closingQuote = nil }
            } else if let close = quotes[character] {
                result += cleanSegment(segment, deduplicate: mode == .light)
                segment = ""
                result.append(character)
                closingQuote = close
            } else {
                segment.append(character)
            }
        }
        result += cleanSegment(segment, deduplicate: mode == .light)
        return result
    }

    /// Keeps punctuation inside the text and quoted speech; an ellipsis is not a run of periods to remove.
    static func withoutEndingPunctuation(_ text: String) -> String {
        var result = text
        while let last = result.last {
            if last == ".", result.hasSuffix("...") { break }
            guard "。.!?！？".contains(last) else { break }
            result.removeLast()
        }
        return result
    }

    private static func cleanSegment(_ segment: String, deduplicate: Bool) -> String {
        let range = NSRange(segment.startIndex..<segment.endIndex, in: segment)
        let text = deduplicate
            ? repeatedLeadIn.stringByReplacingMatches(in: segment, range: range, withTemplate: "$1")
            : segment
        let characters = Array(text)
        return String(characters.indices.map { index in
            let character = characters[index]
            let previous = index > 0 ? characters[index - 1] : nil
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            guard isChinese(previous) || isChinese(next) else { return character }
            switch character {
            case ",": return "，"
            case "?": return "？"
            case "!": return "！"
            case ";": return "；"
            case ":": return "："
            // Only a sentence-ending period becomes 。, so names like 报告.pdf stay intact.
            case "." where isChinese(previous) && !isASCIIAlphanumeric(next): return "。"
            default: return character
            }
        })
    }

    private static func isASCIIAlphanumeric(_ character: Character?) -> Bool {
        guard let character, character.isASCII else { return false }
        return character.isLetter || character.isNumber
    }

    private static func isChinese(_ character: Character?) -> Bool {
        character?.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) } ?? false
    }
}
