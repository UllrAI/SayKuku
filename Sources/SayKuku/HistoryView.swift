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
    @State private var hovering = false
    @State private var player: AVAudioPlayer?

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Button {
                togglePlayback()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(entry.mode.color.opacity(0.1))
                    if isPlaying {
                        Waveform(color: entry.mode.color, barCount: 5, height: 18)
                            .frame(width: 23)
                    } else {
                        Image(systemName: entry.hasAudio ? "play.fill" : entry.mode.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(entry.mode.color)
                    }
                }
                .frame(width: 34, height: 34)
            }
            .buttonStyle(PressScaleStyle())
            .disabled(!entry.hasAudio)
            .help(entry.hasAudio ? appState.text("播放原始语音", "Play original voice") : appState.text("未保存原始语音", "Original voice not saved"))

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Text(entry.mode.title(appState))
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundStyle(entry.mode.color)
                    Text("·")
                    Text(entry.app)
                    Text("·")
                    Text(entry.time)
                    if entry.hasAudio {
                        Text("·")
                        Text(entry.duration)
                    }
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(KukuColor.stone)

                VStack(alignment: .leading, spacing: 6) {
                    LabeledHistoryText(
                        label: appState.text("输入", "Input"),
                        text: entry.input,
                        color: KukuColor.stone,
                        emphasized: false
                    )
                    LabeledHistoryText(
                        label: appState.text("输出", "Output"),
                        text: entry.output,
                        color: KukuColor.ink,
                        emphasized: true
                    )
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

private struct LabeledHistoryText: View {
    let label: String
    let text: String
    let color: Color
    let emphasized: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundStyle(KukuColor.stone)
                .frame(width: 34, alignment: .leading)
            Text(text)
                .font(.system(size: 12.5, weight: emphasized ? .semibold : .regular))
                .foregroundStyle(color)
                .lineLimit(2)
        }
    }
}

enum HistoryFilter: String, CaseIterable, Identifiable {
    case all, dictation, agent
    var id: String { rawValue }
    @MainActor func title(_ appState: AppState) -> String {
        switch self {
        case .all: appState.text("全部", "All")
        case .dictation: "Voice Input"
        case .agent: "Voice Agent"
        }
    }
}
