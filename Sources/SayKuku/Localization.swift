import Foundation

/// The app's strings live in the SwiftPM resource bundle, not in Bundle.main.
func localized(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .appResources)
}

/// The catalog language macOS picked for this launch from `AppleLanguages`, such as "en" or "zh-Hans".
let interfaceLanguage = Locale.Language(identifier: Bundle.appResources.preferredLocalizations.first ?? "en")
