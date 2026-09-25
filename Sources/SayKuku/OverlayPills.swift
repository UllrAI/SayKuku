import AppKit
import SwiftUI

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
            KukuPillLayout.width(for: transcribingLabel, minimum: 145, fixedContentWidth: 82, maximum: 233)
        case .processing:
            KukuPillLayout.width(for: processingLabel, minimum: 145, fixedContentWidth: 82)
        case .result:
            KukuPillLayout.width(for: resultLabel, minimum: 78, fixedContentWidth: appState.resultCanUndo ? 96 : 38, maximum: 200)
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
        appState.text("已完成", "Done")
    }

    var body: some View {
        HStack(spacing: KukuSpacing.sm) {
            if appState.agentPhase == .copyReady {
                CopyFallbackContent()
            } else if appState.agentPhase == .listening {
                PillCancelButton(
                    label: appState.text("取消语音 Agent", "Cancel Voice Agent"),
                    action: appState.dismissAgent
                )

                // Fixed-size glyphs below are counted in the listening `fixedContentWidth`.
                HStack(spacing: KukuSpacing.xs) {
                    Button { showingContext.toggle() } label: {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.kukuIcon(.small, weight: .semibold))
                            .foregroundStyle(KukuColor.textSecondary)
                            .frame(width: 16, height: 22)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(appState.text("查看本次会发送的内容", "Review what’s sent"))
                    .help(appState.text("查看本次会发送的内容", "Review what’s sent"))
                    .popover(isPresented: $showingContext, arrowEdge: .bottom) {
                        AgentContextPopover()
                    }

                    Waveform(
                        color: KukuColor.coral,
                        level: appState.inputLevel,
                        barCount: 5,
                        height: 15
                    )
                    .frame(width: 22)
                }

                Text(listeningLabel)
                    .font(.kuku(.callout, weight: .semibold))
                    .foregroundStyle(KukuColor.textPrimary)
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
                    .font(.kuku(.callout, weight: .semibold))
                    .foregroundStyle(KukuColor.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                PillCancelButton(
                    label: appState.text("取消语音 Agent", "Cancel Voice Agent"),
                    action: appState.dismissAgent
                )
            } else if appState.agentPhase == .result {
                Label {
                    Text(resultLabel)
                } icon: {
                    Image(systemName: "checkmark")
                        .foregroundStyle(KukuColor.success)
                }
                .font(.kuku(.callout, weight: .semibold))
                .foregroundStyle(KukuColor.textSecondary)
                .lineLimit(1)
                if appState.resultCanUndo {
                    Spacer(minLength: 0)
                    PillUndoButton()
                }
            }
        }
        .contentTransition(.interpolate)
        .animation(Motion.snappy, value: appState.agentPhase)
        .animation(Motion.snappy, value: appState.liveTranscript.isEmpty)
        .padding(.horizontal, KukuSpacing.sm)
        .frame(width: width, height: KukuLayout.pillHeight)
        .kukuGlassPill()
        .animation(Motion.pill, value: width)
    }
}

/// Spins and pulses while the agent works; holds still when Reduce Motion is on.
private struct AgentActivityIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                icon
            } else {
                TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                    let progress = timeline.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 1.6) / 1.6
                    let pulse = 0.76 + 0.24 * (0.5 - 0.5 * cos(progress * 2 * .pi))

                    icon
                        .rotationEffect(.degrees(progress * 180))
                        .scaleEffect(pulse)
                }
            }
        }
        // Fixed so the rotating symbol never nudges the pill layout; part of `fixedContentWidth`.
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }

    private var icon: some View {
        Image(systemName: "sparkle")
            .font(.kukuIcon(.regular, weight: .semibold))
            .foregroundStyle(KukuColor.coral)
    }
}

/// Reverts the last verified write. The only accent-colored text in a pill.
private struct PillUndoButton: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Button(appState.text("撤销", "Undo")) {
            Task { await appState.undoLastWrite() }
        }
        .buttonStyle(.plain)
        .font(.kuku(.callout, weight: .semibold))
        .foregroundStyle(KukuColor.accentText)
        .disabled(appState.isWriting)
        .opacity(appState.isWriting ? KukuState.disabledOpacity : 1)
    }
}

/// Cancels recording or processing; nothing is written afterwards.
private struct PillCancelButton: View {
    let label: String
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.kukuIcon(.mini, weight: .semibold))
                .foregroundStyle(KukuColor.textSecondary)
                .frame(width: KukuLayout.pillButton, height: KukuLayout.pillButton)
                .background(KukuColor.fill, in: Circle())
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
                .font(.kukuIcon(.mini, weight: .semibold))
                .foregroundStyle(KukuColor.onAccent)
                .frame(width: KukuLayout.pillButton, height: KukuLayout.pillButton)
                .background(KukuColor.accentFill, in: Circle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(label)
        .help(label)
    }
}

private struct AgentContextPopover: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: KukuSpacing.sm) {
            Text(appState.text("本次会发送的内容", "What’s sent"))
                .font(.kuku(.subheadline, weight: .semibold))
                .foregroundStyle(KukuColor.textSecondary)

            if appState.contextItems.isEmpty {
                Text(appState.text("本次只发送你的语音", "Only your voice will be sent"))
                    .font(.kuku(.callout))
                    .foregroundStyle(KukuColor.textSecondary)
            }

            ForEach(appState.contextItems) { item in
                HStack(spacing: KukuSpacing.sm) {
                    Image(systemName: item.symbol)
                        .font(.kukuIcon(.regular))
                        .foregroundStyle(KukuColor.textSecondary)
                        // Fixed icon column so titles line up.
                        .frame(width: 16)
                    Text(item.title)
                        .font(.kuku(.callout, weight: .medium))
                        .foregroundStyle(KukuColor.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    if appState.agentPhase == .listening {
                        KukuIconButton(
                            symbol: "xmark",
                            label: appState.text("移除“\(item.title)”", "Remove \(item.title)"),
                            size: .small
                        ) {
                            appState.contextItems.removeAll { $0.id == item.id }
                        }
                    }
                }
                .help(Self.preview(of: item) ?? "")
            }
        }
        .padding(KukuSpacing.md)
        // Narrow enough to sit above the pill; long titles truncate.
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
            KukuPillLayout.width(for: listeningLabel, minimum: 160, fixedContentWidth: 135, maximum: 340)
        case .copyReady:
            CopyFallbackContent.width(appState)
        case .processing:
            // Padding 2×8, spinner 16, three 8 pt gaps and the 24 pt cancel button.
            KukuPillLayout.width(for: processingLabel, minimum: 145, fixedContentWidth: 80, maximum: 340)
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

    private var successLabel: String {
        appState.text("已输入", "Inserted")
    }

    var body: some View {
        HStack(spacing: KukuSpacing.sm) {
            switch appState.dictationPhase {
            case .idle:
                EmptyView()
            case .listening:
                PillCancelButton(
                    label: appState.text("取消语音输入", "Cancel Voice Input"),
                    action: appState.cancelDictation
                )
                Waveform(color: KukuColor.coral, level: appState.inputLevel, barCount: 6, height: 16)
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
                    .foregroundStyle(KukuColor.success)
                Text(successLabel)
                if appState.canUndoLastWrite {
                    Spacer(minLength: 0)
                    PillUndoButton()
                }
            case .copyReady:
                CopyFallbackContent()
            }
        }
        .contentTransition(.interpolate)
        .animation(Motion.snappy, value: appState.dictationPhase)
        .animation(Motion.snappy, value: appState.liveTranscript.isEmpty)
        .font(.kuku(.callout, weight: .semibold))
        .foregroundStyle(appState.dictationPhase == .success ? KukuColor.textSecondary : KukuColor.textPrimary)
        .padding(.horizontal, KukuSpacing.sm)
        .frame(width: width, height: KukuLayout.pillHeight)
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
        HStack(spacing: KukuSpacing.sm) {
            Button(action: appState.copyPendingText) {
                HStack(spacing: KukuSpacing.iconText) {
                    Image(systemName: appState.hasCopiedPendingText ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(appState.hasCopiedPendingText ? KukuColor.success : KukuColor.textSecondary)
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
            Spacer(minLength: KukuSpacing.xs)
            PillCancelButton(label: appState.text("关闭", "Close"), action: appState.dismissCopyFallback)
        }
        .font(.kuku(.callout, weight: .semibold))
        .foregroundStyle(KukuColor.textPrimary)
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
