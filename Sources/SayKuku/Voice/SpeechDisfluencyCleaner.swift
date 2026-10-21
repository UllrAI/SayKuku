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
        // A reply that is only 嗯 or 呃 is what the speaker said, not a pause inside a sentence.
        let dropsInterjections = mode == .light
            && !text.filter { !interjections.contains($0) }.trimmingCharacters(in: nonSpeech).isEmpty
        var result = ""
        var segment = ""
        var closingQuote: Character?
        let quotes: [Character: Character] = ["“": "”", "「": "」", "『": "』", "\"": "\"", "`": "`"]

        for character in text {
            if let quote = closingQuote {
                result.append(character)
                if character == quote { closingQuote = nil }
            } else if let close = quotes[character] {
                result += cleanSegment(
                    segment, mode: mode, dropsInterjections: dropsInterjections,
                    before: result.last, after: character
                )
                segment = ""
                result.append(character)
                closingQuote = close
            } else {
                segment.append(character)
            }
        }
        result += cleanSegment(
            segment, mode: mode, dropsInterjections: dropsInterjections, before: result.last, after: nil
        )
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

    private static func cleanSegment(
        _ segment: String, mode: DictationCleanup, dropsInterjections: Bool,
        before: Character?, after: Character?
    ) -> String {
        var text = segment
        if dropsInterjections { text = withoutInterjections(text, before: before, after: after) }
        if mode == .light {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = repeatedLeadIn.stringByReplacingMatches(in: text, range: range, withTemplate: "$1")
        }
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

    private static let interjections: Set<Character> = ["嗯", "呃", "额", "唔"]
    private static let pauses: Set<Character> = ["，", ",", "、", " ", "\t"]
    private static let sentenceEnds: Set<Character> = ["。", "！", "？", ".", "!", "?", "\n"]
    private static let clauseEnds = sentenceEnds.union(["；", ";", "：", ":", "…"])

    /// Drops hesitation sounds the model left in, with the pause marks around them, so
    /// "现在，嗯，也会" reads "现在也会". 嗯 opening a sentence may be assent, so that one stays
    /// for the model to judge. 额 and 唔 also appear inside words (金额, 唔该), so they go only
    /// when nothing but pauses or punctuation touches them. `before` and `after` are the characters
    /// next to the segment, nil at either end of the text.
    private static func withoutInterjections(_ segment: String, before: Character?, after: Character?) -> String {
        let characters = Array(segment)
        var output: [Character] = []
        var index = 0
        while index < characters.count {
            guard interjections.contains(characters[index]) else {
                output.append(characters[index])
                index += 1
                continue
            }
            var end = index
            while end < characters.count, interjections.contains(characters[end]) { end += 1 }
            let run = characters[index..<end]
            let touchingLeft = index > 0 ? characters[index - 1] : before
            let touchingRight = end < characters.count ? characters[end] : after
            let onlyEn = run.allSatisfy { $0 == "嗯" }
            let standsAlone = !isWordCharacter(touchingLeft) && !isWordCharacter(touchingRight)
            // 他嗯了一声 uses 嗯 as a verb; 呃逆 is the one word with 呃.
            let isSound = run.allSatisfy { $0 == "嗯" || $0 == "呃" }
                ? !(onlyEn && touchingRight == "了") && !(run.last == "呃" && touchingRight == "逆")
                : standsAlone
            guard isSound else {
                output += run
                index = end
                continue
            }

            var leftPauses = output.endIndex
            while leftPauses > 0, pauses.contains(output[leftPauses - 1]) { leftPauses -= 1 }
            let left = leftPauses > 0 ? output[leftPauses - 1] : before
            var next = end
            while next < characters.count, pauses.contains(characters[next]) { next += 1 }
            let right = next < characters.count ? characters[next] : after

            if left.map(sentenceEnds.contains) ?? true {
                if onlyEn {
                    output += run
                    index = end
                    continue
                }
                // "好的。呃。" has nothing left of the second sentence.
                if next < characters.count, sentenceEnds.contains(characters[next]) { next += 1 }
                index = next
                continue
            }

            let pausedWithEnumerationComma = output[leftPauses...].contains("、")
            output.removeSubrange(leftPauses...)
            if let right, !clauseEnds.contains(right) {
                if pausedWithEnumerationComma {
                    output.append("、")
                } else if let left, needsSpace(between: left, and: right) {
                    output.append(" ")
                }
            }
            index = next
        }
        return String(output)
    }

    /// Chinese next to an English word or a digit, or two English words, keep one space between them.
    private static func needsSpace(between left: Character, and right: Character) -> Bool {
        (isASCIIAlphanumeric(left) && (isASCIIAlphanumeric(right) || isChinese(right)))
            || (isChinese(left) && isASCIIAlphanumeric(right))
    }

    private static func isWordCharacter(_ character: Character?) -> Bool {
        guard let character else { return false }
        return character.isLetter || character.isNumber
    }

    private static func isASCIIAlphanumeric(_ character: Character?) -> Bool {
        guard let character, character.isASCII else { return false }
        return character.isLetter || character.isNumber
    }

    private static func isChinese(_ character: Character?) -> Bool {
        character?.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) } ?? false
    }
}
