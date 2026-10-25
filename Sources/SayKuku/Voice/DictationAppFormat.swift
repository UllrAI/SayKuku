import Foundation

/// Nil fields follow the current global Voice Input setting.
struct DictationAppFormat: Codable, Equatable, Identifiable {
    var bundleID: String
    var keepEndingPunctuation: Bool?
    var cleanup: DictationCleanup?
    var structure: Bool?
    var refine: Bool?
    var numberFormat: DictationNumberFormat?
    var matchAppTone: Bool?
    var expressionPreference = ""

    var id: String { bundleID }

    var isEmpty: Bool {
        keepEndingPunctuation == nil && cleanup == nil && numberFormat == nil
            && structure == nil && refine == nil && matchAppTone == nil
            && expressionPreference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct EffectiveDictationFormat: Sendable {
    let keepEndingPunctuation: Bool
    let cleanup: DictationCleanup
    let structure: Bool
    let refine: Bool
    let numberFormat: DictationNumberFormat
    let matchAppTone: Bool
    let expressionPreference: String

    func targetAppName(for snapshot: TextTargetSnapshot?) -> String? {
        guard matchAppTone, cleanup != .verbatim, let snapshot, !snapshot.isSensitive else { return nil }
        return snapshot.promptAppName
    }
}
