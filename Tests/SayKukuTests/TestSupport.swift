import Foundation
@testable import SayKuku

/// Isolated defaults, storage folder, and Keychain service for building `AppState` in tests.
@MainActor
struct AppStateTestEnvironment {
    let suite: String
    let defaults: UserDefaults
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let keychain = KeychainStore(service: "com.saykuku.tests.\(UUID().uuidString)")

    init() {
        let suite = "SayKukuTests.\(UUID().uuidString)"
        self.suite = suite
        defaults = UserDefaults(suiteName: suite)!
    }

    /// A new state reads whatever earlier states in this environment saved.
    func makeState(store: LocalStore? = nil, persistenceDelay: Duration = .milliseconds(500)) -> AppState {
        AppState(
            defaults: defaults, store: store ?? LocalStore(root: root),
            keychain: keychain, persistenceDelay: persistenceDelay
        )
    }

    func clean() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
        try? keychain.remove("qwen.apiKey")
    }
}
