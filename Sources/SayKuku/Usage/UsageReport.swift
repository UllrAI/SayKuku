import Foundation

enum UsagePeriod: CaseIterable, Hashable {
    case day, week, month

    var title: String {
        switch self {
        case .day: localized("Day")
        case .week: localized("Week")
        case .month: localized("Month")
        }
    }

    var component: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
    }

    /// Gregorian civil dates, with the user's time zone and week-start preference.
    static func calendar(from regional: Calendar = .autoupdatingCurrent) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = regional.timeZone
        calendar.firstWeekday = regional.firstWeekday
        calendar.minimumDaysInFirstWeek = regional.minimumDaysInFirstWeek
        return calendar
    }
}

struct UsageReport {
    struct Point: Identifiable {
        let date: Date
        let totals: UsageDay
        let isCovered: Bool
        let isFuture: Bool
        var id: Date { date }
    }

    struct Comparison: Equatable {
        let change: Double
        let days: Int
        let current: DateInterval
        let previous: DateInterval
    }

    let interval: DateInterval
    let points: [Point]
    let totals: UsageDay
    let activeDays: Int
    let hasIncompleteCoverage: Bool
    let comparison: Comparison?

    init(statistics: UsageStatistics, period: UsagePeriod, anchor: Date, now: Date = .now,
         calendar: Calendar = UsagePeriod.calendar()) {
        let interval = calendar.dateInterval(of: period.component, for: anchor)!
        self.interval = interval
        let end = min(interval.end, now)
        let daysByKey = Dictionary(statistics.days.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var points: [Point] = []
        var date = interval.start
        var total = UsageDay(id: "total")
        while date < interval.end {
            let next = calendar.date(byAdding: .day, value: 1, to: date)!
            let key = UsageDay.key(for: date, calendar: calendar)
            let day = date <= now ? daysByKey[key] ?? UsageDay(id: key) : UsageDay(id: key)
            let covered = date < end && statistics.covers(DateInterval(start: date, end: min(next, end)), now: now)
            points.append(Point(date: date, totals: day, isCovered: covered, isFuture: date > now))
            if date <= now { total.adjust(day, subtract: false) }
            date = next
        }
        self.points = points
        totals = total
        activeDays = points.filter { $0.totals.dictations > 0 }.count
        hasIncompleteCoverage = end > interval.start
            && !statistics.covers(DateInterval(start: interval.start, end: end), now: now)

        // Daily totals cannot compare part of today with part of an earlier day. Compare complete
        // days only, using the same number in both periods, and hide comparisons with coverage gaps.
        let completedEnd = min(interval.end, calendar.startOfDay(for: now))
        let completedDays = calendar.dateComponents([.day], from: interval.start, to: completedEnd).day ?? 0
        let previousAnchor = calendar.date(byAdding: period.component, value: -1, to: interval.start)!
        let previous = calendar.dateInterval(of: period.component, for: previousAnchor)!
        let previousDays = calendar.dateComponents([.day], from: previous.start, to: previous.end).day ?? 0
        let count = min(completedDays, previousDays)
        if count > 0 {
            let currentRange = DateInterval(
                start: interval.start, end: calendar.date(byAdding: .day, value: count, to: interval.start)!
            )
            let previousRange = DateInterval(
                start: previous.start, end: calendar.date(byAdding: .day, value: count, to: previous.start)!
            )
            let currentCharacters = Self.characters(in: currentRange, days: daysByKey, calendar: calendar)
            let previousCharacters = Self.characters(in: previousRange, days: daysByKey, calendar: calendar)
            if previousCharacters > 0, statistics.covers(currentRange, now: now), statistics.covers(previousRange, now: now) {
                comparison = Comparison(
                    change: Double(currentCharacters - previousCharacters) / Double(previousCharacters),
                    days: count, current: currentRange, previous: previousRange
                )
            } else {
                comparison = nil
            }
        } else {
            comparison = nil
        }
    }

    var topApps: [UsageDay.App] {
        let sorted = totals.apps.sorted {
            if $0.characters != $1.characters { return $0.characters > $1.characters }
            return $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name
        }
        guard sorted.count > 5 else { return sorted }
        return Array(sorted.prefix(5)) + [UsageDay.App(
            id: "other", name: localized("Other apps"), characters: sorted.dropFirst(5).reduce(0) { $0 + $1.characters }
        )]
    }

    var purposes: [(purpose: UsagePurpose, count: Int)] {
        UsagePurpose.allCases.compactMap { purpose in
            guard let count = totals.agentUses[purpose.rawValue], count > 0 else { return nil }
            return (purpose, count)
        }.sorted { $0.count == $1.count ? $0.purpose.rawValue < $1.purpose.rawValue : $0.count > $1.count }
    }

    private static func characters(in interval: DateInterval, days: [String: UsageDay], calendar: Calendar) -> Int {
        var result = 0
        var date = interval.start
        while date < interval.end {
            result += days[UsageDay.key(for: date, calendar: calendar)]?.characters ?? 0
            date = calendar.date(byAdding: .day, value: 1, to: date)!
        }
        return result
    }
}
