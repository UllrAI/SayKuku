import Charts
import SwiftUI

struct UsageView: View {
    @Environment(AppState.self) private var appState
    @Binding var period: UsagePeriod
    @Binding var anchor: Date?
    @State private var showsExplanation = false

    private var calendar: Calendar { UsagePeriod.calendar() }
    private var statistics: UsageStatistics { appState.data.usageStatistics }

    var body: some View {
        // Keep an open page on the current civil day, even when no new input arrives.
        TimelineView(.periodic(from: calendar.startOfDay(for: .now), by: 60)) { context in
            content(at: context.date)
        }
    }

    private func content(at now: Date) -> some View {
        let report = UsageReport(statistics: statistics, period: period, anchor: anchor ?? now, now: now)
        return VStack(spacing: 0) {
            ScreenHeader(title: localized("Usage statistics"), subtitle: localized("Your voice input, over time. Saved only on this Mac."))
            KukuPageContent {
                HStack(spacing: KukuSpacing.md) {
                    KukuTabBar(items: UsagePeriod.allCases, selection: $period, title: \.title)
                    Spacer()
                    KukuIconButton(symbol: "info.circle", label: localized("How statistics are counted")) {
                        showsExplanation = true
                    }
                    .popover(isPresented: $showsExplanation) { explanation }
                    KukuIconButton(symbol: "gearshape", label: localized("Statistics settings")) {
                        appState.showSettings(section: .privacy)
                    }
                }
            }
            .padding(.bottom, KukuLayout.tabsBottom)
            KukuDivider(inset: 0)

            KukuPageScroll {
                VStack(alignment: .leading, spacing: KukuLayout.sectionSpacing) {
                    dateNavigation(report, now: now)
                    if !appState.data.isLoaded {
                        if appState.data.loadingFailed {
                            KukuEmptyState(
                                title: localized("Local data can’t be read right now"),
                                symbol: "exclamationmark.triangle",
                                message: localized("To avoid overwriting the file, new changes won’t be saved. Check the file’s permissions or update SayKuku, then reopen it.")
                            ) {
                                Button(localized("History")) { appState.destination = .history }
                                    .buttonStyle(.kukuSecondary)
                            }
                        } else {
                            ProgressView().frame(maxWidth: .infinity)
                                .accessibilityLabel(localized("Loading statistics"))
                        }
                    } else {
                        if !appState.settings.localStatisticsEnabled {
                            Label(localized("Collection is paused. Your previous totals are still here."), systemImage: "pause.circle")
                                .font(.kuku(.subheadline)).foregroundStyle(KukuColor.textSecondary)
                        }
                        summary(report)
                        if let comparison = report.comparison {
                            Text(localized("First \(comparison.days) complete days: \(comparison.change.formatted(.percent.precision(.fractionLength(0)).sign(strategy: .always()).locale(usageLocale))) vs. the previous period", locale: usageLocale))
                                .font(.kuku(.subheadline)).foregroundStyle(KukuColor.textSecondary)
                                .help("\(usageDateRange(comparison.current, calendar: calendar)) · \(usageDateRange(comparison.previous, calendar: calendar))")
                        }
                        let trend = period == .day
                            ? UsageReport(statistics: statistics, period: .week, anchor: anchor ?? now, now: now) : report
                        UsageTrend(points: trend.points, interval: trend.interval, title: period == .day
                            ? (trend.interval.contains(now) ? localized("This week’s input") : localized("Input that week"))
                            : localized("Daily input"))
                        breakdown(report)
                        coverageNote(report)
                    }
                }
            }
        }
    }

    private func dateNavigation(_ report: UsageReport, now: Date) -> some View {
        HStack(spacing: KukuSpacing.sm) {
            VStack(alignment: .leading, spacing: KukuSpacing.xs) {
                Text(periodName(report, now: now))
                    .font(.kuku(.title3)).foregroundStyle(KukuColor.textPrimary)
                Text(usageDateRange(report.interval, calendar: calendar))
                    .font(.kuku(.subheadline)).foregroundStyle(KukuColor.textSecondary)
            }
            Spacer()
            if !report.interval.contains(now) {
                Button(localized("Current period")) { anchor = nil }
                    .buttonStyle(.kukuSecondary)
            }
            KukuIconButton(symbol: "chevron.left", label: localized("Previous period")) { move(-1) }
                .disabled(UsageDay.key(for: report.interval.start, calendar: calendar) <= earliestDay)
            KukuIconButton(symbol: "chevron.right", label: localized("Next period")) { move(1) }
                .disabled(report.interval.end > now)
        }
    }

    private var earliestDay: String {
        let start = UsageDay.key(for: statistics.startedAt, calendar: calendar)
        return min(start, statistics.days.map(\.id).min() ?? start)
    }

    private func move(_ value: Int) {
        guard let date = calendar.date(byAdding: period.component, value: value, to: anchor ?? .now) else { return }
        anchor = calendar.dateInterval(of: period.component, for: date)?.contains(.now) == true ? nil : date
    }

    private func periodName(_ report: UsageReport, now: Date) -> String {
        guard report.interval.contains(now) else { return localized("Selected period") }
        switch period {
        case .day: return localized("Today")
        case .week: return localized("This week")
        case .month: return localized("This month")
        }
    }

    private func summary(_ report: UsageReport) -> some View {
        HStack(alignment: .top, spacing: KukuSpacing.lg) {
            metric(localized("Dictated characters"), value: report.totals.characters.formatted(.number.locale(usageLocale)),
                   detail: localized("Confirmed input"))
            metric(localized("Dictations"), value: report.totals.dictations.formatted(.number.locale(usageLocale)),
                   detail: localized("\(report.activeDays) active days", locale: usageLocale))
            metric(localized("Speaking time"), value: usageDuration(report.totals.dictationSeconds),
                   detail: localized("For confirmed dictations"))
        }
        .padding(KukuLayout.cardPadding)
        .kukuSurface()
    }

    private func metric(_ title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: KukuSpacing.sm) {
            Text(title).font(.kuku(.subheadline)).foregroundStyle(KukuColor.textSecondary)
            Text(value).font(.kuku(.largeTitle)).monospacedDigit().foregroundStyle(KukuColor.textPrimary)
                .contentTransition(.numericText())
            Text(detail).font(.kuku(.caption)).foregroundStyle(KukuColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func breakdown(_ report: UsageReport) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: KukuSpacing.lg) {
                apps(report).frame(minWidth: KukuLayout.usageBreakdownMinWidth)
                agent(report).frame(minWidth: KukuLayout.usageBreakdownMinWidth)
            }
            VStack(alignment: .leading, spacing: KukuLayout.sectionSpacing) {
                apps(report)
                agent(report)
            }
        }
    }

    private func apps(_ report: UsageReport) -> some View {
        KukuGroup(localized("Where you dictate")) {
            if report.topApps.isEmpty {
                quietEmpty(localized("No confirmed dictations in this period."))
            } else {
                VStack(alignment: .leading, spacing: KukuSpacing.lg) {
                    ForEach(report.topApps) { app in
                        VStack(alignment: .leading, spacing: KukuSpacing.xs) {
                            HStack(spacing: KukuSpacing.sm) {
                                Text(app.name.isEmpty ? localized("Unspecified app") : app.name)
                                    .lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: KukuSpacing.sm)
                                Text(localized("\(app.characters) characters", locale: usageLocale)).monospacedDigit()
                                    .foregroundStyle(KukuColor.textSecondary)
                            }
                            .font(.kuku(.subheadline))
                            GeometryReader { geometry in
                                Capsule().fill(KukuColor.fill)
                                Capsule().fill(KukuColor.textSecondary)
                                    .frame(width: geometry.size.width * Double(app.characters) / Double(max(1, report.totals.characters)))
                            }
                            .frame(height: KukuSpacing.xs)
                            .accessibilityHidden(true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(KukuLayout.cardPadding)
            }
        }
    }

    private func agent(_ report: UsageReport) -> some View {
        KukuGroup(localized("Voice Agent")) {
            VStack(alignment: .leading, spacing: KukuSpacing.md) {
                Text(localized("\(report.totals.agentCount) completed uses", locale: usageLocale))
                    .font(.kuku(.headline)).monospacedDigit().foregroundStyle(KukuColor.textPrimary)
                Text(localized("Answers and completed tasks are counted separately from dictation."))
                    .font(.kuku(.subheadline)).foregroundStyle(KukuColor.textSecondary)
                if report.totals.agentCount > 0 {
                    DisclosureGroup(localized("View uses")) {
                        VStack(spacing: KukuSpacing.md) {
                            ForEach(report.purposes, id: \.purpose) { item in
                                HStack {
                                    Text(item.purpose.title)
                                    Spacer()
                                    Text(localized("\(item.count) uses", locale: usageLocale)).monospacedDigit()
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                        .padding(.top, KukuSpacing.md)
                    }
                    .font(.kuku(.subheadline)).tint(KukuColor.textSecondary)
                }
            }
            .padding(KukuLayout.cardPadding)
        }
    }

    private func quietEmpty(_ text: String) -> some View {
        Text(text).font(.kuku(.subheadline)).foregroundStyle(KukuColor.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading).padding(KukuLayout.cardPadding)
    }

    private func coverageNote(_ report: UsageReport) -> some View {
        VStack(alignment: .leading, spacing: KukuSpacing.xs) {
            Text(localized("Collected since \(statistics.startedAt.formatted(.dateTime.year().month().day().locale(usageLocale)))."))
            if report.hasIncompleteCoverage {
                Text(localized("This period includes time before collection started or while it was paused. Totals may be partial."))
            }
            Text(localized("Deleting history keeps these totals. Clear them separately in Settings › Privacy."))
        }
        .font(.kuku(.caption)).foregroundStyle(KukuColor.textSecondary)
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: KukuSpacing.md) {
            Text(localized("How statistics are counted")).font(.kuku(.headline))
            Text(localized("Dictation counts only text whose insertion SayKuku could verify. Copies, unverified pastes, retries in History, and cancelled or failed attempts are excluded. A confirmed Undo removes that dictation’s characters, count and speaking time."))
            Text(localized("Each non-whitespace character counts once, including letters, numbers, punctuation and emoji. Voice Agent output is excluded from dictated characters."))
            Text(localized("Days follow your local time zone; weeks follow your regional week-start setting. Comparisons use the same number of complete days and are hidden when collection was incomplete."))
            Text(localized("Only daily counts, speaking time, app names and task categories are saved locally. Turning off “Current app” stops saving app names for new statistics. No text or audio is stored in statistics."))
        }
        .font(.kuku(.subheadline)).foregroundStyle(KukuColor.textPrimary)
        .padding(KukuSpacing.xl).frame(width: KukuLayout.usageExplanationWidth)
    }
}

private struct UsageTrend: View {
    let points: [UsageReport.Point]
    let interval: DateInterval
    let title: String
    @State private var selectedDate: Date?

    private var selectedPoint: UsageReport.Point? {
        guard let selectedDate else { return nil }
        return points.first { UsagePeriod.calendar().isDate($0.date, inSameDayAs: selectedDate) }
    }

    var body: some View {
        KukuGroup(title) {
            VStack(alignment: .leading, spacing: KukuSpacing.md) {
                HStack {
                    if let point = selectedPoint {
                        Text(point.date.formatted(.dateTime.month().day().locale(usageLocale)))
                        if point.isFuture {
                            Text(localized("Not yet"))
                        } else {
                            Text(localized("\(point.totals.characters) characters", locale: usageLocale))
                            Text(localized("\(point.totals.dictations) dictations", locale: usageLocale))
                            if !point.isCovered { Text(localized("Partial data")) }
                        }
                    } else {
                        Text(localized("Point to a day to see its input."))
                    }
                }
                .font(.kuku(.caption)).foregroundStyle(KukuColor.textSecondary)
                .frame(minHeight: KukuLayout.controlHeightSmall, alignment: .leading)

                Chart(points) { point in
                    // Unknown and future days keep their place without becoming zero-valued data.
                    if !point.isFuture && (point.isCovered || point.totals.dictations > 0) {
                        BarMark(x: .value(localized("Day"), point.date, unit: .day),
                                y: .value(localized("Dictated characters"), point.totals.characters))
                            .foregroundStyle(KukuColor.textSecondary)
                            .cornerRadius(KukuSpacing.xxs)
                            .accessibilityLabel(point.date.formatted(.dateTime.month().day().locale(usageLocale)))
                            .accessibilityValue(inputDescription(point))
                    }
                    if let selectedPoint, selectedPoint.id == point.id {
                        RuleMark(x: .value(localized("Day"), point.date, unit: .day))
                            .foregroundStyle(KukuColor.borderStrong)
                            .accessibilityHidden(true)
                    }
                }
                .chartXSelection(value: $selectedDate)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Color.clear.contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    guard let frame = proxy.plotFrame else { return }
                                    selectedDate = proxy.value(atX: location.x - geometry[frame].minX, as: Date.self)
                                case .ended: selectedDate = nil
                                }
                            }
                    }
                }
                .chartYScale(domain: 0...max(10, points.map(\.totals.characters).max() ?? 0))
                .chartXScale(domain: interval.start...interval.end,
                             range: .plotDimension(startPadding: KukuSpacing.md, endPadding: KukuSpacing.md))
                .chartXAxis {
                    AxisMarks(values: points.enumerated().filter { $0.offset % (points.count > 7 ? 5 : 1) == 0 }.map { $0.element.date }) { _ in
                        AxisValueLabel(format: .dateTime.day().locale(usageLocale), anchor: .top)
                    }
                }
                .chartYAxis {
                    if points.contains(where: { $0.totals.dictations > 0 }) {
                        AxisMarks(position: .leading) { _ in
                            AxisGridLine().foregroundStyle(KukuColor.separator)
                            AxisValueLabel(format: FloatingPointFormatStyle<Double>.number.locale(usageLocale), anchor: .trailing)
                        }
                    }
                }
                .environment(\.locale, usageLocale)
                .environment(\.calendar, UsagePeriod.calendar())
                .frame(height: KukuLayout.usageChartHeight)
                .overlay {
                    if points.allSatisfy({ $0.totals.dictations == 0 }) {
                        Text(localized("Your confirmed dictations will appear here."))
                            .font(.kuku(.subheadline)).foregroundStyle(KukuColor.textSecondary)
                            .padding(KukuSpacing.sm).background(KukuColor.surface)
                            .allowsHitTesting(false)
                    }
                }
            }
            .padding(KukuLayout.cardPadding)
        }
        .onChange(of: points.map(\.id)) { selectedDate = nil }
    }

    private func inputDescription(_ point: UsageReport.Point) -> String {
        var parts = [localized("\(point.totals.characters) characters", locale: usageLocale),
                     localized("\(point.totals.dictations) dictations", locale: usageLocale)]
        if !point.isCovered { parts.append(localized("Partial data")) }
        return parts.joined(separator: " · ")
    }
}

private var usageLocale: Locale {
    let current = Locale.autoupdatingCurrent
    return current.language.languageCode == interfaceLanguage.languageCode
        ? current : Locale(identifier: interfaceLanguage.minimalIdentifier)
}

private func usageDateRange(_ interval: DateInterval, calendar: Calendar) -> String {
    let last = calendar.date(byAdding: .day, value: -1, to: interval.end)!
    let format = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: usageLocale)
    if calendar.isDate(interval.start, inSameDayAs: last) { return interval.start.formatted(format) }
    return "\(interval.start.formatted(format)) – \(last.formatted(format))"
}

private func usageDuration(_ seconds: Double) -> String {
    let duration = Duration.seconds(seconds)
    let units: Set<Duration.UnitsFormatStyle.Unit> = seconds < 60 ? [.seconds] : [.hours, .minutes]
    return duration.formatted(.units(allowed: units, width: .abbreviated).locale(usageLocale))
}
