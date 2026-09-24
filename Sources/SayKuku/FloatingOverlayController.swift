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
        panel.setAccessibilityLabel("SayKuku Voice Overlay")
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
                Label(error, systemImage: appState.overlayErrorSymbol)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(KukuColor.ink.opacity(0.72))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(width: KukuPillLayout.errorWidth(for: error))
                    .frame(minHeight: 32)
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
        .padding(.bottom, 16)
        .frame(width: size.width, height: size.height)
        .animation(Motion.panel, value: appState.agentPhase)
        .animation(Motion.panel, value: appState.dictationPhase)
        .animation(Motion.panel, value: appState.overlayError)
    }
}

private struct AgentAnswerCard: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(appState.text("语音 Agent 的回答", "Voice Agent answer"), systemImage: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button(action: appState.dismissAnswer) {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(appState.text("关闭回答", "Close answer"))
            }
            ScrollView {
                Text(appState.pendingAnswerText)
                    .font(.system(size: 13))
                    .foregroundStyle(KukuColor.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            HStack {
                Text(appState.pendingAnswerStatus ?? appState.text("回答未写入当前应用", "The answer has not been inserted"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(KukuColor.stone)
                Spacer()
                Button(appState.text("复制", "Copy"), action: appState.copyAnswer)
                    .buttonStyle(TintButtonStyle())
                Button(appState.text("写入", "Insert")) {
                    Task { await appState.insertAnswer() }
                }
                .buttonStyle(HoverFillButtonStyle(prominent: true))
            }
        }
        .padding(18)
        .frame(width: 440, height: 270)
        .kukuSurface(radius: KukuLayout.radiusLarge, elevated: true, fill: KukuColor.overlaySurface)
    }
}
