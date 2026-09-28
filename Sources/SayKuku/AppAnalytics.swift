import Foundation

/// Sends a small, fixed set of product events to the app's Umami website.
@MainActor
final class AppAnalytics {
    typealias Send = @Sendable (URLRequest) async throws -> Int

    private let endpoint: URL
    private let websiteID: String
    private let version: String
    private let settings: AppSettings
    private let defaults: UserDefaults
    private let send: Send
    private var didReportLaunch = false
    private var firstLaunchInFlight = false
    private var activeDayInFlight: String?

    private enum Key {
        static let installID = "analytics.installID"
        static let firstLaunchSent = "analytics.firstLaunchSent"
        static let activeDay = "analytics.activeDay"
    }

    convenience init?(bundle: Bundle, settings: AppSettings, defaults: UserDefaults) {
        guard let urlString = bundle.infoDictionary?["SayKukuAnalyticsURL"] as? String,
              let endpoint = URL(string: urlString), endpoint.scheme == "https",
              let websiteID = bundle.infoDictionary?["SayKukuAnalyticsWebsiteID"] as? String,
              UUID(uuidString: websiteID) != nil,
              let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String else { return nil }
        self.init(endpoint: endpoint, websiteID: websiteID, version: version,
                  settings: settings, defaults: defaults)
    }

    init(endpoint: URL, websiteID: String, version: String, settings: AppSettings,
         defaults: UserDefaults, send: @escaping Send = AppAnalytics.sendRequest) {
        self.endpoint = endpoint
        self.websiteID = websiteID
        self.version = version
        self.settings = settings
        self.defaults = defaults
        self.send = send
    }

    func start() {
        guard settings.analyticsEnabled else { return }
        if !didReportLaunch {
            didReportLaunch = true
            track("app_launch", path: "/app")
        }
        if !defaults.bool(forKey: Key.firstLaunchSent), !firstLaunchInFlight {
            firstLaunchInFlight = true
            track("app_first_launch", path: "/app") { [weak self] success in
                self?.firstLaunchInFlight = false
                if success { self?.defaults.set(true, forKey: Key.firstLaunchSent) }
            }
        }
    }

    func completedVoiceInput(characters: Int) {
        completed("voice_input_completed", path: "/voice-input", characters: characters)
    }

    func completedVoiceAgent(characters: Int) {
        completed("voice_agent_completed", path: "/voice-agent", characters: characters)
    }

    private func completed(_ name: String, path: String, characters: Int) {
        guard settings.analyticsEnabled else { return }
        let day = Self.utcDay(for: .now)
        if defaults.string(forKey: Key.activeDay) != day, activeDayInFlight != day {
            activeDayInFlight = day
            track("app_active", path: "/app") { [weak self] success in
                self?.activeDayInFlight = nil
                if success { self?.defaults.set(day, forKey: Key.activeDay) }
            }
        }
        track(name, path: path, characters: characters)
    }

    private func track(_ name: String, path: String, characters: Int? = nil,
                       onCompletion: (@MainActor (Bool) -> Void)? = nil) {
        guard settings.analyticsEnabled else { return }
        let installID: String
        if let saved = defaults.string(forKey: Key.installID) {
            installID = saved
        } else {
            installID = UUID().uuidString
            defaults.set(installID, forKey: Key.installID)
        }
        let event = Event(type: "event", payload: .init(
            website: websiteID,
            hostname: "mac.say.anikuku.com",
            url: path,
            name: name,
            id: installID,
            data: .init(app_version: version, characters: characters)
        ))
        Task { [weak self] in
            guard let self else { return }
            guard settings.analyticsEnabled else { onCompletion?(false); return }
            do {
                var request = URLRequest(url: endpoint)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("SayKuku/\(version) (macOS; native app)", forHTTPHeaderField: "User-Agent")
                request.httpBody = try JSONEncoder().encode(event)
                let success = (200..<300).contains(try await send(request))
                onCompletion?(success && settings.analyticsEnabled)
            } catch {
                // Statistics never interrupt the voice workflow.
                onCompletion?(false)
            }
        }
    }

    private static func utcDay(for date: Date) -> String {
        let components = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: date)
        return String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
    }

    private struct Event: Encodable {
        let type: String
        let payload: Payload

        struct Payload: Encodable {
            let website: String
            let hostname: String
            let url: String
            let name: String
            let id: String
            let data: Data

            struct Data: Encodable {
                let app_version: String
                let characters: Int?
            }
        }
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    private nonisolated static func sendRequest(_ request: URLRequest) async throws -> Int {
        let (_, response) = try await session.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode ?? 0
    }
}
