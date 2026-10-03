import Foundation
import Testing
@testable import SayKuku

@Suite("Local usage statistics")
struct UsageStatisticsTests {
    @Test("counts user-perceived non-whitespace characters in mixed-language text")
    func characters() {
        #expect(UsageDay.characterCount("你好 Swift 6!\n👨‍👩‍👧‍👦 e\u{301}\t\u{00a0}") == 11)
        #expect(UsageDay.characterCount(" \n\t") == 0)
    }

    @Test("civil dates retain their collection day across time zones")
    func civilDates() {
        let shanghai = calendar("Asia/Shanghai")
        let losAngeles = calendar("America/Los_Angeles")
        let moment = date(2026, 10, 3, hour: 1, calendar: shanghai)
        #expect(UsageDay.key(for: moment, calendar: shanghai) == "2026-10-03")
        #expect(UsageDay.key(for: moment, calendar: losAngeles) == "2026-10-02")
        let statistics = UsageStatistics(startedAt: moment.addingTimeInterval(-86_400), days: [day("2026-10-03", characters: 20)])
        let localDate = date(2026, 10, 3, hour: 12, calendar: losAngeles)
        let report = UsageReport(statistics: statistics, period: .day, anchor: localDate, now: localDate, calendar: losAngeles)
        #expect(report.totals.characters == 20)
    }

    @Test("weeks follow regional preferences and DST days remain single days")
    func calendarBoundaries() {
        var regional = calendar("America/Los_Angeles")
        regional.firstWeekday = 2
        let now = date(2026, 3, 8, hour: 12, calendar: regional)
        let stats = UsageStatistics(startedAt: date(2026, 1, 1, calendar: regional), days: [day("2026-03-08", characters: 10)])
        let report = UsageReport(statistics: stats, period: .week, anchor: now, now: now, calendar: UsagePeriod.calendar(from: regional))
        #expect(report.points.count == 7)
        #expect(UsageDay.key(for: report.interval.start, calendar: regional) == "2026-03-02")
        #expect(report.interval.duration == 7 * 86_400 - 3_600)
        #expect(report.totals.characters == 10)
        regional.firstWeekday = 1
        let sunday = UsageReport(statistics: stats, period: .week, anchor: now, now: now, calendar: regional)
        #expect(UsageDay.key(for: sunday.interval.start, calendar: regional) == "2026-03-08")
    }

    @Test("a new day includes its collected input even at the midnight refresh")
    func midnightTotals() {
        let calendar = calendar()
        let midnight = date(2026, 10, 3, calendar: calendar)
        let statistics = UsageStatistics(startedAt: date(2026, 10, 1, calendar: calendar), days: [day("2026-10-03", characters: 10)])
        let report = UsageReport(statistics: statistics, period: .day, anchor: midnight, now: midnight, calendar: calendar)
        #expect(report.totals.characters == 10)
        #expect(report.activeDays == 1)
        #expect(!report.points[0].isFuture)
    }

    @Test("comparisons ignore partial today and require complete coverage on both sides")
    func comparablePeriods() throws {
        let calendar = calendar()
        let now = date(2026, 10, 3, hour: 12, calendar: calendar)
        var stats = UsageStatistics(startedAt: date(2026, 8, 1, calendar: calendar), days: [
            day("2026-09-01", characters: 10), day("2026-09-02", characters: 10),
            day("2026-09-03", characters: 10_000), day("2026-10-01", characters: 20),
            day("2026-10-02", characters: 20), day("2026-10-03", characters: 90)
        ])
        let report = UsageReport(statistics: stats, period: .month, anchor: now, now: now, calendar: calendar)
        let comparison = try #require(report.comparison)
        #expect(comparison.days == 2)
        #expect(comparison.change == 1)
        #expect(report.totals.characters == 130)
        #expect(report.activeDays == 3)
        #expect(report.points.filter(\.isFuture).count == 28)
        stats.setEnabled(false, at: date(2026, 9, 2, hour: 1, calendar: calendar))
        stats.setEnabled(true, at: date(2026, 9, 2, hour: 2, calendar: calendar))
        #expect(UsageReport(statistics: stats, period: .month, anchor: now, now: now, calendar: calendar).comparison == nil)
        stats.startedAt = date(2026, 10, 1, hour: 1, calendar: calendar)
        let partial = UsageReport(statistics: stats, period: .month, anchor: now, now: now, calendar: calendar)
        #expect(partial.hasIncompleteCoverage)
        #expect(partial.comparison == nil)
    }

    @Test("app breakdown preserves all characters with five named apps and a remainder")
    func topApps() {
        let calendar = calendar()
        let now = date(2026, 10, 3, hour: 12, calendar: calendar)
        var total = day("2026-10-03", characters: 28)
        total.apps = (1...7).map { UsageDay.App(id: "app\($0)", name: "App \($0)", characters: $0) }
        let report = UsageReport(statistics: UsageStatistics(days: [total]), period: .day, anchor: now, now: now, calendar: calendar)
        #expect(report.topApps.count == 6)
        #expect(report.topApps.first?.id == "app7")
        #expect(report.topApps.last?.characters == 3)
        #expect(report.topApps.reduce(0) { $0 + $1.characters } == 28)
    }

    @Test("purpose categories use fixed fields and never infer from intent labels")
    func purposes() {
        var response = AgentResponse(action: .writeText, intent: "翻译", output: "Text")
        #expect(UsagePurpose(response: response) == .text)
        response.purpose = "translate"
        #expect(UsagePurpose(response: response) == .translate)
        response.purpose = "unknown"
        #expect(UsagePurpose(response: response) == .text)
        response.action = .openURL
        response.purpose = "translate"
        #expect(UsagePurpose(response: response) == .openLink)
        let json = #"{"transcript":"改写","action":"writeText","output":"改好了","purpose":"futureCategory"}"#
        #expect(QwenReasoningClient.decodeAgentResponse(json)?.purpose == "futureCategory")
        let malformedPurpose = #"{"transcript":"改写","action":"writeText","output":"改好了","purpose":123}"#
        #expect(QwenReasoningClient.decodeAgentResponse(malformedPurpose)?.output == "改好了")
        #expect(QwenReasoningClient.agentInstructions.contains("purpose (always for writeText and answer)"))
    }

    @Test("local totals persist independently of history, recordings and sharing")
    @MainActor
    func persistenceAndPrivacy() async throws {
        let environment = AppStateTestEnvironment()
        defer { environment.clean() }
        let state = environment.makeState(dependencies: .fake())
        await state.data.loadStoredData()
        state.settings.historyRetention = .off
        state.settings.analyticsEnabled = false
        state.settings.currentAppAllowed = false
        state.data.recordDictationUsage(text: "private text", duration: 3, snapshot: .fake())
        state.data.recordAgentUsage(AgentResponse(action: .answer, output: "private answer"))
        state.data.clearHistory(keepingStarred: false)
        #expect(await state.data.flushPersistence())
        let saved = try await LocalStore(root: environment.root).load()
        let usage = try #require(saved.usage)
        #expect(usage.days.first?.characters == 11)
        #expect(usage.days.first?.dictationSeconds == 3)
        #expect(usage.days.first?.agentCount == 1)
        #expect(usage.days.first?.apps.first?.name == "")
        let json = String(decoding: try JSONEncoder().encode(usage), as: UTF8.self)
        #expect(!json.contains("private"))
        #expect(!json.contains("Editor"))
        let restored = environment.makeState(dependencies: .fake())
        await restored.data.loadStoredData()
        #expect(restored.data.usageStatistics == usage)
        #expect(restored.settings.localStatisticsEnabled)
        #expect(!restored.settings.analyticsEnabled)
    }

    @Test("clear invalidates old undo receipts, keeps History, and pause survives reload")
    @MainActor
    func resetAndPause() async throws {
        let environment = AppStateTestEnvironment()
        defer { environment.clean() }
        let state = environment.makeState(dependencies: .fake())
        await state.data.loadStoredData()
        state.data.historyEntries = [HistoryEntry(mode: .dictation, app: "Editor", durationSeconds: 1, input: "old", output: "old")]
        let old = try #require(state.data.recordDictationUsage(text: "old", duration: 1, snapshot: .fake()))
        state.data.clearUsageStatistics()
        let new = try #require(state.data.recordDictationUsage(text: "new", duration: 2, snapshot: .fake()))
        state.data.adjustDictationUsage(old, subtract: true)
        #expect(state.data.usageStatistics.days.first?.characters == 3)
        state.settings.localStatisticsEnabled = false
        state.data.recordDictationUsage(text: "ignored", duration: 5, snapshot: .fake())
        state.data.recordAgentUsage(AgentResponse(action: .answer, output: "ignored"))
        #expect(state.data.usageStatistics.days.first?.characters == 3)
        #expect(state.data.usageStatistics.days.first?.agentCount == 0)
        // Correct a previous collected write even while collection is paused.
        state.data.adjustDictationUsage(new, subtract: true)
        #expect(state.data.usageStatistics.days.isEmpty)
        #expect(state.data.historyEntries.count == 1)
        #expect(await state.data.flushPersistence())
        let restored = environment.makeState(dependencies: .fake())
        await restored.data.loadStoredData()
        #expect(!restored.settings.localStatisticsEnabled)
        #expect(restored.data.usageStatistics.pauses.count == 1)
        #expect(restored.data.usageStatistics.pauses.first?.end == nil)
        restored.settings.localStatisticsEnabled = true
        #expect(restored.data.usageStatistics.pauses.first?.end != nil)
    }

    @Test("input collected before disk loading is merged instead of replacing stored totals")
    @MainActor
    func inputDuringLoading() async throws {
        let environment = AppStateTestEnvironment()
        defer { environment.clean() }
        let calendar = UsagePeriod.calendar()
        let oldDay = day(UsageDay.key(for: .now, calendar: calendar), characters: 20)
        let store = LocalStore(root: environment.root)
        try await store.replace(.init(usage: UsageStatistics(startedAt: .now.addingTimeInterval(-86_400), days: [oldDay])))
        let state = environment.makeState(dependencies: .fake())
        let receipt = try #require(state.data.recordDictationUsage(text: "Hello", duration: 2, snapshot: .fake()))
        state.data.adjustDictationUsage(receipt, subtract: true)
        state.data.recordDictationUsage(text: "world", duration: 2, snapshot: .fake())
        state.settings.localStatisticsEnabled = false
        await state.data.loadStoredData()
        #expect(state.data.usageStatistics.days.first?.characters == 25)
        #expect(state.data.usageStatistics.days.first?.dictations == 2)
        #expect(state.data.usageStatistics.pauses.last?.end == nil)
    }

    @Test("version-one histories never backfill unverifiable input; corrupt statistics are backed up")
    @MainActor
    func legacyAndCorruptData() async throws {
        let environment = AppStateTestEnvironment()
        defer { environment.clean() }
        try FileManager.default.createDirectory(at: environment.root, withIntermediateDirectories: true)
        let url = environment.root.appendingPathComponent("store.json")
        try Data(#"{"version":1,"history":[]}"#.utf8).write(to: url)
        let state = environment.makeState(dependencies: .fake())
        await state.data.loadStoredData()
        #expect(state.data.usageStatistics.days.isEmpty)
        #expect(await state.data.flushPersistence())
        let original = Data(#"{"version":2,"history":[],"usage":{"startedAt":"broken"}}"#.utf8)
        try original.write(to: url)
        let store = LocalStore(root: environment.root)
        let snapshot = try await store.load()
        #expect(snapshot.usage == nil)
        guard case .skippedRecords(let count, let backup)? = await store.dataIssue else {
            Issue.record("Expected a backup of the damaged statistics")
            return
        }
        #expect(count == 1)
        #expect(try Data(contentsOf: backup) == original)
    }

    @Test("a newer store reports a loading failure instead of presenting empty statistics")
    @MainActor
    func newerStoreIsUnavailable() async throws {
        let environment = AppStateTestEnvironment()
        defer { environment.clean() }
        try FileManager.default.createDirectory(at: environment.root, withIntermediateDirectories: true)
        let url = environment.root.appendingPathComponent("store.json")
        let original = Data(#"{"version":3,"history":[],"futureField":true}"#.utf8)
        try original.write(to: url)
        let state = environment.makeState(dependencies: .fake())
        await state.data.loadStoredData()
        #expect(state.data.loadingFailed)
        #expect(!state.data.isLoaded)
        state.data.dismissLocalDataIssue()
        #expect(state.data.loadingFailed)
        #expect(try Data(contentsOf: url) == original)
    }
}

private func calendar(_ zone: String = "Asia/Shanghai") -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    calendar.firstWeekday = 2
    return calendar
}

private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, calendar: Calendar) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

private func day(_ key: String, characters: Int) -> UsageDay {
    UsageDay(id: key, characters: characters, dictations: 1, dictationSeconds: 1)
}
