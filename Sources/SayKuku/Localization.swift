import Foundation

/// The app's strings live in the SwiftPM resource bundle, not in Bundle.main.
func localized(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .appResources)
}
