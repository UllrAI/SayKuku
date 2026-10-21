import Foundation

/// One polish fixture sample: what is said, a reference rendering, and the checks a reply is scored by.
/// The checks target one behavior each, so harmless wording or punctuation differences from `expected` still pass.
struct DictationPolishSample: Decodable, Sendable {
    enum Category: String, Decodable, CaseIterable, Sendable {
        case fillers
        case selfCorrection
        case list
        case noExpansion
        case chatTone
    }

    let spoken: String
    /// A reference for reading results; the checks below decide pass or fail, not an exact match.
    let expected: String
    let category: Category
    /// Dictation target app, written as `TextTargetSnapshot.promptAppName` writes it.
    let targetApp: String?
    /// Phrases the reply must keep, matched by `DictationPolishRule.contains`.
    let mustContain: [String]?
    /// Spoken phrases the reply must drop: fillers, repeats, abandoned wording.
    let mustNotContain: [String]?
    /// Numbered items the reply must have, one per line; 0 means a single paragraph with no list.
    let listItems: Int?
    /// The most the reply's content may grow relative to `expected`, by `DictationPolishRule.contentLength`.
    let maxLengthRatio: Double?
    /// The reply must not end with a period.
    let noTrailingPeriod: Bool?

    init(
        spoken: String,
        expected: String,
        category: Category,
        targetApp: String? = nil,
        mustContain: [String]? = nil,
        mustNotContain: [String]? = nil,
        listItems: Int? = nil,
        maxLengthRatio: Double? = nil,
        noTrailingPeriod: Bool? = nil
    ) {
        self.spoken = spoken
        self.expected = expected
        self.category = category
        self.targetApp = targetApp
        self.mustContain = mustContain
        self.mustNotContain = mustNotContain
        self.listItems = listItems
        self.maxLengthRatio = maxLengthRatio
        self.noTrailingPeriod = noTrailingPeriod
    }

    /// Read from the repository next to this file, as `MixedLanguageSample` reads its fixture.
    static let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/dictation-polish.json")

    static func loadFixture() throws -> [DictationPolishSample] {
        try JSONDecoder().decode([DictationPolishSample].self, from: Data(contentsOf: fixtureURL))
    }

    /// Every check `actual` fails, in `DictationPolishCheck` order.
    func failures(actual: String) -> [DictationPolishFailure] {
        var failures: [DictationPolishFailure] = []
        let missing = (mustContain ?? []).filter { !DictationPolishRule.contains(actual, $0) }
        if !missing.isEmpty { failures.append(.init(check: .mustContain, detail: missing.joined(separator: ", "))) }
        let kept = (mustNotContain ?? []).filter { DictationPolishRule.contains(actual, $0) }
        if !kept.isEmpty { failures.append(.init(check: .mustNotContain, detail: kept.joined(separator: ", "))) }

        if let listItems {
            let items = DictationPolishRule.numberedItemCount(actual)
            if listItems > 0, items != listItems {
                failures.append(.init(check: .list, detail: "\(items)/\(listItems) items"))
            } else if listItems == 0, DictationPolishRule.hasListMarker(actual) || actual.contains(where: \.isNewline) {
                failures.append(.init(check: .list, detail: "not a paragraph"))
            }
        }
        if let maxLengthRatio {
            let ratio = Double(DictationPolishRule.contentLength(actual)) / Double(max(DictationPolishRule.contentLength(expected), 1))
            if ratio > maxLengthRatio {
                failures.append(.init(check: .length, detail: String(format: "%.2f > %.2f", ratio, maxLengthRatio)))
            }
        }
        if noTrailingPeriod == true, DictationPolishRule.endsWithPeriod(actual) {
            failures.append(.init(check: .trailingPeriod, detail: ""))
        }

        let lines = DictationPolishRule.linesWithoutListMarkers(actual)
        if lines.contains(where: MixedLanguageRule.lacksSpace) { failures.append(.init(check: .spacing, detail: "")) }
        if lines.contains(where: MixedLanguageRule.misplacesPunctuation) { failures.append(.init(check: .punctuation, detail: "")) }
        return failures
    }
}

/// The behaviors the polish eval counts failures by.
enum DictationPolishCheck: String, CaseIterable, Sendable {
    case mustContain
    case mustNotContain
    case list
    case length
    case trailingPeriod
    /// `MixedLanguageRule.spacing`, line by line with list markers removed.
    case spacing
    /// `MixedLanguageRule.punctuation`, line by line with list markers removed.
    case punctuation
}

struct DictationPolishFailure: Equatable, Sendable, CustomStringConvertible {
    let check: DictationPolishCheck
    let detail: String

    var description: String { detail.isEmpty ? check.rawValue : "\(check.rawValue): \(detail)" }
}

/// Scoring helpers that ignore harmless differences in spacing, punctuation and case.
enum DictationPolishRule {
    /// An ASCII phrase matches whole English words, so `um` is not found in `summary`; any other phrase matches
    /// the letters and digits of the text with whitespace and punctuation removed, so `10点` matches `10 点`.
    static func contains(_ text: String, _ phrase: String) -> Bool {
        if phrase.unicodeScalars.allSatisfy(\.isASCII) {
            let padded = { (text: String) in " " + englishWords(in: text).joined(separator: " ") + " " }
            return padded(text).contains(padded(phrase))
        }
        return compact(text).contains(compact(phrase))
    }

    /// Lines that start with a number marker such as `1.`, `2、`, `3)` or `(4)`.
    static func numberedItemCount(_ text: String) -> Int {
        lines(of: text).count { markerEnd(in: $0, numberedOnly: true) != nil }
    }

    /// Any line starting with a number marker or a bullet such as `-` or `•`.
    static func hasListMarker(_ text: String) -> Bool {
        lines(of: text).contains { markerEnd(in: $0) != nil }
    }

    /// Letters and digits, leaving out whitespace, punctuation and list markers.
    static func contentLength(_ text: String) -> Int {
        linesWithoutListMarkers(text).joined().count { $0.isLetter || $0.isNumber }
    }

    /// A final `。` or `.`; an ellipsis is not a period.
    static func endsWithPeriod(_ text: String) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.hasSuffix("。") || (text.hasSuffix(".") && !text.hasSuffix("..."))
    }

    /// Non-empty trimmed lines with any leading list marker removed, so `1. 打扫房间` is checked as `打扫房间`.
    static func linesWithoutListMarkers(_ text: String) -> [String] {
        lines(of: text).map { line in
            String(line[(markerEnd(in: line) ?? line.startIndex)...]).trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
    }

    /// Where a leading list marker ends. A period followed by a digit starts a decimal such as `1.5 GB`, not an item.
    private static func markerEnd(in line: String, numberedOnly: Bool = false) -> String.Index? {
        if let number = line.prefixMatch(of: #/\d{1,2}(?:\.(?!\d)|[、)）])|[（(]\d{1,2}[)）]/#) {
            return number.range.upperBound
        }
        return numberedOnly ? nil : line.prefixMatch(of: #/[-•*·]\s/#)?.range.upperBound
    }

    private static func lines(of text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func englishWords(in text: String) -> [String] {
        text.lowercased().replacing("’", with: "'").matches(of: #/[a-z0-9]+(?:'[a-z0-9]+)*/#).map { String($0.output) }
    }

    private static func compact(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }
}
