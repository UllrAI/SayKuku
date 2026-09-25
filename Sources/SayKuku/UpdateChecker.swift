import Foundation
import Observation

/// The `ver.json` payload. `version` and `url` are required; other keys are ignored.
struct UpdateFeed: Decodable, Equatable {
    let version: String
    let url: URL
    let notes: String?

    /// The first lines of `notes`, short enough for an alert.
    var shortNotes: String? {
        let lines = (notes ?? "").split(whereSeparator: \.isNewline).prefix(6)
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}

/// A dotted version such as "1.2.0", compared part by part; missing parts count as 0.
struct AppVersion: Comparable {
    /// Without trailing zeros, so "1.2" equals "1.2.0".
    private let parts: [Int]

    init?(_ string: String) {
        let fields = string.split(separator: ".", omittingEmptySubsequences: false)
        var parts = fields.compactMap { field in
            field.allSatisfy { $0.isASCII && $0.isNumber } ? Int(field) : nil
        }
        guard parts.count == fields.count else { return nil }
        while parts.last == 0 { parts.removeLast() }
        self.parts = parts
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
}

/// Reads `ver.json` and offers a newer `CFBundleShortVersionString`; the download happens in the browser.
/// Results go through the handlers `AppState` sets.
@MainActor
@Observable
final class UpdateChecker {
    typealias Fetch = @Sendable (URL) async throws -> Data
    enum Response { case download, skip, later }
    enum Decision: Equatable { case offer(UpdateFeed), upToDate, failed, silent }

    /// Shows the offer and returns the user's choice.
    @ObservationIgnored var promptHandler: (@MainActor (UpdateFeed, _ currentVersion: String) -> Response)?
    /// Reports `.upToDate` or `.failed`, which only manual checks produce.
    @ObservationIgnored var resultHandler: (@MainActor (Decision) -> Void)?
    private(set) var isChecking = false

    let currentVersion: String
    @ObservationIgnored private let current: AppVersion
    @ObservationIgnored private let feedURL: URL
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let fetch: Fetch
    /// Already offered this launch, so automatic checks stay quiet about it.
    @ObservationIgnored private var offeredVersion: AppVersion?
    @ObservationIgnored private var periodicTask: Task<Void, Never>?

    init?(currentVersion: String, feedURL: URL, settings: AppSettings,
          fetch: @escaping Fetch = { try await UpdateChecker.download($0) }) {
        guard let current = AppVersion(currentVersion) else { return nil }
        self.currentVersion = currentVersion
        self.current = current
        self.feedURL = feedURL
        self.settings = settings
        self.fetch = fetch
    }

    /// The release app's checker; nil without a version or `SayKukuUpdateURL` in Info.plist.
    convenience init?(bundle: Bundle, settings: AppSettings) {
        guard let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String,
              let feed = (bundle.infoDictionary?["SayKukuUpdateURL"] as? String).flatMap(URL.init(string:)) else {
            return nil
        }
        self.init(currentVersion: version, feedURL: feed, settings: settings)
    }

    /// First check 10 seconds after launch, then every 24 hours while the app runs.
    func startPeriodicChecks() {
        guard periodicTask == nil else { return }
        periodicTask = Task { [weak self] in
            var delay = Duration.seconds(10)
            while (try? await Task.sleep(for: delay)) != nil {
                guard let self else { return }
                await self.checkAutomatically()
                delay = .seconds(24 * 60 * 60)
            }
        }
    }

    func checkAutomatically() async {
        if settings.automaticUpdateChecks { await check(manual: false) }
    }

    func checkManually() async { await check(manual: true) }

    /// Automatic checks stay silent unless there is a version to offer; manual checks always answer.
    func decision(for feed: UpdateFeed?, manual: Bool) -> Decision {
        guard let feed, feed.url.scheme == "https", let remote = AppVersion(feed.version) else {
            return manual ? .failed : .silent
        }
        guard remote > current else { return manual ? .upToDate : .silent }
        if manual { return .offer(feed) }
        let skipped = settings.skippedUpdateVersion.flatMap(AppVersion.init)
        return remote == skipped || remote == offeredVersion ? .silent : .offer(feed)
    }

    private func check(manual: Bool) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        let feed: UpdateFeed?
        do {
            feed = try await JSONDecoder().decode(UpdateFeed.self, from: fetch(feedURL))
        } catch {
            Log.update.error("Update check failed: \(Log.describe(error), privacy: .public)")
            feed = nil
        }
        switch decision(for: feed, manual: manual) {
        case .offer(let feed):
            offeredVersion = AppVersion(feed.version)
            if promptHandler?(feed, currentVersion) == .skip { settings.skippedUpdateVersion = feed.version }
        case .silent: break
        case let result: resultHandler?(result)
        }
    }

    /// A plain GET without cache or cookies, so the request carries nothing about the user.
    nonisolated static func download(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else { throw URLError(.badServerResponse) }
        return data
    }

    private nonisolated static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }()
}
