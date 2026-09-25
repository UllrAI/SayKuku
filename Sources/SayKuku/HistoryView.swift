import AVFoundation
import SwiftUI

struct HistoryView: View {
    @Environment(AppState.self) private var appState
    @Binding var filter: HistoryFilter
    @Binding var search: String

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
                eyebrow: appState.text("历史", "History"),
                title: appState.text("说过的话，随时找回", "Find what you said"),
                subtitle: retentionSubtitle
            ) {
                if !appState.historyEntries.isEmpty {
                    KukuSearchField(
                        prompt: appState.text("搜索内容或 App", "Search text or apps"),
                        clearLabel: appState.text("清除搜索", "Clear search"),
                        text: $search
                    )
                }
            }

            KukuPageTabs(
                items: HistoryFilter.allCases,
                selection: $filter,
                title: { $0.title(appState) }
            )

            KukuDivider(inset: 0)

            KukuPageScroll {
                VStack(alignment: .leading, spacing: 0) {
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
                            title: appState.text("旧版本的加密记录没有迁移过来", "Encrypted history from an earlier version wasn’t carried over"),
                            message: appState.text(
                                "早期版本加密保存的历史、知识和记忆无法在当前版本打开。SayKuku 不会自动迁移或删除它们，文件仍在这台 Mac 上，保留还是删除由你决定。",
                                "History, Knowledge, and Memory saved by an earlier encrypted version can’t be opened here. SayKuku won’t migrate or delete these files. They’re still on this Mac for you to keep or remove."
                            ),
                            fileURL: legacyURL
                        ) { appState.dismissLegacyDataNotice() }
                    }

                    if entries.isEmpty {
                        emptyState
                    } else {
                        entryList(entries)
                    }
                }
            }
        }
    }

    private var retentionSubtitle: String {
        switch appState.historyRetention {
        case .off:
            appState.text("已停止记录新内容，已有记录会保留到你手动清空。", "New items aren’t being saved. Existing ones stay until you clear them.")
        case .forever:
            appState.text("历史记录会一直保留，直到你手动删除。", "History is kept until you delete it.")
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
                title: appState.text("已停止记录历史", "History is off"),
                symbol: "pause.circle",
                message: appState.text(
                    "在“设置 › 历史”里选择保留期限即可重新记录。",
                    "Choose a retention period in Settings › History to start keeping history again."
                )
            ) {
                Button(appState.text("打开设置", "Open Settings")) {
                    appState.settingsSection = .history
                    appState.showMainWindow(destination: .settings)
                }
                .buttonStyle(.kukuSecondary)
            }
        } else if appState.historyEntries.isEmpty {
            KukuEmptyState(
                title: appState.text("还没有历史记录", "No history yet"),
                symbol: "waveform",
                message: appState.text("按 Fn 说句话，记录就会出现在这里。", "Press Fn and start talking. Your history shows up here.")
            )
        } else if !query.isEmpty {
            KukuEmptyState(
                title: appState.text("没有找到匹配的历史记录", "No matching history"),
                symbol: "magnifyingglass",
                message: appState.text("换个关键词试试。", "Try a different search.")
            )
        } else {
            KukuEmptyState(
                title: appState.text("这个分类还没有历史记录", "No history in this category"),
                symbol: "line.3.horizontal.decrease.circle",
                message: appState.text("换个分类，或清除筛选查看全部。", "Switch categories, or clear the filter to see everything.")
            ) {
                Button(appState.text("清除筛选", "Clear Filter")) { filter = .all }
                    .buttonStyle(.kukuSecondary)
            }
        }
    }

    private func entryList(_ entries: [HistoryEntry]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { offset, entry in
                let day = dayLabel(for: entry)
                if offset == 0 || day != dayLabel(for: entries[offset - 1]) {
                    Text(day)
                        .font(.kuku(.caption, weight: .semibold))
                        .foregroundStyle(KukuColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, offset == 0 ? 0 : KukuSpacing.xxl)
                        .padding(.bottom, KukuSpacing.sm)
                }

                HistoryRow(entry: entry)
                // Starts at the text column: row padding, icon tile, then the tile's spacing.
                KukuDivider(inset: KukuLayout.iconTile + KukuSpacing.md * 2)
            }
        }
    }

    private func dayLabel(for entry: HistoryEntry) -> String {
        if Calendar.current.isDateInToday(entry.createdAt) { return appState.text("今天", "Today") }
        if Calendar.current.isDateInYesterday(entry.createdAt) { return appState.text("昨天", "Yesterday") }
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
                message: appState.text(
                    "其余内容都已正常载入。原文件已完整备份为 \(backup.lastPathComponent)。",
                    "Everything else loaded normally. The original file was backed up as \(backup.lastPathComponent)."
                )
            )
        case .movedAside(let backup):
            return (
                title: appState.text("本机数据无法读取，已从空白记录重新开始", "Local data couldn’t be read, so SayKuku started fresh"),
                message: appState.text(
                    "原文件没有被覆盖，已完整备份为 \(backup.lastPathComponent)。",
                    "The original file wasn’t overwritten. It’s saved as \(backup.lastPathComponent)."
                )
            )
        case .readOnly:
            return (
                title: appState.text("本机数据暂时无法读取", "Local data can’t be read right now"),
                message: appState.text(
                    "为避免覆盖原文件，新的更改暂不保存。请检查文件权限或更新 SayKuku，然后重新打开。",
                    "To avoid overwriting the file, new changes won’t be saved. Check the file’s permissions or update SayKuku, then reopen it."
                )
            )
        }
    }
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
                Button(appState.text("在访达中显示", "Show in Finder")) {
                    appState.revealInFinder(fileURL)
                }
                .buttonStyle(.kuku(.secondary, size: .small))
                .padding(.top, KukuSpacing.xs)
            }

            Spacer(minLength: KukuSpacing.sm)

            KukuIconButton(symbol: "xmark", label: appState.text("关闭", "Close"), action: onDismiss)
        }
        .kukuCard()
        .padding(.bottom, KukuLayout.listSpacing)
    }
}

private struct HistoryRow: View {
    @Environment(AppState.self) private var appState
    let entry: HistoryEntry
    @State private var isPlaying = false
    @State private var isOutputExpanded = false
    @State private var hovering = false
    @State private var confirmingDelete = false
    @State private var player: AVAudioPlayer?

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
                    historyLine(label: appState.text("你说的", "Spoken")) { inputContent }
                    historyLine(label: appState.text("结果", "Result")) { outputContent }
                }
            }

            Spacer(minLength: KukuSpacing.lg)

            HStack(spacing: 0) {
                if hovering {
                    KukuIconButton(
                        symbol: "trash",
                        label: appState.text("删除这条记录", "Delete this item"),
                        action: requestDelete
                    )
                }

                KukuIconButton(
                    symbol: entry.isStarred ? "star.fill" : "star",
                    label: entry.isStarred ? appState.text("取消星标", "Remove star") : appState.text("加星标", "Star"),
                    help: entry.isStarred ? nil : appState.text("加星标，永久保留", "Star and keep forever"),
                    tint: starTint,
                    action: toggleStar
                )
            }
        }
        .padding(KukuSpacing.md)
        .contentShape(Rectangle())
        .background(hovering ? KukuColor.rowHover : .clear, in: RoundedRectangle(cornerRadius: KukuLayout.radiusMedium, style: .continuous))
        .onHover { hovering = $0 }
        .animation(Motion.snappy, value: hovering)
        .contextMenu {
            if hasCopyableOutput {
                Button(appState.text("复制结果", "Copy Result")) { appState.copyHistoryOutput(entry.output) }
            }
            if entry.hasAudio {
                Button(playbackTitle(titleCase: true)) { togglePlayback() }
            }
            Button(entry.isStarred ? appState.text("取消星标", "Remove Star") : appState.text("加星标", "Star")) {
                toggleStar()
            }
            Divider()
            Button(
                entry.isStarred ? appState.text("删除…", "Delete…") : appState.text("删除", "Delete"),
                role: .destructive
            ) { requestDelete() }
        }
        .confirmationDialog(
            appState.text("删除这条星标记录？", "Delete this starred item?"),
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button(appState.text("删除", "Delete"), role: .destructive) { delete() }
            Button(appState.text("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text(entry.hasAudio
                 ? appState.text("录音也会一起删除，且无法恢复。", "Its recording will be deleted too. This can’t be undone.")
                 : appState.text("删除后无法恢复。", "This can’t be undone."))
        }
    }

    /// Stars are neutral: a star marks an item to keep, not a status.
    private var starTint: Color {
        if entry.isStarred { return KukuColor.textPrimary }
        return hovering ? KukuColor.textSecondary : KukuColor.textTertiary
    }

    private var hasCopyableOutput: Bool { entry.status == .completed && !entry.output.isEmpty }

    private func playbackTitle(titleCase: Bool) -> String {
        isPlaying
            ? appState.text("停止播放", titleCase ? "Stop Playback" : "Stop playback")
            : appState.text("播放录音", titleCase ? "Play Recording" : "Play recording")
    }

    @ViewBuilder
    private var inputContent: some View {
        HStack(spacing: KukuSpacing.sm) {
            if entry.hasAudio {
                Button { togglePlayback() } label: {
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
                     ? appState.text("正在保存录音…", "Saving recording…")
                     : appState.text("没有录音", "No recording"))
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
                     ? appState.text("正在识别…", "Transcribing…")
                     : appState.text("正在处理…", "Processing…"))
            }
            .foregroundStyle(KukuColor.textSecondary)
        case .failed:
            VStack(alignment: .leading, spacing: KukuSpacing.sm) {
                KukuStatusLabel(
                    text: entry.errorMessage ?? appState.text("处理失败", "Processing failed"),
                    tone: .danger,
                    font: .kuku(.body)
                )
                retryButton
            }
        case .cancelled:
            VStack(alignment: .leading, spacing: KukuSpacing.sm) {
                Label(appState.text("已取消", "Cancelled"), systemImage: "xmark.circle")
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

                if hasCopyableOutput {
                    Button {
                        appState.copyHistoryOutput(entry.output)
                    } label: {
                        Label(appState.text("复制结果", "Copy Result"), systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.kuku(.plain, size: .small))
                }

                if shouldCollapseOutput {
                    Button {
                        withAnimation(Motion.snappy) { isOutputExpanded.toggle() }
                    } label: {
                        Label(
                            isOutputExpanded
                                ? appState.text("收起", "Show Less")
                                : appState.text("展开", "Show More"),
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
            Button(appState.text("重新识别", "Retry Transcription")) {
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

    /// Starred items are meant to be kept, so deleting one asks first.
    private func requestDelete() {
        if entry.isStarred { confirmingDelete = true } else { delete() }
    }

    private func delete() {
        player?.stop()
        player = nil
        withAnimation(Motion.snappy) { appState.deleteHistoryEntry(entry.id) }
        appState.showToast(appState.text("已删除", "Deleted"), symbol: "trash")
    }

    /// Formats a recording length as m:ss, e.g. 0:04 or 1:25.
    private static func durationLabel(_ seconds: Double) -> String {
        guard seconds > 0 else { return "—" }
        let total = max(1, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func togglePlayback() {
        if isPlaying {
            player?.stop()
            player = nil
            withAnimation(Motion.snappy) { isPlaying = false }
            return
        }
        Task {
            do {
                let data = try await appState.playAudio(for: entry)
                let audioPlayer = try AVAudioPlayer(data: data)
                audioPlayer.prepareToPlay()
                audioPlayer.play()
                player = audioPlayer
                withAnimation(Motion.snappy) { isPlaying = true }
                try? await Task.sleep(for: .seconds(max(entry.durationSeconds, 0.2)))
                guard player === audioPlayer else { return }
                player = nil
                withAnimation(Motion.snappy) { isPlaying = false }
            } catch {
                appState.showToast(
                    appState.text("无法播放这段录音，文件可能已被移动或删除", "Couldn’t play this recording. The file may have been moved or deleted."),
                    symbol: "exclamationmark.triangle.fill"
                )
            }
        }
    }
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
        case .all: appState.text("全部", "All")
        case .dictation: appState.voiceInputTitle
        case .agent: appState.voiceAgentTitle
        }
    }
}
