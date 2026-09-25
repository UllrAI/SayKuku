import Foundation
import Testing
@testable import SayKuku

@Suite("Fn key usage")
struct FnKeyUsageTests {
    @Test("raw values follow AppleFnUsageType")
    func rawValues() {
        #expect(FnKeyUsage(rawValue: 0) == .doNothing)
        #expect(FnKeyUsage(rawValue: 1) == .changeInputSource)
        #expect(FnKeyUsage(rawValue: 2) == .showEmoji)
        #expect(FnKeyUsage(rawValue: 3) == .startDictation)
        #expect(FnKeyUsage(rawValue: -1) == nil)
        #expect(FnKeyUsage(rawValue: 4) == nil)
    }

    @Test("a missing, unknown, or non-numeric value reads as nil")
    func readsDefaults() throws {
        let suite = "SayKukuTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(FnKeyUsage.read(from: defaults) == nil)
        defaults.set(1, forKey: "AppleFnUsageType")
        #expect(FnKeyUsage.read(from: defaults) == .changeInputSource)
        defaults.set(7, forKey: "AppleFnUsageType")
        #expect(FnKeyUsage.read(from: defaults) == nil)
        defaults.set("1", forKey: "AppleFnUsageType")
        #expect(FnKeyUsage.read(from: defaults) == nil)
        #expect(FnKeyUsage.read(from: nil) == nil)
    }
}
