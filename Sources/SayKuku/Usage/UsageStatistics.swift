import Foundation

/// Daily totals only. Text, audio, window titles and individual sessions are never stored here.
struct UsageStatistics: Codable, Equatable {
    var startedAt: Date = .now
    var days: [UsageDay] = []
    var pauses: [Pause] = []

    struct Pause: Codable, Equatable {
        var start: Date
        var end: Date?
    }

    mutating func setEnabled(_ enabled: Bool, at date: Date) {
        if enabled {
            if pauses.last?.end == nil, !pauses.isEmpty { pauses[pauses.count - 1].end = date }
        } else if pauses.isEmpty || pauses.last?.end != nil {
            pauses.append(Pause(start: date))
        }
    }

    mutating func adjust(_ contribution: UsageDay, subtract: Bool = false) {
        let index: Int
        if let existing = days.firstIndex(where: { $0.id == contribution.id }) {
            index = existing
        } else {
            guard !subtract else { return }
            days.append(UsageDay(id: contribution.id))
            index = days.count - 1
        }
        days[index].adjust(contribution, subtract: subtract)
        if days[index].isEmpty { days.remove(at: index) }
    }

    func covers(_ interval: DateInterval, now: Date) -> Bool {
        guard startedAt <= interval.start else { return false }
        return !pauses.contains { $0.start < interval.end && ($0.end ?? now) > interval.start }
    }
}

struct UsageDay: Codable, Equatable, Identifiable {
    /// Civil date at collection time. Travelling never moves an existing total to another day.
    var id: String
    var characters = 0
    var dictations = 0
    var dictationSeconds = 0.0
    var apps: [App] = []
    var agentUses: [String: Int] = [:]

    struct App: Codable, Equatable, Identifiable {
        var id: String
        var name: String
        var characters: Int
    }

    var agentCount: Int { agentUses.values.reduce(0, +) }
    var isEmpty: Bool { dictations == 0 && agentCount == 0 }

    mutating func adjust(_ other: UsageDay, subtract: Bool) {
        let sign = subtract ? -1 : 1
        characters = max(0, characters + sign * other.characters)
        dictations = max(0, dictations + sign * other.dictations)
        dictationSeconds = max(0, dictationSeconds + Double(sign) * other.dictationSeconds)
        for app in other.apps {
            if let index = apps.firstIndex(where: { $0.id == app.id }) {
                apps[index].characters = max(0, apps[index].characters + sign * app.characters)
                if !subtract { apps[index].name = app.name }
            } else if !subtract {
                apps.append(app)
            }
        }
        apps.removeAll { $0.characters == 0 }
        for (purpose, count) in other.agentUses {
            let total = max(0, (agentUses[purpose] ?? 0) + sign * count)
            agentUses[purpose] = total == 0 ? nil : total
        }
    }

    static func characterCount(_ text: String) -> Int {
        text.filter { !$0.isWhitespace }.count
    }

    static func key(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
}

/// The model supplies a fixed purpose, never a classification guessed from its display label.
enum UsagePurpose: String, CaseIterable {
    case draft, rewrite, translate, summarize, answer, text, openLink, search, shortcut

    init(response: AgentResponse) {
        switch response.action {
        case .openURL: self = .openLink
        case .webSearch: self = .search
        case .runShortcut: self = .shortcut
        case .writeText, .answer:
            let purpose = response.purpose.flatMap(Self.init(rawValue:))
            if let purpose, [.draft, .rewrite, .translate, .summarize, .answer].contains(purpose) {
                self = purpose
            } else {
                self = response.action == .answer ? .answer : .text
            }
        }
    }

    var title: String {
        switch self {
        case .draft: localized("Drafting")
        case .rewrite: localized("Rewriting")
        case .translate: localized("Translation")
        case .summarize: localized("Summaries")
        case .answer: localized("Questions & answers")
        case .text: localized("Other text work")
        case .openLink: localized("Opening links")
        case .search: localized("Web searches")
        case .shortcut: localized("Running shortcuts")
        }
    }
}

/// Kept in memory with the undoable write, so clearing statistics invalidates earlier receipts.
struct DictationUsageReceipt {
    let generation: UUID
    let contribution: UsageDay
}
