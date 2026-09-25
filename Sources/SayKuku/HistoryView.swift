import AVFoundation
import SwiftUI

struct HistoryView: View {
    @Environment(AppState.self) private var appState
    @Binding var filter: HistoryFilter
    @Binding var search: String
    @State private var selection: HistoryEntry.ID?
    @State private var pendingDeletion: HistoryEntry?
    /// One recording plays at a time. It lives here, not in the row, because the list
    /// removes rows as they scroll out of view.
    @State private var playback: Playback?
    @FocusState private var searchFocused: Bool
    @FocusState private var listFocused: Bool

    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var filteredEntries: [HistoryEntry] {
        let text = query
        return appState.historyEntries.filter { entry in
            (filter == .all || entry.mode.filter == filter) && (text.isEmpty || Self.entry(entry, matches: text))
        }
    }

    private static func entry(_ entry: HistoryEntry, matches text: String) -> Bool {
        entry.input.localizedCaseInsensitiveContains(text)
            || entry.output.localizedCaseInsensitiveContains(text)
            || entry.app.localizedCaseInsensitiveContains(text)
    }

    var body: some View {
        let entries = filteredEntries

        VStack(spacing: 0) {
            ScreenHeader(
                title: localized("History"),
                subtitle: retentionSubtitle
            ) {
                if !appState.historyEntries.isEmpty {
                    KukuSearchField(
                        prompt: localized("Search text or apps"),
                        clearLabel: localized("Clear search"),
                        text: $search,
                        focus: $searchFocused,
                        onExit: { listFocused = true }
                    )
                    .focusedSceneValue(\.searchFieldFocus, $searchFocused)
                }
            }

            KukuPageTabs(
                items: HistoryFilter.allCases,
                selection: $filter,
                title: { $0.title(appState) }
            )

            KukuDivider(inset: 0)

            if entries.isEmpty {
                KukuPageScroll {
                    VStack(alignment: .leading, spacing: 0) {
                        notices
                        emptyState
                    }
                }
            } else {
                entryList(entries)
            }
        }
        .onDisappear(perform: stopPlayback)
        .confirmationDialog(
            localized("Delete this starred item?"),
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { entry in
            Button(localized("Delete"), role: .destructive) { delete(entry) }
            Button(localized("Cancel"), role: .cancel) { }
        } message: { entry in
            Text(entry.hasAudio
                 ? localized("Its recording will be deleted too. This can’t be undone.")
                 : localized("This can’t be undone."))
        }
    }

    @ViewBuilder
    private var notices: some View {
        if let issue = appState.localDataIssue {
            let copy = issueCopy(issue)
            HistoryNotice(
                symbol: "exclamationmark.triangle",
                title: copy.title,
                message: copy.message,
                fileURL: issue.fileURL
            ) { appState.dismissLocalDataIssue() }
        }
        if let legacyURL = appState.legacyDataURL {
            HistoryNotice(
                symbol: "archivebox",
                title: localized("Encrypted history from an earlier version wasn’t carried over"),
                message: localized(
                    "History, Knowledge, and Memory saved by an earlier encrypted version can’t be opened here. SayKuku won’t migrate or delete these files. They’re still on this Mac for you to keep or remove."
                ),
                fileURL: legacyURL
            ) { appState.dismissLegacyDataNotice() }
        }
    }

    private var retentionSubtitle: String {
        switch appState.historyRetention {
        case .off:
            localized("New items aren’t being saved. Existing ones stay until you clear them.")
        case .forever:
            localized("History is kept until you delete it.")
        default:
            appState.text(
                "保留 \(appState.historyRetention.chineseTitle)，星标记录不会自动删除。",
                "Kept for \(appState.historyRetention.englishTitle). Starred items are never deleted automatically."
            )
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if appState.historyEntries.isEmpty, appState.historyRetention == .off {
            KukuEmptyState(
                title: localized("History is off"),
                symbol: "pause.circle",
                message: localized("Choose a retention period in Settings › History to start keeping history again.")
            ) {
                Button(localized("Open Settings")) {
                    appState.showSettings(section: .history)
                }
                .buttonStyle(.kukuSecondary)
            }
        } else if appState.historyEntries.isEmpty {
            KukuEmptyState(
                title: localized("No history yet"),
                symbol: "waveform",
                message: localized("Press Fn and start talking. Your history shows up here.")
            )
        } else if !query.isEmpty {
            KukuEmptyState(
                title: localized("No matching history"),
                symbol: "magnifyingglass",
                message: localized("Try a different search.")
            )
        } else {
            KukuEmptyState(
                title: localized("No history in this category"),
                symbol: "line.3.horizontal.decrease.circle",
                message: localized("Switch categories, or clear the filter to see everything.")
            ) {
                Button(localized("Clear Filter")) { filter = .all }
                    .buttonStyle(.kukuSecondary)
            }
        }
    }

    private func entryList(_ entries: [HistoryEntry]) -> some View {
        let days = daySections(entries)
        return KukuPageContent {
            List(selection: $selection) {
                Group { notices }.kukuListRow()

                ForEach(days) { day in
                    // The day's String id doesn't match the UUID selection, so headers can't be selected.
                    Text(day.label)
                        .font(.kuku(.caption, weight: .semibold))
                        .foregroundStyle(KukuColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, day.id == days.first?.id ? 0 : KukuSpacing.xxl)
                        .padding(.bottom, KukuSpacing.sm)
                        .kukuListRow()

                    ForEach(day.entries) { entry in
                        VStack(spacing: 0) {
                            HistoryRow(
                                entry: entry,
                                isSelected: selection == entry.id,
                                isPlaying: playback?.entryID == entry.id,
                                onTogglePlayback: { togglePlayback(entry) },
                                onDelete: { requestDelete(entry) }
                            )
                            // Starts at the text column: row padding, icon tile, then the tile's spacing.
                            KukuDivider(inset: KukuLayout.iconTile + KukuSpacing.md * 2)
                        }
                        .tag(entry.id)
                        .kukuListRow()
                    }
                }
            }
            .kukuList()
            .contentMargins(.top, KukuLayout.contentTop, for: .scrollContent)
            .contentMargins(.bottom, KukuLayout.contentBottom, for: .scrollContent)
            .focused($listFocused)
            .onDeleteCommand {
                if let entry = selectedEntry(in: entries) { requestDelete(entry) }
            }
            .onCopyCommand {
                guard let entry = selectedEntry(in: entries) else { return [] }
                // The result, or what was said when there is no result.
                let text = entry.hasCopyableOutput ? entry.output : entry.input
                return text.isEmpty ? [] : [NSItemProvider(object: text as NSString)]
            }
        }
    }

    private func selectedEntry(in entries: [HistoryEntry]) -> HistoryEntry? {
        entries.first { $0.id == selection }
    }

    /// Consecutive entries grouped under one day label, in list order.
    private func daySections(_ entries: [HistoryEntry]) -> [HistoryDay] {
        var days: [HistoryDay] = []
        for entry in entries {
            let label = dayLabel(for: entry)
            if days.last?.label == label {
                days[days.count - 1].entries.append(entry)
            } else {
                days.append(HistoryDay(label: label, entries: [entry]))
            }
        }
        return days
    }

    /// Starred items are meant to be kept, so deleting one asks first.
    private func requestDelete(_ entry: HistoryEntry) {
        if entry.isStarred { pendingDeletion = entry } else { delete(entry) }
    }

    private func delete(_ entry: HistoryEntry) {
        if playback?.entryID == entry.id { stopPlayback() }
        if selection == entry.id { selection = filteredEntries.selectionAfterRemoving(entry.id) }
        withAnimation(Motion.snappy) { appState.deleteHistoryEntry(entry.id) }
        appState.showToast(localized("Deleted"), symbol: "trash")
    }

    private func stopPlayback() {
        playback?.player?.stop()
        withAnimation(Motion.snappy) { playback = nil }
    }

    /// Plays `entry`, stopping whatever was playing; tapping the playing entry again stops it.
    private func togglePlayback(_ entry: HistoryEntry) {
        let wasPlaying = playback?.entryID == entry.id
        stopPlayback()
        guard !wasPlaying else { return }
        withAnimation(Motion.snappy) { playback = Playback(entryID: entry.id) }
        Task {
            do {
                let data = try await appState.playAudio(for: entry)
                // Stopped, switched or left the page while loading.
                guard playback?.entryID == entry.id, playback?.player == nil else { return }
                let player = try AVAudioPlayer(data: data)
                player.prepareToPlay()
                player.play()
                playback?.player = player
                try? await Task.sleep(for: .seconds(max(entry.durationSeconds, 0.2)))
                guard playback?.player === player else { return }
                withAnimation(Motion.snappy) { playback = nil }
            } catch {
                if playback?.entryID == entry.id { withAnimation(Motion.snappy) { playback = nil } }
                appState.showToast(
                    localized("Couldn’t play this recording. The file may have been moved or deleted."),
                    symbol: "exclamationmark.triangle.fill"
                )
            }
        }
    }

    private func dayLabel(for entry: HistoryEntry) -> String {
        if Calendar.current.isDateInToday(entry.createdAt) { return localized("Today") }
        if Calendar.current.isDateInYesterday(entry.createdAt) { return localized("Yesterday") }
        let locale = historyLocale(chinese: appState.usesChineseUI)
        return entry.createdAt.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale))
    }

    private func issueCopy(_ issue: LocalStore.DataIssue) -> (title: String, message: String) {
        switch issue {
        case .skippedRecords(let count, let backup):
            return (
                title: appState.text(
                    "有 \(count) 条本机记录无法读取，已跳过",
                    count == 1 ? "1 saved item couldn’t be read and was skipped" : "\(count) saved items couldn’t be read and were skipped"
                ),
                message: localized(
                    "Everything else loaded normally. The original file was backed up as \(backup.lastPathComponent)."
                )
            )
        case .movedAside(let backup):
            return (
                title: localized("Local data couldn’t be read, so SayKuku started fresh"),
                message: localized("The original file wasn’t overwritten. It’s saved as \(backup.lastPathComponent).")
            )
        case .readOnly:
            return (
                title: localized("Local data can’t be read right now"),
                message: localized(
                    "To avoid overwriting the file, new changes won’t be saved. Check the file’s permissions or update SayKuku, then reopen it."
                )
            )
        }
    }
}

private struct Playback {
    let entryID: HistoryEntry.ID
    /// `nil` while the recording loads.
    var player: AVAudioPlayer?
}

private struct HistoryDay: Identifiable {
    let label: String
    var entries: [HistoryEntry]
    var id: String { label }
}

private struct HistoryNotice: View {
    @Environment(AppState.self) private var appState
    let symbol: String
    let title: String
    let message: String
    let fileURL: URL
    let onDismiss: @MainActor () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: KukuSpacing.md) {
            Image(systemName: symbol)
                .font(.kukuIcon(.regular, weight: .semibold))
                .foregroundStyle(KukuStatusTone.warning.iconColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: KukuSpacing.xs) {
                Text(title)
                    .font(.kuku(.headline))
                    .foregroundStyle(KukuColor.textPrimary)
                Text(message)
                    .font(.kuku(.subheadline))
                    .foregroundStyle(KukuColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(localized("Show in Finder")) {
                    appState.revealInFinder(fileURL)
                }
                .buttonStyle(.kuku(.secondary, size: .small))
                .padding(.top, KukuSpacing.xs)
            }

            Spacer(minLength: KukuSpacing.sm)

            KukuIconButton(symbol: "xmark", label: localized("Close"), action: onDismiss)
        }
        .kukuCard()
        .padding(.bottom, KukuLayout.listSpacing)
    }
}

private struct HistoryRow: View {
    @Environment(AppState.self) private var appState
    let entry: HistoryEntry
    let isSelected: Bool
    let isPlaying: Bool
    let onTogglePlayback: @MainActor () -> Void
    /// The page owns deletion so Delete in the list and the row's buttons share one path.
    let onDelete: @MainActor () -> Void
    @State private var isOutputExpanded = false
    @State private var hovering = false

    private var locale: Locale { historyLocale(chinese: appState.usesChineseUI) }

    var body: some View {
        HStack(alignment: .top, spacing: KukuSpacing.md) {
            KukuIconTile(symbol: entry.mode.symbol)

            VStack(alignment: .leading, spacing: KukuSpacing.sm) {
                HStack(spacing: KukuSpacing.iconText) {
                    Text(entry.mode.title(appState))
                        .font(.kuku(.caption, weight: .semibold))
                    Text("·")
                    Text(entry.app)
                    Text("·")
                    Text(entry.createdAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale)))
                }
                .font(.kuku(.caption))
                .foregroundStyle(KukuColor.textSecondary)

                VStack(alignment: .leading, spacing: KukuSpacing.iconText) {
                    historyLine(label: localized("Spoken")) { inputContent }
                    historyLine(label: localized("Result")) { outputContent }
                }
            }

            Spacer(minLength: KukuSpacing.lg)

            HStack(spacing: 0) {
                if hovering {
                    KukuIconButton(
                        symbol: "trash",
                        label: localized("Delete this item"),
                        action: onDelete
                    )
                }

                KukuIconButton(
                    symbol: entry.isStarred ? "star.fill" : "star",
                    label: entry.isStarred ? localized("Remove star") : localized("Star"),
                    help: entry.isStarred ? nil : localized("Star and keep forever"),
                    tint: starTint,
                    action: toggleStar
                )
            }
        }
        .padding(KukuSpacing.md)
        // Rows grow with expanded output instead of taking a height from the list.
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        .background(rowFill, in: RoundedRectangle(cornerRadius: KukuLayout.radiusMedium, style: .continuous))
        .onHover { hovering = $0 }
        .animation(Motion.snappy, value: hovering)
        .animation(Motion.snappy, value: isSelected)
        .contextMenu {
            if entry.hasCopyableOutput {
                Button(localized("Copy Result")) { appState.copyHistoryOutput(entry.output) }
            }
            if entry.hasAudio {
                Button(playbackTitle(titleCase: true), action: onTogglePlayback)
            }
            Button(entry.isStarred ? localized("Remove Star") : localized("Star")) {
                toggleStar()
            }
            Divider()
            Button(
                entry.isStarred ? localized("Delete…") : localized("Delete"),
                role: .destructive,
                action: onDelete
            )
        }
    }

    /// Same fills as `kukuInteractiveSurface`: selection wins over hover.
    private var rowFill: Color {
        if isSelected { return KukuColor.selectedFill }
        return hovering ? KukuColor.rowHover : .clear
    }

    /// Stars are neutral: a star marks an item to keep, not a status.
    private var starTint: Color {
        if entry.isStarred { return KukuColor.textPrimary }
        return hovering ? KukuColor.textSecondary : KukuColor.textTertiary
    }

    private func playbackTitle(titleCase: Bool) -> String {
        isPlaying
            ? appState.text("停止播放", titleCase ? "Stop Playback" : "Stop playback")
            : appState.text("播放录音", titleCase ? "Play Recording" : "Play recording")
    }

    @ViewBuilder
    private var inputContent: some View {
        HStack(spacing: KukuSpacing.sm) {
            if entry.hasAudio {
                Button(action: onTogglePlayback) {
                    HStack(spacing: KukuSpacing.iconText) {
                        if isPlaying {
                            // Compact playback waveform sized to fit the small capsule.
                            Waveform(color: KukuColor.textSecondary, barCount: 5, height: 12)
                                .frame(width: 20)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.kukuIcon(.mini, weight: .semibold))
                        }
                        Text(Self.durationLabel(entry.durationSeconds))
                            .font(.kuku(.caption, weight: .semibold))
                            .monospacedDigit()
                    }
                    .foregroundStyle(KukuColor.textSecondary)
                    .padding(.horizontal, KukuSpacing.sm)
                    .frame(minHeight: KukuLayout.controlHeightSmall)
                    .background(KukuColor.fill, in: Capsule())
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel(playbackTitle(titleCase: false))
                .accessibilityValue(Self.durationLabel(entry.durationSeconds))
                .help(playbackTitle(titleCase: false))
            } else {
                Image(systemName: entry.status == .processing && appState.storeVoiceAudio ? "ellipsis" : "waveform.slash")
                    .font(.kukuIcon(.small))
                    .foregroundStyle(KukuColor.textSecondary)
                Text(entry.status == .processing && appState.storeVoiceAudio
                     ? localized("Saving recording…")
                     : localized("No recording"))
                    .font(.kuku(.subheadline))
                    .foregroundStyle(KukuColor.textSecondary)
            }

            if entry.mode == .agent, !entry.input.isEmpty {
                Text(entry.input)
                    .font(.kuku(.callout))
                    .foregroundStyle(KukuColor.textSecondary)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private var outputContent: some View {
        switch entry.status {
        case .processing:
            HStack(spacing: KukuSpacing.iconText) {
                ProgressView().controlSize(.mini)
                Text(entry.mode == .dictation
                     ? localized("Transcribing…")
                     : localized("Processing…"))
            }
            .foregroundStyle(KukuColor.textSecondary)
        case .failed:
            VStack(alignment: .leading, spacing: KukuSpacing.sm) {
                KukuStatusLabel(
                    text: entry.errorMessage ?? localized("Processing failed"),
                    tone: .danger,
                    font: .kuku(.body)
                )
                retryButton
            }
        case .cancelled:
            VStack(alignment: .leading, spacing: KukuSpacing.sm) {
                Label(localized("Cancelled"), systemImage: "xmark.circle")
                    .foregroundStyle(KukuColor.textSecondary)
                retryButton
            }
        case .completed:
            VStack(alignment: .leading, spacing: KukuSpacing.iconText) {
                Text(entry.output)
                    .foregroundStyle(KukuColor.textPrimary)
                    .lineSpacing(KukuTypography.paragraphSpacing)
                    .lineLimit(shouldCollapseOutput && !isOutputExpanded ? 4 : nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                if entry.hasCopyableOutput {
                    Button {
                        appState.copyHistoryOutput(entry.output)
                    } label: {
                        Label(localized("Copy Result"), systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.kuku(.plain, size: .small))
                }

                if shouldCollapseOutput {
                    Button {
                        withAnimation(Motion.snappy) { isOutputExpanded.toggle() }
                    } label: {
                        Label(
                            isOutputExpanded
                                ? localized("Show Less")
                                : localized("Show More"),
                            systemImage: isOutputExpanded ? "chevron.up" : "chevron.down"
                        )
                    }
                    .buttonStyle(.kuku(.plain, size: .small))
                }
            }
        }
    }

    @ViewBuilder
    private var retryButton: some View {
        if entry.canRetryTranscription {
            Button(localized("Retry Transcription")) {
                Task { await appState.retryDictation(entry.id) }
            }
            .buttonStyle(.kuku(.secondary, size: .small))
        }
    }

    private var shouldCollapseOutput: Bool {
        entry.output.count > 180
            || entry.output.filter { $0.isNewline }.count >= 3
    }

    private func historyLine<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: KukuSpacing.sm) {
            Text(label)
                .font(.kuku(.caption, weight: .semibold))
                .foregroundStyle(KukuColor.textSecondary)
                .lineLimit(1)
                // Fixed label column so every entry's content starts at the same edge.
                .frame(width: 40, alignment: .leading)
            content()
                .font(.kuku(.body))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggleStar() {
        withAnimation(Motion.spring) { appState.toggleHistoryStar(entry.id) }
    }

    /// Formats a recording length as m:ss, e.g. 0:04 or 1:25.
    private static func durationLabel(_ seconds: Double) -> String {
        guard seconds > 0 else { return "—" }
        let total = max(1, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private extension HistoryEntry {
    var hasCopyableOutput: Bool { status == .completed && !output.isEmpty }
}

/// Uses the app's UI language for dates, keeping the user's regional formats when the languages match.
private func historyLocale(chinese: Bool) -> Locale {
    let current = Locale.autoupdatingCurrent
    let currentIsChinese = current.language.languageCode == Locale.LanguageCode.chinese
    return chinese == currentIsChinese ? current : Locale(identifier: chinese ? "zh-Hans" : "en")
}

enum HistoryFilter: String, CaseIterable, Identifiable {
    case all, dictation, agent
    var id: String { rawValue }
    @MainActor func title(_ appState: AppState) -> String {
        switch self {
        case .all: localized("All")
        case .dictation: appState.voiceInputTitle
        case .agent: appState.voiceAgentTitle
        }
    }
}
