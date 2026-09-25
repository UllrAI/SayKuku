import AppKit
import SwiftUI

@MainActor
final class FloatingOverlayController {
    private let panel: NSPanel
    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState

        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize(answerVisible: false)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.title = "SayKuku Voice Overlay"
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(
            rootView: FloatingSystemOverlay()
                .environment(appState)
        )
    }

    /// Shared by the panel and its SwiftUI root so both always agree on the overlay bounds.
    nonisolated static func panelSize(answerVisible: Bool) -> NSSize {
        answerVisible ? NSSize(width: 460, height: 300) : NSSize(width: 380, height: 92)
    }

    func refresh() {
        guard let appState else { return }
        // Set here so the label follows the current UI language.
        panel.setAccessibilityLabel(appState.text("SayKuku 语音浮层", "SayKuku voice overlay"))
        panel.setContentSize(Self.panelSize(answerVisible: appState.agentPhase == .answerReady))
        let shouldShow = appState.overlayError != nil
            || appState.dictationPhase != .idle
            || appState.agentPhase != .hidden

        if shouldShow {
            positionOnActiveScreen()
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    private func positionOnActiveScreen() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else { return }

        let origin = NSPoint(
            x: visibleFrame.midX - panel.frame.width / 2,
            y: visibleFrame.minY + 8
        )
        panel.setFrameOrigin(origin)
    }
}

private struct FloatingSystemOverlay: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let size = FloatingOverlayController.panelSize(answerVisible: appState.agentPhase == .answerReady)
        ZStack(alignment: .bottom) {
            Color.clear

            if appState.agentPhase == .answerReady {
                AgentAnswerCard()
                    .transition(.scale(scale: 0.96, anchor: .bottom).combined(with: .opacity))
            } else if let error = appState.overlayError {
                // A calm notice, not an alarm: neutral icon, primary text.
                Label {
                    Text(error)
                        .foregroundStyle(KukuColor.textPrimary)
                } icon: {
                    Image(systemName: appState.overlayErrorSymbol)
                        .foregroundStyle(KukuColor.textSecondary)
                }
                .font(.kuku(.callout, weight: .medium))
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, KukuSpacing.md)
                .padding(.vertical, KukuSpacing.sm)
                .frame(width: KukuPillLayout.errorWidth(for: error))
                .frame(minHeight: KukuLayout.controlHeight)
                .kukuGlassPill()
                .transition(.scale(scale: 0.94, anchor: .bottom).combined(with: .opacity))
            } else if appState.agentPhase != .hidden {
                AgentPill()
                    .transition(.scale(scale: 0.94, anchor: .bottom).combined(with: .opacity))
            } else if appState.dictationPhase != .idle {
                DictationPill()
                    .transition(.scale(scale: 0.94, anchor: .bottom).combined(with: .opacity))
            }
        }
        .padding(.bottom, KukuSpacing.lg)
        .frame(width: size.width, height: size.height)
        .animation(Motion.panel, value: appState.agentPhase)
        .animation(Motion.panel, value: appState.dictationPhase)
        .animation(Motion.panel, value: appState.overlayError)
    }
}

private struct AgentAnswerCard: View {
    @Environment(AppState.self) private var appState

    /// Title, icon, hint and primary button: the card shows an answer or asks before a link or shortcut runs.
    private var labels: (title: String, symbol: String, hint: String, primary: String) {
        switch appState.pendingAction?.action {
        case .openURL:
            (appState.text("打开这个网址？", "Open this link?"), "link",
             appState.text("先核对网址，再决定是否打开", "Check the address before you open it"),
             appState.text("打开", "Open"))
        case .runShortcut:
            (appState.text("运行这个快捷指令？", "Run this shortcut?"), "square.stack.3d.up",
             appState.text("确认这是你要运行的快捷指令", "Make sure this is the shortcut you meant"),
             appState.text("运行", "Run"))
        default:
            (appState.text("回答", "Answer"), "sparkles",
             appState.text("可复制，或写入刚才的输入位置", "Copy it, or insert it where you were typing"),
             appState.text("写入", "Insert"))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KukuSpacing.md) {
            HStack {
                Label {
                    Text(labels.title)
                        .foregroundStyle(KukuColor.textPrimary)
                } icon: {
                    Image(systemName: labels.symbol)
                        .foregroundStyle(KukuColor.textSecondary)
                }
                .font(.kuku(.headline))
                Spacer()
                KukuIconButton(symbol: "xmark", label: appState.text("关闭", "Close"), action: appState.dismissAnswer)
            }
            ScrollView {
                Text(appState.pendingAnswerText)
                    .font(.kuku(.body))
                    .foregroundStyle(KukuColor.textPrimary)
                    .lineSpacing(KukuTypography.paragraphSpacing)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            HStack {
                Text(appState.pendingAnswerStatus ?? labels.hint)
                    .font(.kuku(.subheadline))
                    .foregroundStyle(KukuColor.textSecondary)
                    .lineLimit(2)
                Spacer()
                Button(appState.text("复制", "Copy"), action: appState.copyAnswer)
                    .buttonStyle(.kukuSecondary)
                Button(labels.primary) {
                    if appState.pendingAction == nil {
                        Task { await appState.insertAnswer() }
                    } else {
                        appState.confirmPendingAction()
                    }
                }
                .buttonStyle(.kukuPrimary)
                .disabled(appState.isWriting)
            }
        }
        .padding(KukuLayout.cardPadding)
        // Leaves room inside the answer panel (see `panelSize`) for the card shadow.
        .frame(width: 440, height: 270)
        .kukuSurface(radius: KukuLayout.radiusLarge, elevated: true, fill: KukuColor.overlaySurface)
    }
}
