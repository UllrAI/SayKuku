import Foundation

/// Apps whose windows SayKuku never reads from or writes into, matched by bundle ID prefix.
enum SensitiveApps {
    static let bundlePrefixes = [
        "com.1password", "com.agilebits", "com.bitwarden", "com.lastpass", "com.dashlane",
        "org.keepassxc", "com.apple.keychainaccess", "com.apple.passwords"
    ]

    static func contains(bundleID: String) -> Bool {
        let lowercased = bundleID.lowercased()
        return bundlePrefixes.contains { lowercased.hasPrefix($0) }
    }
}
