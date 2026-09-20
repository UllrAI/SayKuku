import AVFoundation
import SwiftUI

struct HistoryView: View {
    @Environment(AppState.self) private var appState
    @State private var filter: HistoryFilter = .all

    private var filteredIndices: [Int] {
        appState.historyEntries.indices.filter { index in
            filter == .all || appState.historyEntries[index].mode.filter == filter
        }
    }

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 0) {
            ScreenHeader(
                eyebrow: "History",
                title: appState.text("最近说过，也随时找得到", "Everything you said, easy to find"),
                subtitle: appState.text(
                    "保留 \(appState.historyRetention.chineseTitle)，星标内容不会自动清理",
                    "Kept for \(appState.historyRetention.englishTitle); starred items never expire"
                )
            )

            KukuPageTabs(
                items: HistoryFilter.allCases,
                selection: $filter,
                title: { $0.title(appState) }
            )

            Divider().opacity(0.55)

            ScrollView {
                KukuPageContent {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredIndices.enumerated()), id: \.element) { offset, index in
                            if offset == 0 || dayLabel(for: index) != dayLabel(for: filteredIndices[offset - 1]) {
                                Text(dayLabel(for: index))
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .tracking(0.45)
                                    .foregroundStyle(KukuColor.stone)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, offset == 0 ? 20 : 26)
                                    .padding(.bottom, 7)
                            }

                            HistoryRow(entry: $appState.historyEntries[index])
                                .id(appState.historyEntries[index].id)
                            Divider().padding(.leading, 58).opacity(0.45)
                        }
                    }
                }
                .padding(.bottom, 36)
            }
        }
    }

    private func dayLabel(for index: Int) -> String {
        let entry = appState.historyEntries[index]
        if Calendar.current.isDateInToday(entry.createdAt) { return appState.text("今天", "Today") }
        if Calendar.current.isDateInYesterday(entry.createdAt) { return appState.text("昨天", "Yesterday") }
        return entry.createdAt.formatted(date: .abbreviated, time: .omitted)
    }
}

private struct HistoryRow: View {
    @Environment(AppState.self) private var appState
    @Binding var entry: HistoryEntry
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
                    historyLine(label: appState.text("输入", "Input")) { inputContent }
                    historyLine(label: appState.text("输出", "Output")) { outputContent }
                }
            }

            Spacer(minLength: 18)

            Button {
                withAnimation(Motion.spring) { entry.isStarred.toggle() }
            } label: {
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
        .padding(.vertical, 13)
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
        .background(hovering ? Color.white.opacity(0.48) : .clear, in: RoundedRectangle(cornerRadius: KukuLayout.radiusMedium, style: .continuous))
        .onHover { hovering = $0 }
        .animation(Motion.snappy, value: hovering)
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
                .help(appState.text("播放原始语音", "Play original voice"))
            } else {
                Image(systemName: entry.status == .processing && appState.storeVoiceAudio ? "ellipsis" : "waveform.slash")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(KukuColor.stone)
                Text(entry.status == .processing && appState.storeVoiceAudio
                     ? appState.text("正在保存录音…", "Saving voice…")
                     : appState.text("未保存原始语音", "Original voice not saved"))
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
            Label(entry.errorMessage ?? appState.text("处理失败", "Processing failed"), systemImage: "exclamationmark.circle")
                .foregroundStyle(KukuColor.stone)
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
                appState.showToast(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
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
