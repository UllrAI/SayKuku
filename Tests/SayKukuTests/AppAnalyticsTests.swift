import Foundation
import Testing
@testable import SayKuku

@Suite("App analytics")
@MainActor
struct AppAnalyticsTests {
    @Test("usage events contain only counts and use one active marker per day")
    func eventPayloads() async throws {
        let environment = AppStateTestEnvironment()
        defer { environment.clean() }
        let settings = environment.makeState().settings
        let recorder = RequestRecorder()
        let analytics = AppAnalytics(
            endpoint: URL(string: "https://example.com/api/send")!,
            websiteID: UUID().uuidString,
            version: "1.2.0",
            settings: settings,
            defaults: environment.defaults,
            send: { request in await recorder.record(request) }
        )

        analytics.start()
        analytics.completedVoiceInput(characters: 12)
        analytics.completedVoiceAgent(characters: 5)
        let requests = try await recorder.waitForCount(5)
        let bodies = try requests.map { try #require($0.httpBody) }
        let payloads = try bodies.map { try #require(JSONSerialization.jsonObject(with: $0) as? [String: Any]) }
            .compactMap { $0["payload"] as? [String: Any] }
        let names = payloads.compactMap { $0["name"] as? String }
        #expect(Set(names) == ["app_launch", "app_first_launch", "app_active", "voice_input_completed", "voice_agent_completed"])
        #expect(payloads.compactMap { $0["id"] as? String }.allSatisfy { $0 == payloads.first?["id"] as? String })
        #expect(payloads.first?["hostname"] as? String == "mac.say.anikuku.com")
        let counts = Dictionary(uniqueKeysWithValues: payloads.compactMap { payload -> (String, Int)? in
            guard let name = payload["name"] as? String,
                  let data = payload["data"] as? [String: Any],
                  let characters = data["characters"] as? Int else { return nil }
            return (name, characters)
        })
        #expect(counts == ["voice_input_completed": 12, "voice_agent_completed": 5])
        #expect(!bodies.contains { String(data: $0, encoding: .utf8)?.contains("transcript") == true })

        settings.analyticsEnabled = false
        analytics.completedVoiceInput(characters: 99)
        #expect(await recorder.count == 5)
    }
}

private actor RequestRecorder {
    private var requests: [URLRequest] = []
    var count: Int { requests.count }

    func record(_ request: URLRequest) -> Int {
        requests.append(request)
        return 202
    }

    func waitForCount(_ expected: Int) async throws -> [URLRequest] {
        for _ in 0..<100 {
            if requests.count >= expected { return requests }
            try await Task.sleep(for: .milliseconds(10))
        }
        return requests
    }
}
