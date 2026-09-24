import AppKit
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
    @State private var practiceText = ""
    @FocusState private var practiceFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(
                eyebrow: appState.text("快速开始", "Quick start"),
                title: appState.text("在当前输入框，直接开口", "Speak right where you type"),
                subtitle: appState.text("在任意输入框按 Fn 即可，不用打开 SayKuku。", "Press Fn in any text field. No need to open SayKuku.")
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

                    VStack(alignment: .leading, spacing: 9) {
                        Text(appState.text("试写区", "Try it here"))
                            .font(.system(size: 12, weight: .semibold))
                        Text(appState.text(
                            "点这里，按 Fn 说句话；选中文字后连按两次 Fn，让语音 Agent 改写。",
                            "Click here and press Fn to talk. Select text and press Fn twice to have Voice Agent rewrite it."
                        ))
                        .font(.system(size: 11))
                        .foregroundStyle(KukuColor.stone)
                        TextEditor(text: $practiceText)
                            .focused($practiceFocused)
                            .font(.system(size: 13))
                            .scrollContentBackground(.hidden)
                            .frame(height: 70)
                            .padding(8)
                            .background(KukuColor.canvas, in: RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous))
                            .accessibilityLabel(appState.text("语音试写区", "Voice practice field"))
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .kukuSurface(radius: KukuLayout.radiusLarge)

                    Label(
                        appState.text("只在你按下 Fn 或快捷键后才录音并发送", "SayKuku only records and sends audio after you press Fn or your shortcut"),
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
            subtitle: appState.inputMode == .hold
                ? appState.text("按住说话，松开即输入", "Hold to talk, release to insert")
                : appState.text("单击开始说话，再单击即输入", "Tap to start, tap again to insert"),
            shortcut: appState.globalShortcut(for: .voiceInput),
            symbol: "mic.fill",
            accent: KukuColor.coral
        ) {
            practiceFocused = true
        }
    }

    private var voiceAgentCard: some View {
        HomeGestureRow(
            key: "Fn Fn",
            title: appState.voiceAgentTitle,
            subtitle: appState.text("改写选中文字、提问或打开网页", "Rewrite selected text, ask questions, or open pages"),
            shortcut: appState.globalShortcut(for: .voiceAgent),
            symbol: "sparkles",
            accent: KukuColor.ink
        ) {
            practiceFocused = true
        }
    }
}

private struct HomeGestureRow: View {
    @Environment(AppState.self) private var appState
    let key: String
    let title: String
    let subtitle: String
    /// The optional global shortcut, shown for people without an Fn key.
    let shortcut: GlobalShortcut?
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
                        .background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous))

                    Spacer()

                    Text(key)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(KukuColor.shade.opacity(0.055), in: RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(KukuColor.stone)
                        .lineLimit(2)
                }

                if let shortcut {
                    Text(appState.text("或 \(shortcut.displayString)", "or \(shortcut.displayString)"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(KukuColor.stone)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
            .background(hovering ? KukuColor.highlight.opacity(0.32) : .clear)
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
            CopyFallbackContent.width(appState)
        case .answerReady:
            0
        case .transcribing:
            KukuPillLayout.width(for: transcribingLabel, minimum: 145, fixedContentWidth: 81, maximum: 233)
        case .processing:
            KukuPillLayout.width(for: processingLabel, minimum: 145, fixedContentWidth: 81)
        case .result:
            KukuPillLayout.width(for: resultLabel, minimum: 78, fixedContentWidth: appState.resultCanUndo ? 96 : 38, maximum: 320)
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
                PillCancelButton(
                    label: appState.text("取消语音 Agent", "Cancel Voice Agent"),
                    action: appState.dismissAgent
                )

                HStack(spacing: 4) {
                    Button { showingContext.toggle() } label: {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(KukuColor.coral.opacity(0.82))
                            .frame(width: 16, height: 22)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(appState.text("查看本次会发送的内容", "Review what’s sent"))
                    .help(appState.text("查看本次会发送的内容", "Review what’s sent"))
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

                PillConfirmButton(
                    label: appState.text("结束录音并执行", "Stop recording and run"),
                    action: appState.finishAgentListening
                )
            } else if appState.agentPhase == .transcribing || appState.agentPhase == .processing {
                AgentActivityIndicator()
                Text(appState.agentPhase == .transcribing
                     ? transcribingLabel
                     : processingLabel)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(KukuColor.ink.opacity(0.78))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                PillCancelButton(
                    label: appState.text("取消语音 Agent", "Cancel Voice Agent"),
                    action: appState.dismissAgent
                )
            } else if appState.agentPhase == .result {
                Label(resultLabel, systemImage: "checkmark")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(KukuColor.ink.opacity(0.64))
                    .lineLimit(1)
                if appState.resultCanUndo {
                    Spacer(minLength: 0)
                    Button(appState.text("撤销", "Undo")) {
                        Task { await appState.undoLastWrite() }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(KukuColor.coral)
                }
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

/// Cancels recording or processing; nothing is written afterwards.
private struct PillCancelButton: View {
    let label: String
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(KukuColor.stone.opacity(0.82))
                .frame(width: 25, height: 25)
                .background(KukuColor.shade.opacity(0.05), in: Circle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(label)
        .help(label)
    }
}

/// Ends recording and hands the audio off for processing.
private struct PillConfirmButton: View {
    let label: String
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.94))
                .frame(width: 25, height: 25)
                .background(KukuColor.coral.opacity(0.84), in: Circle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(label)
        .help(label)
    }
}

private struct AgentContextPopover: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(appState.text("本次会发送的内容", "What’s sent"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(KukuColor.stone)

            if appState.contextItems.isEmpty {
                Text(appState.text("本次只发送你的语音", "Only your voice will be sent"))
                    .font(.system(size: 12))
                    .foregroundStyle(KukuColor.stone)
            }

            ForEach(appState.contextItems) { item in
                HStack(spacing: 9) {
                    Image(systemName: item.symbol)
                        .foregroundStyle(KukuColor.coral)
                        .frame(width: 16)
                    Text(item.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    if appState.agentPhase == .listening {
                        let removeLabel = appState.text("移除“\(item.title)”", "Remove \(item.title)")
                        Button {
                            appState.contextItems.removeAll { $0.id == item.id }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(KukuColor.stone)
                                .frame(width: 20, height: 20)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(removeLabel)
                        .help(removeLabel)
                    }
                }
                .help(Self.preview(of: item) ?? "")
            }
        }
        .padding(14)
        .frame(width: 230)
    }

    /// Lets people check the actual text; app, knowledge and conversation values are internal summaries.
    private static func preview(of item: ContextItem) -> String? {
        switch item.kind {
        case .selectedText, .previousOutput, .window, .clipboard, .browser, .domain:
            return item.value.count > 200 ? "\(item.value.prefix(200))…" : item.value
        case .app, .session, .knowledge:
            return nil
        }
    }
}

struct DictationPill: View {
    @Environment(AppState.self) private var appState

    private var width: CGFloat {
        switch appState.dictationPhase {
        case .idle: 0
        case .listening:
            KukuPillLayout.width(for: listeningLabel, minimum: 160, fixedContentWidth: 141, maximum: 340)
        case .copyReady:
            CopyFallbackContent.width(appState)
        case .processing:
            KukuPillLayout.width(for: processingLabel, minimum: 145, fixedContentWidth: 81, maximum: 340)
        case .success:
            KukuPillLayout.width(for: successLabel, minimum: 78, fixedContentWidth: appState.canUndoLastWrite ? 100 : 42, maximum: 200)
        }
    }

    private var listeningLabel: String {
        appState.liveTranscript.isEmpty ? appState.text("正在听…", "Listening…") : appState.liveTranscript
    }

    private var processingLabel: String {
        appState.liveTranscript.isEmpty ? appState.text("正在识别…", "Transcribing…") : appState.liveTranscript
    }

    // Only verified writes can be undone, so an unverified paste asks the user to take a look.
    private var successLabel: String {
        appState.canUndoLastWrite
            ? appState.text("已输入", "Inserted")
            : appState.text("已输入，请核对", "Inserted. Check it.")
    }

    var body: some View {
        HStack(spacing: 8) {
            switch appState.dictationPhase {
            case .idle:
                EmptyView()
            case .listening:
                PillCancelButton(
                    label: appState.text("取消语音输入", "Cancel Voice Input"),
                    action: appState.cancelDictation
                )
                Waveform(color: KukuColor.coral.opacity(0.82), level: appState.inputLevel, barCount: 6, height: 16)
                Text(listeningLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                PillConfirmButton(
                    label: appState.text("结束录音并输入", "Stop recording and insert"),
                    action: appState.finishDictation
                )
            case .processing:
                ProgressView().controlSize(.small)
                Text(processingLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                PillCancelButton(
                    label: appState.text("取消语音输入", "Cancel Voice Input"),
                    action: appState.cancelDictation
                )
            case .success:
                Image(systemName: "checkmark")
                Text(successLabel)
                if appState.canUndoLastWrite {
                    Spacer(minLength: 0)
                    Button(appState.text("撤销", "Undo")) {
                        Task { await appState.undoLastWrite() }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(KukuColor.coral)
                }
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
    @State private var hovering = false

    static func width(_ appState: AppState) -> CGFloat {
        KukuPillLayout.width(for: status(appState), minimum: 180, fixedContentWidth: 96)
    }

    private static func status(_ appState: AppState) -> String {
        appState.hasCopiedPendingText
            ? appState.text("已复制，按 ⌘V 粘贴", "Copied. Press ⌘V to paste.")
            : appState.text("点按复制结果", "Click to copy")
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: appState.copyPendingText) {
                HStack(spacing: 6) {
                    Image(systemName: appState.hasCopiedPendingText ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(KukuColor.coral.opacity(0.82))
                        .contentTransition(.symbolEffect(.replace))
                    Text(Self.status(appState))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(appState.pendingCopyText)
            .accessibilityLabel(Self.status(appState))
            .accessibilityValue(appState.pendingCopyText)
            Spacer(minLength: 4)
            Button(action: appState.dismissCopyFallback) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 25, height: 25)
                    .background(KukuColor.shade.opacity(0.05), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(appState.text("关闭", "Close"))
            .help(appState.text("关闭", "Close"))
        }
        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
        .foregroundStyle(KukuColor.ink.opacity(0.76))
        .frame(maxWidth: .infinity)
        .onHover { hovering = $0 }
        .task(id: hovering) {
            // Collapse after a quiet period; stay while hovered or when VoiceOver needs time to read it.
            guard !hovering, !NSWorkspace.shared.isVoiceOverEnabled else { return }
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            guard appState.dictationPhase == .copyReady || appState.agentPhase == .copyReady else { return }
            appState.dismissCopyFallback()
        }
    }
}
