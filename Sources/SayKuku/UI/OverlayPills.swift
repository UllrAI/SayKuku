import AppKit
import SwiftUI

// Each phase's status is the pill's text without live input, and what VoiceOver
// announces when the overlay changes (see `FloatingSystemOverlay`).

extension VoiceWorkflow.AgentPhase {
    @MainActor func status(_ workflow: VoiceWorkflow) -> String? {
        switch self {
        case .hidden, .answerReady:
            return nil
        case .listening:
            return localized("Listening…")
        case .transcribing:
            return localized("Understanding…")
        case .processing:
            // `agentCommand` holds the understood task by now, unless there was none.
            let task = workflow.agentCommand.trimmingCharacters(in: .whitespacesAndNewlines)
            return task.isEmpty || task == Self.listening.status(workflow)
                ? localized("Running…")
                : localized("Running · \(task)")
        case .result:
            return localized("Done (status)")
        case .copyReady:
            return CopyFallbackContent.status(workflow)
        }
    }
}

extension VoiceWorkflow.DictationPhase {
    @MainActor func status(_ workflow: VoiceWorkflow) -> String? {
        switch self {
        case .idle: nil
        case .listening: localized("Listening…")
        case .processing: localized("Transcribing…")
        case .success: localized("Inserted")
        case .copyReady: CopyFallbackContent.status(workflow)
        }
    }
}

/// Keeps the same pill on screen when a second Fn tap turns dictation into Agent.
struct RecordingPill: View {
    @Environment(AppState.self) private var appState
    @State private var showingContext = false

    private var isAgent: Bool { appState.workflow.agentPhase == .listening }
    private var width: CGFloat {
        KukuPillLayout.width(for: localized("Listening…"), minimum: 208, fixedContentWidth: 140)
    }

    var body: some View {
        HStack(spacing: KukuSpacing.sm) {
            PillCancelButton(
                label: isAgent ? localized("Cancel Voice Agent") : localized("Cancel Voice Input"),
                action: isAgent ? appState.workflow.dismissAgent : appState.workflow.cancelDictation
            )

            HStack(spacing: KukuSpacing.xs) {
                if isAgent {
                    Button { showingContext.toggle() } label: {
                        Image(systemName: "sparkle")
                            .font(.kukuIcon(.regular, weight: .semibold))
                            .foregroundStyle(KukuColor.coral)
                            .frame(width: 16, height: 22)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                    .accessibilityLabel(localized("Review what’s sent"))
                    .help(localized("Review what’s sent"))
                    .popover(isPresented: $showingContext, arrowEdge: .bottom) {
                        AgentContextPopover()
                    }
                } else {
                    Color.clear.frame(width: 16, height: 22)
                        .accessibilityHidden(true)
                }

                Waveform(color: KukuColor.coral, level: appState.workflow.inputLevel, barCount: 5, height: 15)
                    .frame(width: 22)
            }

            Text(localized("Listening…"))
                .font(.kuku(.callout, weight: .semibold))
                .foregroundStyle(KukuColor.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            PillConfirmButton(
                label: isAgent ? localized("Stop recording and run") : localized("Stop recording and insert"),
                action: isAgent ? appState.workflow.finishAgentListening : appState.workflow.finishDictation
            )
        }
        .padding(.horizontal, KukuSpacing.sm)
        .frame(width: width)
        .frame(minHeight: KukuLayout.pillHeight)
        .kukuGlassPill()
        .animation(Motion.snappy, value: isAgent)
    }
}

struct AgentPill: View {
    @Environment(AppState.self) private var appState
    private var width: CGFloat {
        switch appState.workflow.agentPhase {
        case .hidden, .listening: 0
        case .copyReady:
            CopyFallbackContent.width(appState.workflow)
        case .answerReady:
            0
        case .transcribing:
            KukuPillLayout.width(for: status, minimum: 145, fixedContentWidth: 82, maximum: 233)
        case .processing:
            KukuPillLayout.width(for: status, minimum: 145, fixedContentWidth: 82)
        case .result:
            KukuPillLayout.width(for: status, minimum: 78, fixedContentWidth: appState.workflow.resultCanUndo ? 96 : 38, maximum: 200)
        }
    }

    private var status: String {
        appState.workflow.agentPhase.status(appState.workflow) ?? ""
    }

    var body: some View {
        HStack(spacing: KukuSpacing.sm) {
            if appState.workflow.agentPhase == .copyReady {
                CopyFallbackContent()
            } else if appState.workflow.agentPhase == .transcribing || appState.workflow.agentPhase == .processing {
                AgentActivityIndicator()
                Text(status)
                    .font(.kuku(.callout, weight: .semibold))
                    .foregroundStyle(KukuColor.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                PillCancelButton(
                    label: localized("Cancel Voice Agent"),
                    action: appState.workflow.dismissAgent
                )
            } else if appState.workflow.agentPhase == .result {
                Label {
                    Text(status)
                } icon: {
                    Image(systemName: "checkmark")
                        .foregroundStyle(KukuColor.success)
                }
                .font(.kuku(.callout, weight: .semibold))
                .foregroundStyle(KukuColor.textSecondary)
                .lineLimit(1)
                if appState.workflow.resultCanUndo {
                    Spacer(minLength: 0)
                    PillUndoButton()
                }
            }
        }
        .contentTransition(.interpolate)
        .animation(Motion.snappy, value: appState.workflow.agentPhase)
        .padding(.horizontal, KukuSpacing.sm)
        .frame(width: width)
        .frame(minHeight: KukuLayout.pillHeight)
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
        Button(localized("Undo")) {
            Task { await appState.workflow.undoLastWrite() }
        }
        .buttonStyle(.plain)
        .font(.kuku(.callout, weight: .semibold))
        .foregroundStyle(KukuColor.accentText)
        .disabled(appState.workflow.isWriting)
        .opacity(appState.workflow.isWriting ? KukuState.disabledOpacity : 1)
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
            Text(localized("What’s sent"))
                .font(.kuku(.subheadline, weight: .semibold))
                .foregroundStyle(KukuColor.textSecondary)

            ScrollView {
                VStack(alignment: .leading, spacing: KukuSpacing.md) {
                    if appState.workflow.contextItems.isEmpty {
                        Text(localized("Only your voice will be sent"))
                            .font(.kuku(.callout))
                            .foregroundStyle(KukuColor.textSecondary)
                    }

                    ForEach(appState.workflow.contextItems) { item in
                        VStack(alignment: .leading, spacing: KukuSpacing.xs) {
                            HStack(spacing: KukuSpacing.sm) {
                                Image(systemName: item.symbol)
                                    .font(.kukuIcon(.regular))
                                    .foregroundStyle(KukuColor.textSecondary)
                                    .frame(width: 16)
                                    .accessibilityHidden(true)
                                Text(item.title)
                                    .font(.kuku(.callout, weight: .medium))
                                    .foregroundStyle(KukuColor.textPrimary)
                                Spacer(minLength: 0)
                                if appState.workflow.agentPhase == .listening {
                                    KukuIconButton(
                                        symbol: "xmark",
                                        label: localized("Remove \(item.title)"),
                                        size: .small
                                    ) {
                                        appState.workflow.contextItems.removeAll { $0.id == item.id }
                                    }
                                }
                            }
                            Text(item.value)
                                .font(.kuku(.subheadline))
                                .foregroundStyle(KukuColor.textSecondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 400)
        }
        .padding(KukuSpacing.md)
        .frame(width: 420)
    }
}

struct DictationPill: View {
    @Environment(AppState.self) private var appState

    private var width: CGFloat {
        switch appState.workflow.dictationPhase {
        case .idle, .listening: 0
        case .copyReady:
            CopyFallbackContent.width(appState.workflow)
        case .processing:
            // Padding 2×8, spinner 16, three 8 pt gaps and the 24 pt cancel button.
            KukuPillLayout.width(for: transcriptLabel, minimum: 145, fixedContentWidth: 80, maximum: 340)
        case .success:
            KukuPillLayout.width(for: status, minimum: 78, fixedContentWidth: appState.workflow.canUndoLastWrite ? 100 : 42, maximum: 200)
        }
    }

    private var status: String {
        appState.workflow.dictationPhase.status(appState.workflow) ?? ""
    }

    /// Realtime deltas only arrive once the audio is committed, so live text can replace
    /// the status while transcribing but never while listening.
    private var transcriptLabel: String {
        appState.workflow.liveTranscript.isEmpty ? status : appState.workflow.liveTranscript
    }

    var body: some View {
        HStack(spacing: KukuSpacing.sm) {
            switch appState.workflow.dictationPhase {
            case .idle:
                EmptyView()
            case .listening:
                EmptyView()
            case .processing:
                ProgressView().controlSize(.small)
                Text(transcriptLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                PillCancelButton(
                    label: localized("Cancel Voice Input"),
                    action: appState.workflow.cancelDictation
                )
            case .success:
                Image(systemName: "checkmark")
                    .foregroundStyle(KukuColor.success)
                Text(status)
                if appState.workflow.canUndoLastWrite {
                    Spacer(minLength: 0)
                    PillUndoButton()
                }
            case .copyReady:
                CopyFallbackContent()
            }
        }
        .contentTransition(.interpolate)
        .animation(Motion.snappy, value: appState.workflow.dictationPhase)
        .animation(Motion.snappy, value: appState.workflow.liveTranscript.isEmpty)
        .font(.kuku(.callout, weight: .semibold))
        .foregroundStyle(appState.workflow.dictationPhase == .success ? KukuColor.textSecondary : KukuColor.textPrimary)
        .padding(.horizontal, KukuSpacing.sm)
        .frame(width: width)
        .frame(minHeight: KukuLayout.pillHeight)
        .kukuGlassPill()
        .animation(Motion.pill, value: width)
    }
}

private struct CopyFallbackContent: View {
    @Environment(AppState.self) private var appState
    @State private var hovering = false

    static func width(_ workflow: VoiceWorkflow) -> CGFloat {
        KukuPillLayout.width(for: status(workflow), minimum: 180, fixedContentWidth: 96)
    }

    static func status(_ workflow: VoiceWorkflow) -> String {
        workflow.hasCopiedPendingText
            ? localized("Copied. Press ⌘V to paste.")
            : localized("Click to copy")
    }

    var body: some View {
        HStack(spacing: KukuSpacing.sm) {
            Button(action: appState.workflow.copyPendingText) {
                HStack(spacing: KukuSpacing.iconText) {
                    Image(systemName: appState.workflow.hasCopiedPendingText ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(appState.workflow.hasCopiedPendingText ? KukuColor.success : KukuColor.textSecondary)
                        .contentTransition(.symbolEffect(.replace))
                    Text(Self.status(appState.workflow))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(appState.workflow.pendingCopyText)
            .accessibilityLabel(Self.status(appState.workflow))
            .accessibilityValue(appState.workflow.pendingCopyText)
            Spacer(minLength: KukuSpacing.xs)
            PillCancelButton(label: localized("Close"), action: appState.workflow.dismissCopyFallback)
        }
        .font(.kuku(.callout, weight: .semibold))
        .foregroundStyle(KukuColor.textPrimary)
        .frame(maxWidth: .infinity)
        .onHover { hovering = $0 }
        .task(id: hovering) {
            // Collapse after a quiet period; stay while hovered or when VoiceOver needs time to read it.
            guard !hovering, !NSWorkspace.shared.isVoiceOverEnabled else { return }
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            guard appState.workflow.dictationPhase == .copyReady || appState.workflow.agentPhase == .copyReady else { return }
            appState.workflow.dismissCopyFallback()
        }
    }
}
