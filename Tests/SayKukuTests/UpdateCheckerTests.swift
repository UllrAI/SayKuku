import Foundation
import Testing
@testable import SayKuku

@Suite("Update checker")
@MainActor
struct UpdateCheckerTests {
    private static let feedURL = URL(string: "https://example.com/ver.json")!

    @Test("versions compare part by part, with missing parts as 0")
    func versionComparison() throws {
        let version = { (string: String) in try #require(AppVersion(string)) }
        #expect(try version("1.2.0") > version("1.1.9"))
        #expect(try version("1.10") > version("1.9"))
        #expect(try version("1.2") == version("1.2.0"))
        #expect(try version("2") == version("2.0.0"))
        #expect(try version("1.2.1") > version("1.2"))
        for invalid in ["", "v1.2", "1..2", "1.2.", "1.2-beta", "1.2 ", "+1.2", "-1", "１.２"] {
            #expect(AppVersion(invalid) == nil, "\(invalid) parsed")
        }
    }

    @Test("the feed needs version and url and ignores other keys")
    func feedDecoding() throws {
        let decode = { (json: String) in try JSONDecoder().decode(UpdateFeed.self, from: Data(json.utf8)) }
        let feed = try decode(#"{"version": "1.2.0", "url": "https://example.com/d", "channel": "stable", "size": 3}"#)
        #expect(feed == UpdateFeed(version: "1.2.0", url: URL(string: "https://example.com/d")!, notes: nil))
        #expect(try decode(#"{"version": "1.2.0", "url": "https://example.com/d", "notes": "a\n\nb"}"#).shortNotes == "a\nb")
        #expect(throws: DecodingError.self) { try decode(#"{"url": "https://example.com/d"}"#) }
        #expect(throws: DecodingError.self) { try decode(#"{"version": "1.2.0"}"#) }
    }

    @Test("a newer version is offered once per launch by automatic checks")
    func offersNewVersionOnce() async throws {
        let environment = AppStateTestEnvironment()
        defer { environment.clean() }
        let (checker, recorder) = try makeChecker(environment, serving: "1.2.0")
        await checker.checkAutomatically()
        await checker.checkAutomatically()
        #expect(recorder.offers == ["1.2.0"])
        #expect(recorder.toasts.isEmpty)
        await checker.checkManually()
        #expect(recorder.offers == ["1.2.0", "1.2.0"])
    }

    @Test("a manual check of the current version says it is up to date")
    func upToDate() async throws {
        let environment = AppStateTestEnvironment()
        defer { environment.clean() }
        let (checker, recorder) = try makeChecker(environment, serving: "1.1")
        await checker.checkAutomatically()
        #expect(recorder.toasts.isEmpty)
        await checker.checkManually()
        #expect(recorder.offers.isEmpty)
        #expect(recorder.toasts == [localized("You’re up to date")])
    }

    @Test("a failed check is silent when automatic and reported when manual")
    func failure() async throws {
        let environment = AppStateTestEnvironment()
        defer { environment.clean() }
        let (checker, recorder) = try makeChecker(environment) { _ in throw URLError(.timedOut) }
        await checker.checkAutomatically()
        #expect(recorder.toasts.isEmpty)
        await checker.checkManually()
        #expect(recorder.toasts == [localized("Couldn’t check for updates. Try again later.")])

        let (unreadable, unreadableRecorder) = try makeChecker(environment, serving: "latest")
        await unreadable.checkManually()
        #expect(unreadableRecorder.offers.isEmpty)
        #expect(unreadableRecorder.toasts == [localized("Couldn’t check for updates. Try again later.")])
    }

    @Test("a skipped version stays quiet in automatic checks, even after relaunch")
    func skipVersion() async throws {
        let environment = AppStateTestEnvironment()
        defer { environment.clean() }
        let (checker, recorder) = try makeChecker(environment, serving: "1.2.0", response: .skip)
        await checker.checkAutomatically()
        #expect(recorder.offers == ["1.2.0"])
        #expect(environment.defaults.string(forKey: "updates.skippedVersion") == "1.2.0")

        let (relaunched, relaunchedRecorder) = try makeChecker(environment, serving: "1.2.0")
        await relaunched.checkAutomatically()
        #expect(relaunchedRecorder.offers.isEmpty)
        await relaunched.checkManually()
        #expect(relaunchedRecorder.offers == ["1.2.0"])

        let (newer, newerRecorder) = try makeChecker(environment, serving: "1.3.0")
        await newer.checkAutomatically()
        #expect(newerRecorder.offers == ["1.3.0"])
    }

    @Test("turning off automatic checks leaves only manual ones")
    func automaticChecksOff() async throws {
        let environment = AppStateTestEnvironment()
        defer { environment.clean() }
        environment.defaults.set(false, forKey: "updates.automaticChecks")
        let (checker, recorder) = try makeChecker(environment, serving: "1.2.0")
        await checker.checkAutomatically()
        #expect(recorder.offers.isEmpty)
        await checker.checkManually()
        #expect(recorder.offers == ["1.2.0"])
    }

    @Test("a feed that doesn't link over HTTPS is unreadable")
    func insecureLink() throws {
        let environment = AppStateTestEnvironment()
        defer { environment.clean() }
        let (checker, _) = try makeChecker(environment, serving: "1.2.0")
        let feed = UpdateFeed(version: "1.2.0", url: URL(string: "file:///Applications")!, notes: nil)
        #expect(checker.decision(for: feed, manual: true) == .failed)
        #expect(checker.decision(for: feed, manual: false) == .silent)
    }

    private func makeChecker(
        _ environment: AppStateTestEnvironment,
        serving version: String,
        response: UpdateChecker.Response = .later
    ) throws -> (UpdateChecker, Recorder) {
        let json = Data(#"{"version": "\#(version)", "url": "https://example.com/download"}"#.utf8)
        return try makeChecker(environment, response: response) { _ in json }
    }

    private func makeChecker(
        _ environment: AppStateTestEnvironment,
        response: UpdateChecker.Response = .later,
        fetch: @escaping UpdateChecker.Fetch
    ) throws -> (UpdateChecker, Recorder) {
        let settings = AppSettings(defaults: environment.defaults, keychain: environment.keychain)
        let checker = try #require(UpdateChecker(currentVersion: "1.1.0", feedURL: Self.feedURL, settings: settings, fetch: fetch))
        let recorder = Recorder()
        checker.promptHandler = { feed, _ in
            recorder.offers.append(feed.version)
            return response
        }
        checker.toastHandler = { text, _ in recorder.toasts.append(text) }
        return (checker, recorder)
    }
}

@MainActor
private final class Recorder {
    var offers: [String] = []
    var toasts: [String] = []
}
