import Foundation

/// Text on either side of the cursor in the dictation target, sent with the request so the model can pick
/// homophones, spell names and terms the way the document does, and resolve references. It is never output.
struct DictationCursorContext: Equatable, Sendable {
    /// Characters (grapheme clusters) kept before and after the cursor; the text before matters more.
    static let beforeLimit = 800
    static let afterLimit = 200

    let before: String
    let after: String

    /// The text with the cursor marked. `id` changes per request, so the text cannot fake the marker or
    /// the closing tag of its section.
    func promptSection(id: String) -> String {
        """
        <text_near_cursor id="\(id)">
        \(before)<cursor id="\(id)" />\(after)
        </text_near_cursor id="\(id)">
        """
    }
}

extension DictationCursorContext {
    /// Nil for a sensitive target, a field without readable text, an invalid range, or one with only whitespace
    /// around the cursor. A selection is left out: dictation replaces it, so it would never sit next to the output.
    ///
    /// `selectedRange` is in UTF-16 units, as Accessibility reports it. Bounds that split a character are
    /// widened to whole characters, so the text never starts or ends in half an emoji or surrogate pair.
    init?(snapshot: TextTargetSnapshot?) {
        guard let snapshot, !snapshot.isSensitive, !SensitiveApps.contains(bundleID: snapshot.bundleID),
              let value = snapshot.valueBefore, let range = snapshot.selectedRange else { return nil }
        let text = value as NSString
        guard range.location >= 0, range.length >= 0, range.location + range.length <= text.length else { return nil }
        let start = Self.aligned(range.location, in: text, roundingUp: false)
        let end = Self.aligned(range.location + range.length, in: text, roundingUp: true)
        let before = String(text.substring(to: start).suffix(Self.beforeLimit))
        let after = String(text.substring(from: max(start, end)).prefix(Self.afterLimit))
        guard !(before + after).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        self.init(before: before, after: after)
    }

    /// `offset` moved to the nearest character boundary in the given direction; a boundary stays put.
    private static func aligned(_ offset: Int, in text: NSString, roundingUp: Bool) -> Int {
        guard offset < text.length else { return text.length }
        let character = text.rangeOfComposedCharacterSequence(at: offset)
        guard character.location != offset else { return offset }
        return roundingUp ? character.location + character.length : character.location
    }
}
