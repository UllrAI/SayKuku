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
        // A reply that is only 嗯 or 呃 is what the speaker said, not a pause before the rest.
        let dropsFillers = mode == .light
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
                    segment, mode: mode, dropsFillers: dropsFillers,
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
            segment, mode: mode, dropsFillers: dropsFillers, before: result.last, after: nil
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
        _ segment: String, mode: DictationCleanup, dropsFillers: Bool,
        before: Character?, after: Character?
    ) -> String {
        var text = segment
        if dropsFillers { text = withoutFillers(text, before: before, after: after) }
        if mode == .light {
            // The segment opens a clause unless it follows quoted speech in the same clause.
            let opensClause = before.map { clauseBreaks.contains($0) } ?? true
            for pattern in [repeatedLeadIn, restartedClause] + (opensClause ? [restartedOpening] : []) {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                text = pattern.stringByReplacingMatches(in: text, range: range, withTemplate: "$1")
            }
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
    private static let pauseMarks: Set<Character> = ["，", ",", "、"]
    private static let sentenceEnds: Set<Character> = ["。", "！", "？", ".", "!", "?", "\n"]
    private static let clauseEnds = sentenceEnds.union(["；", ";", "：", ":", "…"])
    private static let englishFillers = ["you know", "um", "uh"]
    private static let closers: Set<Character> = ["”", "」", "』", "\"", "`", "’", ")", "）", "]", "】", "》"]
    private static let openers: Set<Character> = ["“", "「", "『", "\"", "`", "‘", "(", "（", "[", "【", "《"]

    /// "我们先，我们先把预算": a whole clause of three to six characters said again to open the next
    /// one, when the sentence goes on after it. Shorter repeats are often a question or a list
    /// ("你好，你好吗", "香蕉，香蕉很好吃"); "这是好人，好人有好报" repeats only the end of its clause on
    /// purpose, and so do "谢谢，谢谢。" and 好好学习. 、 separates list items, not clauses.
    private static let restartedChunk = #"(\p{Han}{3,6})[ \t]*[，,][ \t]*\1(?=[ \t]*[\p{L}\p{N}])"#
    private static let clauseBreaks: Set<Character> = ["，", ",", "。", "！", "？", ".", "!", "?", "；", ";", "：", ":", "\n"]
    private static let restartedClause = try! NSRegularExpression(
        pattern: #"(?<=[，,。！？.!?；;：:\n])"# + restartedChunk
    )
    private static let restartedOpening = try! NSRegularExpression(pattern: "^" + restartedChunk)

    private enum Filler {
        /// 嗯、呃、额、唔, alone or doubled.
        case sound(onlyEn: Bool)
        case nage
        case jiushi
        /// you know, um, uh; `capitalized` when it opened the sentence with a capital.
        case english(capitalized: Bool)
    }

    /// The filler starting at `index` and its length, or the length of a word to keep as it is.
    private static func filler(
        at index: Int, in characters: [Character], before: Character?, after: Character?
    ) -> (length: Int, filler: Filler?)? {
        let character = characters[index]
        let previous = index > 0 ? characters[index - 1] : before
        if interjections.contains(character) {
            var end = index
            while end < characters.count, interjections.contains(characters[end]) { end += 1 }
            let run = characters[index..<end]
            let touchingRight = end < characters.count ? characters[end] : after
            let onlyEn = run.allSatisfy { $0 == "嗯" }
            // 他嗯了一声 uses 嗯 as a verb; 呃逆 is the one word with 呃. 额 and 唔 also appear
            // inside words (金额, 唔该), so they count only when no letter touches them.
            let isSound = run.allSatisfy { $0 == "嗯" || $0 == "呃" }
                ? !(onlyEn && touchingRight == "了") && !(run.last == "呃" && touchingRight == "逆")
                : !isWordCharacter(previous) && !isWordCharacter(touchingRight)
            return (run.count, isSound ? .sound(onlyEn: onlyEn) : nil)
        }
        if index + 1 < characters.count {
            let pair = String(characters[index...index + 1])
            if pair == "那个" { return (2, .nage) }
            if pair == "就是" { return (2, .jiushi) }
        }
        guard character.isASCII, character.isLetter, !(previous?.isLetter ?? false) else { return nil }
        for phrase in englishFillers where index + phrase.count < characters.count {
            let word = characters[index..<index + phrase.count]
            guard String(word).lowercased() == phrase, [",", "，"].contains(characters[index + phrase.count]) else {
                continue
            }
            return (phrase.count, .english(capitalized: character.isUppercase))
        }
        return nil
    }

    /// Drops fillers the model left in, with the pause marks around them, so "现在，嗯，也会" reads
    /// "现在也会" and "那个，明天的会" reads "明天的会". A sentence-initial 嗯 goes only when more
    /// follows its pause. `before` and `after` are the characters next to the segment, nil at
    /// either end of the text. A filler with a pause on one side only leaves that pause behind;
    /// with pauses on both sides the clauses join.
    private static func withoutFillers(_ segment: String, before: Character?, after: Character?) -> String {
        let characters = Array(segment)
        var output: [Character] = []
        var capitalizeNext = false
        // The last filler was dropped from next to a pause, so the next one still counts as paused.
        // This is that pause mark.
        var carriedPause: Character?
        var pauseCarried: Bool { carriedPause != nil }
        var index = 0
        while index < characters.count {
            guard let (length, filler) = filler(at: index, in: characters, before: before, after: after) else {
                let character = characters[index]
                if capitalizeNext, character.isASCII, character.isLowercase {
                    output += character.uppercased()
                } else {
                    output.append(character)
                }
                capitalizeNext = false
                carriedPause = nil
                index += 1
                continue
            }
            let end = index + length
            guard let filler else {
                output += characters[index..<end]
                capitalizeNext = false
                carriedPause = nil
                index = end
                continue
            }

            var leftPauses = output.endIndex
            while leftPauses > 0, pauses.contains(output[leftPauses - 1]) { leftPauses -= 1 }
            let left = leftPauses > 0 ? output[leftPauses - 1] : before
            var next = end
            while next < characters.count, pauses.contains(characters[next]) { next += 1 }
            let right = next < characters.count ? characters[next] : after
            let startsSentence = (left.map(sentenceEnds.contains) ?? true)
                || followsListMarker(output, segmentOpensLine: before.map { $0 == "\n" } ?? true)
            let leftMarks = output[leftPauses...].filter(pauseMarks.contains)
            let rightMarks = characters[end..<next].filter(pauseMarks.contains)
            let pausedBefore = !leftMarks.isEmpty || pauseCarried
            let leftMark = leftMarks.first ?? carriedPause
            let rightMark = rightMarks.first
            let pausedAfter = end < characters.count && pauseMarks.contains(characters[end])
            // More of the message follows the filler, and after its pause.
            let followed = right.map { !sentenceEnds.contains($0) } ?? false
            let goesOn = next > end && followed

            let drop: Bool
            switch (filler, startsSentence) {
            case (.sound(onlyEn: true), true): drop = followed
            case (.sound(onlyEn: false), true):
                // "好的。呃。" has nothing left of the second sentence.
                if next < characters.count, sentenceEnds.contains(characters[next]) { next += 1 }
                drop = true
            case (.sound, false): drop = true
            case (.nage, true), (.jiushi, true): drop = pausedAfter && goesOn
            case (.nage, false): drop = pausedBefore && pausedAfter
            // 问题就是，我们没时间: 就是 inside a sentence is a word unless a dropped filler led to it.
            case (.jiushi, false): drop = pauseCarried && pausedAfter
            case (.english(let capitalized), true):
                drop = goesOn
                if drop, capitalized { capitalizeNext = true }
            case (.english, false): drop = pausedBefore
            }
            guard drop else {
                output += characters[index..<end]
                capitalizeNext = false
                carriedPause = nil
                index = end
                continue
            }
            if !startsSentence {
                output.removeSubrange(leftPauses...)
                if let right, !clauseEnds.contains(right) {
                    let english: Bool
                    if case .english = filler { english = left?.isASCII ?? false } else { english = false }
                    let mark = (leftMarks + rightMarks).first
                    if let mark, left.map(closers.contains) ?? false || openers.contains(right) {
                        // 他说“好”，嗯，走吧: the quote still needs its pause.
                        output += mark == "," ? ", " : String(mark)
                    } else if english, leftMarks.contains(",") && opensWithOneWord(output) {
                        // "Well, uh, I think so": the comma belongs to the opening word.
                        output += ", "
                    } else if let kept = (leftMark == nil ? rightMark : rightMark == nil ? leftMark : nil),
                              isWordCharacter(left) {
                        // A pause on one side only is still a pause: "你好，嗯我觉得行" keeps its comma.
                        output.append(kept)
                        if kept == ",", isASCIIAlphanumeric(right), !isChinese(left) { output.append(" ") }
                    } else if leftMarks.contains("、") {
                        output.append("、")
                    } else if let left, needsSpace(between: left, and: right) {
                        output.append(" ")
                    }
                }
                carriedPause = leftMarks.first ?? (pausedBefore ? carriedPause : nil) ?? rightMarks.first
            }
            index = next
        }
        return String(output)
    }

    /// The clause so far is a single word, such as Well or However.
    private static func opensWithOneWord(_ output: [Character]) -> Bool {
        let start = output.lastIndex(where: clauseBreaks.contains).map { $0 + 1 } ?? 0
        let clause = output[start...].drop { $0 == " " || $0 == "\t" }
        return !clause.isEmpty && clause.allSatisfy(\.isLetter)
    }

    /// "- 嗯，买牛奶": the line so far is a list marker and a space, so a sentence starts here.
    private static func followsListMarker(_ output: [Character], segmentOpensLine: Bool) -> Bool {
        let lineStart = output.lastIndex(of: "\n").map { $0 + 1 }
        guard lineStart != nil || segmentOpensLine else { return false }
        let line = output[(lineStart ?? 0)...]
        guard let last = line.last, last == " " || last == "\t" else { return false }
        let marker = String(line).trimmingCharacters(in: .whitespaces)
        if ["-", "*", "•"].contains(marker) { return true }
        guard let close = marker.last, ".)、）".contains(close) else { return false }
        let number = marker.dropLast()
        return !number.isEmpty && number.allSatisfy { $0.isASCII && $0.isNumber }
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
