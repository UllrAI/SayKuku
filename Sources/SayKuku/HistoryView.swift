import AVFoundation
import SwiftUI

struct HistoryView: View {
    @Environment(AppState.self) private var appState
    @State private var filter: HistoryFilter = .all
    @State private var search = ""

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
                title: appState.text("最近说过，也随时找得到", "Everything you said, easy to find"),
                subtitle: retentionSubtitle
            ) {
                if !appState.historyEntries.isEmpty { searchField }
            }

            KukuPageTabs(
                items: HistoryFilter.allCases,
                selection: $filter,
                title: { $0.title(appState) }
            )

            Divider().opacity(0.55)

            ScrollView {
                KukuPageContent {
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
                                title: appState.text("旧版本的加密记录没有迁移过来", "Encrypted history from an earlier version wasn't carried over"),
                                message: appState.text(
                                    "早期版本加密保存的历史、知识和记忆无法在当前版本打开。SayKuku 不会自动迁移或删除它们，文件仍在这台 Mac 上，保留还是删除由你决定。",
                                    "History, knowledge, and memory saved by an earlier encrypted version can't be opened here. SayKuku won't migrate or delete these files; they're still on this Mac for you to keep or remove."
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
                .padding(.bottom, 36)
            }
        }
    }

    private var retentionSubtitle: String {
        guard appState.historyRetention != .forever else {
            return appState.text("历史会一直保留，直到你手动删除", "History is kept until you delete it")
        }
        return appState.text(
            "保留 \(appState.historyRetention.chineseTitle)，星标内容不会自动清理",
            "Kept for \(appState.historyRetention.englishTitle); starred items never expire"
        )
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(KukuColor.stone)
            TextField(appState.text("搜索内容或 App", "Search text or apps"), text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(KukuColor.stone)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(appState.text("清除搜索", "Clear search"))
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 220, height: KukuLayout.controlHeight)
        .background(KukuColor.surfaceStrong, in: RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous).stroke(KukuColor.line, lineWidth: 1))
    }

    private var emptyState: some View {
        let title: String
        let message: String
        var symbol = "waveform"
        if appState.historyEntries.isEmpty {
            title = appState.text("还没有输入记录", "No voice history yet")
            message = appState.text("用 Fn 开始语音输入，记录会显示在这里。", "Use Fn to start voice input. Your history will appear here.")
        } else if !query.isEmpty {
            title = appState.text("没有找到相关记录", "No matching history")
            message = appState.text("换个关键词试试。", "Try a different word.")
            symbol = "magnifyingglass"
        } else {
            title = appState.text("这个分类还没有记录", "No history in this category")
            message = appState.text("切换到“全部”查看其他记录。", "Choose All to see your other history.")
        }
        return ContentUnavailableView(title, systemImage: symbol, description: Text(message))
            .frame(maxWidth: .infinity, minHeight: 180)
    }

    private func entryList(_ entries: [HistoryEntry]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { offset, entry in
                let day = dayLabel(for: entry)
                if offset == 0 || day != dayLabel(for: entries[offset - 1]) {
                    Text(day)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(0.45)
                        .foregroundStyle(KukuColor.stone)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, offset == 0 ? 20 : 26)
                        .padding(.bottom, 7)
                }

                HistoryRow(entry: entry)
                Divider().padding(.leading, 58).opacity(0.45)
            }
        }
    }

    private func dayLabel(for entry: HistoryEntry) -> String {
        if Calendar.current.isDateInToday(entry.createdAt) { return appState.text("今天", "Today") }
        if Calendar.current.isDateInYesterday(entry.createdAt) { return appState.text("昨天", "Yesterday") }
        return entry.createdAt.formatted(date: .abbreviated, time: .omitted)
    }

    private func issueCopy(_ issue: LocalStore.DataIssue) -> (title: String, message: String) {
        switch issue {
        case .skippedRecords(let count, let backup):
            return (
                title: appState.text(
                    "有 \(count) 条本地记录无法读取，已跳过",
                    count == 1 ? "1 saved item couldn't be read and was skipped" : "\(count) saved items couldn't be read and were skipped"
                ),
                message: appState.text(
                    "其余内容都已正常载入。原文件已完整备份为 \(backup.lastPathComponent)。",
                    "Everything else loaded normally. The original file was backed up as \(backup.lastPathComponent)."
                )
            )
        case .movedAside(let backup):
            return (
                title: appState.text("本地数据无法读取，已从空白记录重新开始", "Local data couldn't be read, so SayKuku started fresh"),
                message: appState.text(
                    "原文件没有被覆盖，已完整备份为 \(backup.lastPathComponent)。",
                    "The original file wasn't overwritten. It's saved as \(backup.lastPathComponent)."
                )
            )
        case .readOnly:
            return (
                title: appState.text("本地数据暂时无法读取", "Local data can't be read right now"),
                message: appState.text(
                    "为避免覆盖原文件，新的更改暂不保存。请检查文件权限后重新打开 SayKuku。",
                    "To avoid overwriting the file, new changes won't be saved. Check the file's permissions, then reopen SayKuku."
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
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(KukuColor.amber)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(KukuColor.ink)
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(KukuColor.stone)
                    .fixedSize(horizontal: false, vertical: true)
                Button(appState.text("在访达中显示", "Show in Finder")) {
                    appState.revealInFinder(fileURL)
                }
                .buttonStyle(TintButtonStyle())
                .padding(.top, 6)
            }

            Spacer(minLength: 8)

            Button { onDismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(KukuColor.stone)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(appState.text("关闭", "Close"))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kukuSurface(radius: KukuLayout.radiusMedium)
        .padding(.top, 16)
    }
}

private struct HistoryRow: View {
    @Environment(AppState.self) private var appState
    let entry: HistoryEntry
    @State private var isPlaying = false
    @State private var isOutputExpanded = false
    @State private var hovering = false
    @State private var player: AVAudioPlayer?

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(KukuColor.stone.opacity(0.11))
                Image(systemName: entry.mode.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(KukuColor.stone)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Text(entry.mode.title(appState))
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundStyle(KukuColor.stone)
                    Text("·")
                    Text(entry.app)
                    Text("·")
                    Text(entry.time)
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(KukuColor.stone)

                VStack(alignment: .leading, spacing: 6) {
                    historyLine(label: appState.text("你说的", "Spoken")) { inputContent }
                    historyLine(label: appState.text("结果", "Result")) { outputContent }
                }
            }

            Spacer(minLength: 18)

            HStack(spacing: 0) {
                if hovering {
                    Button { delete() } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(KukuColor.stone.opacity(0.8))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(PressScaleStyle())
                    .help(appState.text("删除这条记录", "Delete this item"))
                }

                Button { toggleStar() } label: {
                    Image(systemName: entry.isStarred ? "star.fill" : "star")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(entry.isStarred ? KukuColor.amber : KukuColor.stone.opacity(hovering ? 0.8 : 0.35))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(PressScaleStyle())
                .help(entry.isStarred
                      ? appState.text("取消星标", "Remove star")
                      : appState.text("加星标，永久保留", "Star and keep forever"))
            }
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
        .background(hovering ? KukuColor.highlight.opacity(0.48) : .clear, in: RoundedRectangle(cornerRadius: KukuLayout.radiusMedium, style: .continuous))
        .onHover { hovering = $0 }
        .animation(Motion.snappy, value: hovering)
        .contextMenu {
            Button(entry.isStarred ? appState.text("取消星标", "Remove Star") : appState.text("加星标", "Star")) {
                toggleStar()
            }
            Divider()
            Button(appState.text("删除", "Delete"), role: .destructive) { delete() }
        }
    }

    @ViewBuilder
    private var inputContent: some View {
        HStack(spacing: 8) {
            if entry.hasAudio {
                Button { togglePlayback() } label: {
                    HStack(spacing: 7) {
                        if isPlaying {
                            Waveform(color: KukuColor.stone, barCount: 5, height: 12)
                                .frame(width: 20)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        Text(entry.duration)
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(KukuColor.stone)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(KukuColor.stone.opacity(0.09), in: Capsule())
                }
                .buttonStyle(PressScaleStyle())
                .help(appState.text("播放录音", "Play recording"))
            } else {
                Image(systemName: entry.status == .processing && appState.storeVoiceAudio ? "ellipsis" : "waveform.slash")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(KukuColor.stone)
                Text(entry.status == .processing && appState.storeVoiceAudio
                     ? appState.text("正在保存录音…", "Saving voice…")
                     : appState.text("未保存录音", "Recording not saved"))
                    .font(.system(size: 11))
                    .foregroundStyle(KukuColor.stone)
            }

            if entry.mode == .agent, !entry.input.isEmpty {
                Text(entry.input)
                    .font(.system(size: 11.5))
                    .foregroundStyle(KukuColor.stone)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private var outputContent: some View {
        switch entry.status {
        case .processing:
            HStack(spacing: 7) {
                ProgressView().controlSize(.mini)
                Text(entry.mode == .dictation
                     ? appState.text("正在识别…", "Transcribing…")
                     : appState.text("正在处理…", "Processing…"))
            }
            .foregroundStyle(KukuColor.stone)
        case .failed:
            VStack(alignment: .leading, spacing: 8) {
                Label(entry.errorMessage ?? appState.text("处理失败", "Processing failed"), systemImage: "exclamationmark.circle")
                    .foregroundStyle(KukuColor.stone)
                if entry.mode == .dictation && entry.hasAudio {
                    Button(appState.text("重试识别", "Retry")) {
                        Task { await appState.retryDictation(entry.id) }
                    }
                    .buttonStyle(TintButtonStyle())
                }
            }
        case .cancelled:
            Label(appState.text("已取消", "Cancelled"), systemImage: "xmark.circle")
                .foregroundStyle(KukuColor.stone)
        case .completed:
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.output)
                    .foregroundStyle(KukuColor.ink)
                    .lineLimit(shouldCollapseOutput && !isOutputExpanded ? 4 : nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                if !entry.output.isEmpty {
                    Button {
                        appState.copyHistoryOutput(entry.output)
                    } label: {
                        Label(appState.text("复制输出", "Copy output"), systemImage: "doc.on.doc")
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(KukuColor.coral)
                }

                if shouldCollapseOutput {
                    Button {
                        withAnimation(Motion.snappy) { isOutputExpanded.toggle() }
                    } label: {
                        Label(
                            isOutputExpanded
                                ? appState.text("收起", "Collapse")
                                : appState.text("展开全文", "Show all"),
                            systemImage: isOutputExpanded ? "chevron.up" : "chevron.down"
                        )
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(KukuColor.stone)
                    }
                    .buttonStyle(.plain)
                }
            }
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
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundStyle(KukuColor.stone)
                .frame(width: 34, alignment: .leading)
            content()
                .font(.system(size: 12.5, weight: .semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggleStar() {
        withAnimation(Motion.spring) { appState.toggleHistoryStar(entry.id) }
    }

    private func delete() {
        player?.stop()
        player = nil
        withAnimation(Motion.snappy) { appState.deleteHistoryEntry(entry.id) }
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
                appState.showToast(appState.localizedError(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }
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
