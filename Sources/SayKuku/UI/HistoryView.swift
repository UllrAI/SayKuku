import AVFoundation
import SwiftUI

struct HistoryView: View {
    @Environment(AppState.self) private var appState
    @Binding var filter: HistoryFilter
    @Binding var search: String
    @State private var pendingDeletion: HistoryEntry?
    /// One recording plays at a time. It lives here, not in the row, because the list
    /// removes rows as they scroll out of view.
    @State private var playback: Playback?
    @FocusState private var searchFocused: Bool

    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var filteredEntries: [HistoryEntry] {
        let text = query
        return appState.data.historyEntries.filter { entry in
            entry.id != appState.data.pendingHistoryDeletion?.id
                && (filter == .all || entry.mode.filter == filter)
                && (text.isEmpty || Self.entry(entry, matches: text))
        }
    }

    private var visibleEntries: [HistoryEntry] {
        appState.data.historyEntries.filter { $0.id != appState.data.pendingHistoryDeletion?.id }
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
                if !visibleEntries.isEmpty {
                    KukuSearchField(
                        prompt: localized("Search text or apps"),
                        clearLabel: localized("Clear search"),
                        text: $search,
                        focus: $searchFocused,
                        onExit: { searchFocused = false }
                    )
                    .focusedSceneValue(\.searchFieldFocus, $searchFocused)
                }
            }

            KukuPageTabs(
                items: HistoryFilter.allCases,
                selection: $filter,
                title: { $0.title }
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
        .overlay(alignment: .bottom) {
            if appState.data.pendingHistoryDeletion != nil {
                undoDeletionBar
                    .padding(.bottom, KukuSpacing.xxl)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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

    private var undoDeletionBar: some View {
        HStack(spacing: KukuSpacing.lg) {
            Label(localized("Deleted"), systemImage: "trash")
                .font(.kuku(.callout, weight: .semibold))
            Button(localized("Undo")) {
                withAnimation(Motion.snappy) { appState.data.undoHistoryDeletion() }
            }
            .buttonStyle(.plain)
            .font(.kuku(.callout, weight: .semibold))
            .underline()
            .accessibilityHint(localized("Restore the deleted history item"))
        }
        .foregroundStyle(KukuColor.toastText)
        .padding(.horizontal, KukuSpacing.lg)
        .padding(.vertical, KukuSpacing.sm)
        .frame(minHeight: KukuLayout.controlHeight)
        .background(KukuColor.toastSurface, in: RoundedRectangle(cornerRadius: KukuLayout.radiusLarge))
        .kukuShadow(.floating)
        .onAppear {
            AccessibilityNotification.Announcement(localized("Deleted. Undo is available.")).post()
        }
    }

    @ViewBuilder
    private var notices: some View {
        if let issue = appState.data.localDataIssue {
            let copy = issueCopy(issue)
            HistoryNotice(
                symbol: "exclamationmark.triangle",
                title: copy.title,
                message: copy.message,
                fileURL: issue.fileURL
            ) { appState.data.dismissLocalDataIssue() }
        }
        if let legacyURL = appState.data.legacyDataURL {
            HistoryNotice(
                symbol: "archivebox",
                title: localized("Encrypted history from an earlier version wasn’t carried over"),
                message: localized(
                    "History and Memory data saved by an earlier encrypted version can’t be opened here. SayKuku won’t migrate or delete these files. They’re still on this Mac for you to keep or remove."
                ),
                fileURL: legacyURL
            ) { appState.data.dismissLegacyDataNotice() }
        }
    }

    private var retentionSubtitle: String {
        switch appState.settings.historyRetention {
        case .off:
            localized("New items aren’t being saved. Existing ones stay until you clear them.")
        case .forever:
            localized("History is kept until you delete it.")
        default:
            localized("Kept for \(appState.settings.historyRetention.title). Starred items are never deleted automatically.")
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if visibleEntries.isEmpty, appState.settings.historyRetention == .off {
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
        } else if visibleEntries.isEmpty {
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
            ScrollView {
                LazyVStack(spacing: 0) {
                    notices

                    ForEach(days) { day in
                        Text(day.label)
                            .font(.kuku(.caption, weight: .semibold))
                            .foregroundStyle(KukuColor.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, day.id == days.first?.id ? 0 : KukuSpacing.xxl)
                            .padding(.bottom, KukuSpacing.sm)

                        ForEach(day.entries) { entry in
                            HistoryRow(
                                entry: entry,
                                isPlaying: playback?.entryID == entry.id,
                                onTogglePlayback: { togglePlayback(entry) },
                                onDelete: { requestDelete(entry) }
                            )
                            if entry.id != day.entries.last?.id {
                                KukuDivider(inset: KukuLayout.iconTile + KukuSpacing.md)
                            }
                        }
                    }
                }
                .padding(.top, KukuLayout.contentTop)
                .padding(.bottom, KukuLayout.contentBottom)
            }
        }
    }

    /// Consecutive entries grouped under one day label, in list order.
    private func daySections(_ entries: [HistoryEntry]) -> [HistoryDay] {
        var days: [HistoryDay] = []
        for entry in entries {
            let label = entry.createdAt.dayLabel
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
        if entry.isStarred {
            pendingDeletion = entry
        } else {
            if playback?.entryID == entry.id { stopPlayback() }
            withAnimation(Motion.snappy) { appState.data.stageHistoryDeletion(entry.id) }
        }
    }

    private func delete(_ entry: HistoryEntry) {
        if playback?.entryID == entry.id { stopPlayback() }
        withAnimation(Motion.snappy) { appState.data.deleteHistoryEntry(entry.id) }
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
                let data = try await appState.data.audio(for: entry)
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


    private func issueCopy(_ issue: LocalStore.DataIssue) -> (title: String, message: String) {
        switch issue {
        case .skippedRecords(let count, let backup):
            return (
                title: localized("\(count) saved items couldn’t be read and were skipped"),
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
    let isPlaying: Bool
    let onTogglePlayback: @MainActor () -> Void
    /// The page owns deletion so the row's button and context menu share one path.
    let onDelete: @MainActor () -> Void
    @State private var isOutputExpanded = false

    private var locale: Locale { historyLocale }

    var body: some View {
        HStack(alignment: .top, spacing: KukuSpacing.md) {
            KukuIconTile(symbol: entry.mode.symbol)

            VStack(alignment: .leading, spacing: KukuSpacing.sm) {
                HStack(spacing: KukuSpacing.iconText) {
                    Text(entry.mode.title)
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
                KukuIconButton(
                    symbol: "trash",
                    label: localized("Delete this item"),
                    action: onDelete
                )

                KukuIconButton(
                    symbol: entry.isStarred ? "star.fill" : "star",
                    label: entry.isStarred ? localized("Remove star") : localized("Star"),
                    help: entry.isStarred ? nil : localized("Star and keep forever"),
                    tint: starTint,
                    action: toggleStar
                )
            }
        }
        .padding(.vertical, KukuSpacing.md)
        // Rows grow with expanded output.
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        .contextMenu {
            if entry.hasCopyableOutput {
                Button(localized("Copy Result")) { appState.copyText(entry.output) }
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

    /// Stars are neutral: a star marks an item to keep, not a status.
    private var starTint: Color {
        if entry.isStarred { return KukuColor.textPrimary }
        return KukuColor.textSecondary
    }

    private func playbackTitle(titleCase: Bool) -> String {
        isPlaying
            ? (titleCase ? localized("Stop Playback") : localized("Stop playback"))
            : (titleCase ? localized("Play Recording") : localized("Play recording"))
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
                Image(systemName: entry.status == .processing && appState.settings.storeVoiceAudio ? "ellipsis" : "waveform.slash")
                    .font(.kukuIcon(.small))
                    .foregroundStyle(KukuColor.textSecondary)
                Text(entry.status == .processing && appState.settings.storeVoiceAudio
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
        case .awaitingConfirmation:
            VStack(alignment: .leading, spacing: KukuSpacing.iconText) {
                Label(localized("Waiting for confirmation"), systemImage: "hand.raised")
                    .foregroundStyle(KukuColor.textSecondary)
                Text(entry.output)
                    .foregroundStyle(KukuColor.textPrimary)
                    .textSelection(.enabled)
            }
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
                        appState.copyText(entry.output)
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
                Task { await appState.workflow.retryDictation(entry.id) }
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
        withAnimation(Motion.spring) { appState.data.toggleHistoryStar(entry.id) }
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

extension Date {
    /// Today, Yesterday, or the date, for History days and when something was remembered.
    var dayLabel: String {
        if Calendar.current.isDateInToday(self) { return localized("Today") }
        if Calendar.current.isDateInYesterday(self) { return localized("Yesterday") }
        return formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: historyLocale))
    }
}

/// Uses the interface language for dates, keeping the user's regional formats when the languages match.
private var historyLocale: Locale {
    let current = Locale.autoupdatingCurrent
    guard current.language.languageCode != interfaceLanguage.languageCode else { return current }
    return Locale(identifier: interfaceLanguage.minimalIdentifier)
}

enum HistoryFilter: String, CaseIterable, Identifiable {
    case all, dictation, agent
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: localized("All")
        case .dictation: localized("Voice Input")
        case .agent: localized("Voice Agent")
        }
    }
}
