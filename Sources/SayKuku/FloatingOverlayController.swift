import AppKit
import SwiftUI

@MainActor
final class FloatingOverlayController {
    private let panel: NSPanel
    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 92),
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
                .preferredColorScheme(.light)
        )
    }

    func refresh() {
        guard let appState else { return }
        let shouldShow = appState.dictationPhase != .idle || appState.agentPhase != .hidden

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
            y: visibleFrame.minY + 22
        )
        panel.setFrameOrigin(origin)
    }
}

private struct FloatingSystemOverlay: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear

            if appState.agentPhase != .hidden {
                AgentPill()
                    .transition(.scale(scale: 0.88, anchor: .bottom).combined(with: .opacity))
            } else if appState.dictationPhase != .idle {
                DictationPill()
                    .transition(.scale(scale: 0.88, anchor: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: 380, height: 92)
        .animation(Motion.panel, value: appState.agentPhase)
        .animation(Motion.panel, value: appState.dictationPhase)
    }
}
