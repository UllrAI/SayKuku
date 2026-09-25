import Foundation
import Testing
@testable import SayKuku

@Suite("Localization")
struct LocalizationTests {
    /// SwiftPM compiles the catalog into `.strings` files inside the app target's resource bundle,
    /// which `localized()` reads through `Bundle.module` under `swift test`; the raw `.xcstrings` is not
    /// shipped, so read the source catalog from the repository, three levels up from this file.
    private static let catalogURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/SayKuku/Resources/Localizable.xcstrings")

    @Test("every catalog key has a Simplified Chinese translation with the same arguments")
    func catalogIsComplete() throws {
        let data = try Data(contentsOf: Self.catalogURL)
        let catalog = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(catalog["sourceLanguage"] as? String == "en")
        let strings = try #require(catalog["strings"] as? [String: Any])
        #expect(!strings.isEmpty)

        for (key, entry) in strings {
            let localizations = (entry as? [String: Any])?["localizations"] as? [String: Any]
            let chinese = forms(of: localizations?["zh-Hans"])
            #expect(!chinese.isEmpty, "\(key) has no zh-Hans translation")
            for form in chinese + forms(of: localizations?["en"]) {
                #expect(!form.text.trimmingCharacters(in: .whitespaces).isEmpty, "\(key) has an empty value")
                // A plural form may leave its number out, as in "Corrected once".
                let matches = form.isPlural
                    ? Set(arguments(in: form.text)).isSubset(of: arguments(in: key))
                    : arguments(in: form.text) == arguments(in: key)
                #expect(matches, "\(key) → \(form.text) changes the arguments")
            }
        }
    }

    /// A plain value, or each plural form; a plural must include `other`.
    private func forms(of localization: Any?) -> [(text: String, isPlural: Bool)] {
        guard let localization = localization as? [String: Any] else { return [] }
        if let value = (localization["stringUnit"] as? [String: Any])?["value"] as? String {
            return [(value, false)]
        }
        let plural = (localization["variations"] as? [String: Any])?["plural"] as? [String: Any] ?? [:]
        guard plural["other"] != nil else { return [] }
        return plural.values.compactMap { form in
            ((form as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
        }.map { ($0, true) }
    }

    /// Sorted format specifier types; translations may reorder them with positions such as `%2$@`.
    private func arguments(in format: String) -> [String] {
        format.replacingOccurrences(of: "%%", with: "")
            .matches(of: #/%(?:\d+\$)?(lld|llu|ld|lu|lf|d|u|f|@)/#)
            .map { String($0.output.1) }
            .sorted()
    }
}
