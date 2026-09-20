import SwiftUI

struct HomeView: View {
    var body: some View {
        ZStack {
            KukuColor.canvas.ignoresSafeArea()
            HomeReadyState()
        }
    }
}

private struct HomeReadyState: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(
                eyebrow: appState.text("快速开始", "Quick start"),
                title: appState.text("在当前输入框，直接开口", "Speak right where you type"),
                subtitle: appState.text("无需打开 SayKuku 窗口，使用 Fn 即可随时输入。", "Keep this window closed—Fn is always ready.")
            )

            Spacer()
                .frame(height: 46)

            KukuPageContent {
                VStack(alignment: .leading, spacing: 15) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            voiceInputCard
                            voiceAgentCard
                        }

                        VStack(spacing: 12) {
                            voiceInputCard
                            voiceAgentCard
                        }
                    }

                    Label(
                        appState.text("语音仅在你主动触发后发送", "Audio is sent only when you invoke it"),
                        systemImage: "lock.fill"
                    )
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(KukuColor.stone)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }

            Spacer(minLength: 40)
        }
    }

    private var voiceInputCard: some View {
        HomeGestureRow(
            key: "Fn",
            title: appState.voiceInputTitle,
            subtitle: appState.text("按住说话，松开后写入当前光标", "Hold to speak, release to type"),
            symbol: "mic.fill",
            accent: KukuColor.coral
        ) {
            appState.startDictation()
        }
    }

    private var voiceAgentCard: some View {
        HomeGestureRow(
            key: "Fn Fn",
            title: appState.voiceAgentTitle,
            subtitle: appState.text("说出意图，识别后直接执行或写回", "Say an intent to run it or write it back"),
            symbol: "sparkles",
            accent: KukuColor.graphite
        ) {
            appState.startAgent()
        }
    }
}

private struct HomeGestureRow: View {
    @Environment(AppState.self) private var appState
    let key: String
    let title: String
    let subtitle: String
    let symbol: String
    let accent: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 34, height: 34)
                        .background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                    Spacer()

                    Text(key)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(Color.black.opacity(0.055), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(KukuColor.stone)
                        .lineLimit(2)
                }

                HStack(spacing: 5) {
                    Text(appState.text("开始", "Open"))
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(accent.opacity(hovering ? 1 : 0.72))
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
            .background(hovering ? Color.white.opacity(0.32) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .kukuSurface(radius: KukuLayout.radiusLarge, elevated: true)
        .onHover { hovering = $0 }
        .animation(Motion.snappy, value: hovering)
    }
}

struct AgentPill: View {
    @Environment(AppState.self) private var appState
    @State private var showingContext = false

    private var width: CGFloat {
        switch appState.agentPhase {
        case .hidden: 0
        case .listening:
            KukuPillLayout.width(for: listeningLabel, minimum: 168, fixedContentWidth: 140)
        case .copyReady:
            KukuPillLayout.width(for: appState.pendingCopyText, minimum: 180, fixedContentWidth: 136)
        case .transcribing:
            KukuPillLayout.width(for: transcribingLabel, minimum: 112, fixedContentWidth: 48, maximum: 200)
        case .processing:
            KukuPillLayout.width(for: processingLabel, minimum: 112, fixedContentWidth: 48)
        case .result:
            KukuPillLayout.width(for: resultLabel, minimum: 78, fixedContentWidth: 38, maximum: 320)
        }
    }

    private var listeningLabel: String {
        appState.liveTranscript.isEmpty ? appState.agentCommand : appState.liveTranscript
    }

    private var transcribingLabel: String {
        appState.text("正在理解…", "Understanding…")
    }

    private var taskTitle: String {
        let value = appState.agentCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        return value == appState.text("正在听…", "Listening…") ? "" : value
    }

    private var processingLabel: String {
        taskTitle.isEmpty
            ? appState.text("正在执行…", "Running…")
            : appState.text("正在执行 · \(taskTitle)", "Running · \(taskTitle)")
    }

    private var resultLabel: String {
        taskTitle.isEmpty
            ? appState.text("已完成", "Done")
            : appState.text("已完成 · \(taskTitle)", "Done · \(taskTitle)")
    }

    var body: some View {
        HStack(spacing: 8) {
            if appState.agentPhase == .copyReady {
                CopyFallbackContent()
            } else if appState.agentPhase == .listening {
                Button(action: appState.dismissAgent) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(KukuColor.stone.opacity(0.82))
                        .frame(width: 26, height: 26)
                        .background { Circle().fill(Color.black.opacity(0.05)) }
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel(appState.text("取消语音 Agent", "Cancel Voice Agent"))
                .help(appState.text("取消语音 Agent", "Cancel Voice Agent"))

                HStack(spacing: 4) {
                    Button { showingContext.toggle() } label: {
                        Image(systemName: "sparkle")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(KukuColor.coral.opacity(0.82))
                            .frame(width: 16, height: 22)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(appState.text("查看本次上下文", "Show context"))
                    .help(appState.text("查看本次上下文", "Show context"))
                    .popover(isPresented: $showingContext, arrowEdge: .bottom) {
                        AgentContextPopover()
                    }

                    Waveform(
                        color: KukuColor.stone.opacity(0.58),
                        level: appState.inputLevel,
                        barCount: 5,
                        height: 15
                    )
                    .frame(width: 22)
                }

                Text(listeningLabel)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(KukuColor.ink.opacity(0.78))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                Button(action: appState.finishAgentListening) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.94))
                        .frame(width: 26, height: 26)
                        .background { Circle().fill(KukuColor.coral.opacity(0.84)) }
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel(appState.text("结束录音并执行", "Stop recording and run"))
                .help(appState.text("结束录音并执行", "Stop recording and run"))
            } else if appState.agentPhase == .transcribing || appState.agentPhase == .processing {
                AgentActivityIndicator()
                Text(appState.agentPhase == .transcribing
                     ? transcribingLabel
                     : processingLabel)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(KukuColor.ink.opacity(0.78))
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else if appState.agentPhase == .result {
                Label(resultLabel, systemImage: "checkmark")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(KukuColor.ink.opacity(0.64))
                    .lineLimit(1)
            }
        }
        .contentTransition(.interpolate)
        .animation(Motion.snappy, value: appState.agentPhase)
        .animation(Motion.snappy, value: appState.liveTranscript.isEmpty)
        .padding(.horizontal, 7)
        .frame(width: width, height: 40)
        .kukuGlassPill()
        .animation(Motion.pill, value: width)
    }
}

private struct AgentActivityIndicator: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let progress = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 1.6) / 1.6
            let pulse = 0.76 + 0.24 * (0.5 - 0.5 * cos(progress * 2 * .pi))

            Image(systemName: "sparkle")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [KukuColor.stone, KukuColor.coral.opacity(0.88), KukuColor.amber],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .rotationEffect(.degrees(progress * 180))
                .scaleEffect(pulse)
                .shadow(color: KukuColor.coral.opacity(0.2), radius: 3)
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}

private struct AgentContextPopover: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(appState.text("本次使用的上下文", "Context used this time"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(KukuColor.stone)

            ForEach(appState.contextItems) { item in
                HStack(spacing: 9) {
                    Image(systemName: item.symbol)
                        .foregroundStyle(KukuColor.coral)
                        .frame(width: 16)
                    Text(item.title.replacingOccurrences(
                        of: "28 字",
                        with: appState.text("28 字", "28 chars")
                    ))
                    .font(.system(size: 12, weight: .medium))
                    Spacer()
                    if appState.agentPhase == .listening {
                        Button {
                            appState.contextItems.removeAll { $0.id == item.id }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(KukuColor.stone)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(appState.text("移除此上下文", "Remove this context"))
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 230)
    }
}

struct DictationPill: View {
    @Environment(AppState.self) private var appState

    private var width: CGFloat {
        switch appState.dictationPhase {
        case .idle: 0
        case .listening:
            KukuPillLayout.width(for: listeningLabel, minimum: 132, fixedContentWidth: 86, maximum: 340)
        case .copyReady:
            KukuPillLayout.width(for: appState.pendingCopyText, minimum: 180, fixedContentWidth: 136)
        case .processing:
            KukuPillLayout.width(for: processingLabel, minimum: 112, fixedContentWidth: 48, maximum: 340)
        case .success:
            KukuPillLayout.width(for: successLabel, minimum: 78, fixedContentWidth: 42, maximum: 160)
        }
    }

    private var listeningLabel: String {
        appState.liveTranscript.isEmpty ? appState.text("正在听…", "Listening…") : appState.liveTranscript
    }

    private var processingLabel: String {
        appState.liveTranscript.isEmpty ? appState.text("正在整理…", "Formatting…") : appState.liveTranscript
    }

    private var successLabel: String {
        appState.text("已输入", "Done")
    }

    var body: some View {
        HStack(spacing: 8) {
            switch appState.dictationPhase {
            case .idle:
                EmptyView()
            case .listening:
                Waveform(color: KukuColor.coral.opacity(0.82), level: appState.inputLevel, barCount: 6, height: 16)
                Text(listeningLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Button(action: appState.finishDictation) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 25, height: 25)
                        .background(KukuColor.coral.opacity(0.84), in: Circle())
                        .foregroundStyle(Color.white.opacity(0.94))
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel(appState.text("结束录音并输入", "Stop recording and insert"))
                .help(appState.text("结束录音并输入", "Stop recording and insert"))
            case .processing:
                ProgressView().controlSize(.small)
                Text(processingLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
            case .success:
                Image(systemName: "checkmark")
                Text(successLabel)
            case .copyReady:
                CopyFallbackContent()
            }
        }
        .contentTransition(.interpolate)
        .animation(Motion.snappy, value: appState.dictationPhase)
        .animation(Motion.snappy, value: appState.liveTranscript.isEmpty)
        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
        .foregroundStyle(KukuColor.ink.opacity(appState.dictationPhase == .success ? 0.62 : 0.78))
        .padding(.horizontal, 10)
        .frame(width: width, height: appState.dictationPhase == .copyReady ? 40 : 34)
        .kukuGlassPill()
        .animation(Motion.pill, value: width)
    }
}

private struct CopyFallbackContent: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .foregroundStyle(KukuColor.coral.opacity(0.82))
            Text(appState.pendingCopyText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Button(action: appState.copyPendingText) {
                Label(appState.text("复制", "Copy"), systemImage: "doc.on.doc")
                    .font(.system(size: 10.5, weight: .semibold))
                    .padding(.horizontal, 9)
                    .frame(height: 25)
                    .background(Color.black.opacity(0.055), in: Capsule())
            }
            .buttonStyle(.plain)
            .help(appState.text("复制", "Copy"))
            Button(action: appState.dismissCopyFallback) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 25, height: 25)
                    .background(Color.black.opacity(0.05), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(appState.text("关闭", "Close"))
            .help(appState.text("关闭", "Close"))
        }
        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
        .foregroundStyle(KukuColor.ink.opacity(0.76))
        .frame(maxWidth: .infinity)
    }
}
