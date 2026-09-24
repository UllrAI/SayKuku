import Foundation
import NaturalLanguage

struct CorrectionCandidate: Equatable, Sendable {
    let before: String
    let after: String
}

/// Turns a user's edit of freshly written text into a word- or phrase-level correction.
enum CorrectionExtractor {
    static let maxLength = 32
    /// CJK phrases up to this length are kept whole; longer ones are narrowed to word tokens.
    static let wholePhraseLength = 8

    private enum WordClass { case alphanumeric, cjk }

    /// Character range shared by both texts: `lower` leading and `trailing` trailing characters sit outside it.
    private struct Span {
        var lower: Int
        var trailing: Int

        func range(in characters: [Character]) -> Range<Int> { lower..<(characters.count - trailing) }
    }

    private static let separators: Set<Character> = ["，", "。", "！", "？", "；", "：", "、", ",", ";", "!", "?"]
    private static let cjkRanges: [ClosedRange<UInt32>] = [
        0x1100...0x11FF, 0x3040...0x30FF, 0x3130...0x318F, 0x31F0...0x31FF, 0x3400...0x4DBF,
        0x4E00...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF, 0x20000...0x323AF
    ]

    /// - Parameter writtenRange: UTF-16 range of the text SayKuku wrote inside `expected`.
    static func extract(expected: String, actual: String, writtenRange: Range<Int>) -> CorrectionCandidate? {
        let old = Array(expected), new = Array(actual)
        guard old != new else { return nil }
        let written = characterRange(utf16: writtenRange, in: old)

        let shared = min(old.count, new.count)
        var prefix = 0
        while prefix < shared, old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < shared - prefix, old[old.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }
        // Edits that touch text SayKuku did not write are not corrections of its output.
        guard prefix >= written.lowerBound, old.count - suffix <= written.upperBound else { return nil }

        let edit = Span(lower: prefix, trailing: suffix)
        let oldEdit = edit.range(in: old), newEdit = edit.range(in: new)
        let leading = classes(of: [oldEdit.first.map { old[$0] }, newEdit.first.map { new[$0] }])
        let trailing = classes(of: [oldEdit.last.map { old[$0] }, newEdit.last.map { new[$0] }])
        // Adding or dropping CJK characters is rewording, not a misheard term.
        if oldEdit.isEmpty || newEdit.isEmpty, leading.union(trailing).contains(.cjk) { return nil }

        var span = edit
        while span.lower > written.lowerBound,
              let neighbor = wordClass(of: old[span.lower - 1]), leading.contains(neighbor) {
            span.lower -= 1
        }
        while span.trailing > 0, old.count - span.trailing < written.upperBound,
              let neighbor = wordClass(of: old[old.count - span.trailing]), trailing.contains(neighbor) {
            span.trailing -= 1
        }
        if leading.union(trailing).contains(.cjk),
           max(span.range(in: old).count, span.range(in: new).count) > wholePhraseLength {
            span = narrowToTokens(span, edit: edit, in: new)
        }
        return candidate(before: old[span.range(in: old)], after: new[span.range(in: new)])
    }

    /// Shrinks a long CJK phrase to the word tokens around the edit, using the corrected text.
    private static func narrowToTokens(_ span: Span, edit: Span, in new: [Character]) -> Span {
        let phrase = String(new[span.range(in: new)])
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = phrase
        let tokens = tokenizer.tokens(for: phrase.startIndex..<phrase.endIndex).map {
            phrase.distance(from: phrase.startIndex, to: $0.lowerBound)..<phrase.distance(from: phrase.startIndex, to: $0.upperBound)
        }
        let start = edit.lower - span.lower
        let end = new.count - edit.trailing - span.lower
        var lower = tokens.first(where: { $0.lowerBound < start && start < $0.upperBound })?.lowerBound ?? start
        var upper = tokens.first(where: { $0.lowerBound < end && end < $0.upperBound })?.upperBound ?? end
        // A lone character is rarely a term on its own (e.g. a name split into single characters).
        if upper - lower < 2 {
            lower = tokens.last(where: { $0.upperBound <= lower })?.lowerBound ?? lower
            upper = tokens.first(where: { $0.lowerBound >= upper })?.upperBound ?? upper
        }
        return Span(lower: span.lower + lower, trailing: new.count - span.lower - upper)
    }

    private static func candidate(before: ArraySlice<Character>, after: ArraySlice<Character>) -> CorrectionCandidate? {
        let before = trimmed(before), after = trimmed(after)
        guard !before.isEmpty, !after.isEmpty,
              before.count <= maxLength, after.count <= maxLength,
              !before.contains(where: isSeparator), !after.contains(where: isSeparator) else { return nil }
        let beforeKey = comparisonKey(before), afterKey = comparisonKey(after)
        // Skip punctuation- or case-only edits, number tweaks, and text typed after the output.
        guard !afterKey.hasPrefix(beforeKey),
              !beforeKey.allSatisfy(\.isNumber), !afterKey.allSatisfy(\.isNumber) else { return nil }
        return CorrectionCandidate(before: before, after: after)
    }

    private static func trimmed(_ characters: ArraySlice<Character>) -> String {
        guard let first = characters.firstIndex(where: { wordClass(of: $0) != nil }),
              let last = characters.lastIndex(where: { wordClass(of: $0) != nil }) else { return "" }
        return String(characters[first...last])
    }

    private static func comparisonKey(_ text: String) -> String {
        text.filter { wordClass(of: $0) != nil }.lowercased()
    }

    private static func isSeparator(_ character: Character) -> Bool {
        character.isNewline || separators.contains(character)
    }

    private static func classes(of characters: [Character?]) -> Set<WordClass> {
        Set(characters.compactMap { $0.flatMap { wordClass(of: $0) } })
    }

    private static func wordClass(of character: Character) -> WordClass? {
        guard character.isLetter || character.isNumber else { return nil }
        let isCJK = character.unicodeScalars.contains { scalar in cjkRanges.contains { $0.contains(scalar.value) } }
        return isCJK ? .cjk : .alphanumeric
    }

    /// Maps a UTF-16 range onto whole characters, widening it when it splits a grapheme.
    private static func characterRange(utf16 range: Range<Int>, in characters: [Character]) -> Range<Int> {
        var lower: Int?, upper: Int?
        var start = 0
        for (index, character) in characters.enumerated() {
            let end = start + character.utf16.count
            if lower == nil, end > range.lowerBound { lower = index }
            if upper == nil, start >= range.upperBound { upper = index }
            start = end
        }
        let resolvedUpper = upper ?? characters.count
        return min(lower ?? characters.count, resolvedUpper)..<resolvedUpper
    }
}
