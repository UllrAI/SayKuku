import Foundation

/// The app's strings live in the SwiftPM resource bundle, not in Bundle.main.
func localized(_ key: String.LocalizationValue, locale: Locale = .current) -> String {
    String(localized: key, bundle: .appResources, locale: locale)
}

/// The catalog language macOS picked for this launch from `AppleLanguages`, such as "en" or "zh-Hans".
let interfaceLanguage = Locale.Language(identifier: Bundle.appResources.preferredLocalizations.first ?? "en")

/// Errors that adopt `LocalizedError` describe themselves; system errors such as `URLError`
/// don't, so they get a plain message rather than Foundation's, which follows the system language.
func localizedError(_ error: Error) -> String {
    if let description = (error as? LocalizedError)?.errorDescription { return description }
    if error is URLError { return localized("Couldn’t connect. Check your network and try again.") }
    return localized("Something went wrong. Try again.")
}
