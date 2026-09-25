import Foundation
import Testing
@testable import SayKuku

@Suite("Keychain storage")
struct KeychainStoreTests {
    @Test("legacy values move to the current service")
    func legacyMigration() throws {
        let suffix = UUID().uuidString
        let currentService = "com.saykuku.tests.\(suffix)"
        let legacyService = "\(currentService).legacy"
        let account = "migration"
        let currentStore = KeychainStore(service: currentService)
        let legacyStore = KeychainStore(service: legacyService)
        let store = KeychainStore(service: currentService, legacyServices: [legacyService])

        defer {
            try? store.remove(account)
        }

        try legacyStore.set("original", for: account)
        #expect(try store.string(for: account) == "original")
        #expect(try currentStore.string(for: account) == "original")
        #expect(try legacyStore.string(for: account) == nil)
    }

    @Test("removal clears current and legacy values")
    func removal() throws {
        let suffix = UUID().uuidString
        let currentService = "com.saykuku.tests.\(suffix)"
        let legacyService = "\(currentService).legacy"
        let account = "removal"
        let currentStore = KeychainStore(service: currentService)
        let legacyStore = KeychainStore(service: legacyService)
        let store = KeychainStore(service: currentService, legacyServices: [legacyService])

        defer {
            try? store.remove(account)
        }

        try currentStore.set("current", for: account)
        try legacyStore.set("legacy", for: account)
        try store.remove(account)

        #expect(try currentStore.string(for: account) == nil)
        #expect(try legacyStore.string(for: account) == nil)
    }
}
