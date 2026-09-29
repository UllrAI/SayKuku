import Foundation

/// Nil fields follow the current global Voice Input setting.
struct DictationAppFormat: Codable, Equatable, Identifiable {
    var bundleID: String
    var keepEndingPunctuation: Bool?
    var cleanup: DictationCleanup?
    var numberFormat: DictationNumberFormat?
    var matchAppTone: Bool?
    var expressionPreference = ""

    var id: String { bundleID }

    var isEmpty: Bool {
        keepEndingPunctuation == nil && cleanup == nil && numberFormat == nil
            && matchAppTone == nil && expressionPreference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct EffectiveDictationFormat: Sendable {
    let keepEndingPunctuation: Bool
    let cleanup: DictationCleanup
    let numberFormat: DictationNumberFormat
    let matchAppTone: Bool
    let expressionPreference: String

    func targetAppName(for snapshot: TextTargetSnapshot?) -> String? {
        guard matchAppTone, cleanup == .light, let snapshot, !snapshot.isSensitive else { return nil }
        return snapshot.promptAppName
    }
}
