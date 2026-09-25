import AppKit
import SwiftUI

@MainActor
final class FloatingOverlayController {
    private let panel: NSPanel
    private weak var appState: AppState?
    /// Where the target was when the current workflow began. The overlay stays there until the
    /// next workflow, even if the mouse moves to another screen.
    private var caretFrame: CGRect?
    private var windowFrame: CGRect?
    private var visibleFrame: CGRect?

    init(appState: AppState) {
        self.appState = appState

        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize(answerHeight: nil)),
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
    /// `answerHeight` is the answer card's height, or nil while a pill shows. The answer panel
    /// leaves room around the card for its shadow.
    nonisolated static func panelSize(answerHeight: CGFloat?) -> NSSize {
        guard let answerHeight else { return NSSize(width: 380, height: 92) }
        return NSSize(width: OverlayLayout.answerCardWidth + 20, height: answerHeight + 30)
    }

    /// Called once per workflow, when its target is captured. Errors before that reuse the last anchor.
    func anchor(to snapshot: TextTargetSnapshot) {
        caretFrame = snapshot.caretFrame
        windowFrame = snapshot.windowFrame
        let screen = (caretFrame ?? windowFrame).flatMap { target in
            NSScreen.screens.first { $0.frame.contains(CGPoint(x: target.midX, y: target.midY)) }
        } ?? NSScreen.main
        visibleFrame = screen?.visibleFrame
    }

    func refresh() {
        guard let appState else { return }
        // Set here so the label follows the current UI language.
        panel.setAccessibilityLabel(appState.text("SayKuku 语音浮层", "SayKuku voice overlay"))
        let shouldShow = appState.overlayError != nil
            || appState.dictationPhase != .idle
            || appState.agentPhase != .hidden

        if shouldShow {
            let answerHeight = appState.agentPhase == .answerReady ? appState.answerCardHeight : nil
            place(size: Self.panelSize(answerHeight: answerHeight))
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    /// Sizes the panel and keeps it on the anchor; resizing alone would grow it from its bottom-left corner.
    private func place(size: NSSize) {
        // Before the first workflow there is no anchor yet.
        guard let visibleFrame = visibleFrame ?? NSScreen.main?.visibleFrame else { return }
        let origin = OverlayLayout.origin(
            caretFrame: caretFrame, windowFrame: windowFrame, visibleFrame: visibleFrame, panelSize: size
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

/// Overlay geometry in AppKit screen coordinates, where y grows upward.
enum OverlayLayout {
    /// Space between the caret and the panel.
    static let caretGap: CGFloat = 12
    /// Space between the panel and the bottom of the window or screen it sits on.
    static let bottomInset: CGFloat = 8
    static let answerCardWidth: CGFloat = 440
    static let answerCardHeights: ClosedRange<CGFloat> = 160...420
    /// Everything in the answer card besides the answer text: padding above and below, the header
    /// row (its close button is the tallest item), the footer row (its buttons are the tallest) and
    /// the stack spacing on either side of the text.
    static let answerCardChrome: CGFloat = KukuLayout.cardPadding * 2 + KukuLayout.iconButton
        + KukuLayout.controlHeight + KukuSpacing.md * 2

    /// Below the caret, centered on it, or above it when there's no room below. Without a caret,
    /// the bottom center of the target window, then of the screen. Always kept inside `visibleFrame`.
    static func origin(caretFrame: CGRect?, windowFrame: CGRect?, visibleFrame: CGRect, panelSize: CGSize) -> CGPoint {
        var origin: CGPoint
        if let caret = caretFrame {
            origin = CGPoint(x: caret.midX - panelSize.width / 2, y: caret.minY - caretGap - panelSize.height)
            if origin.y < visibleFrame.minY { origin.y = caret.maxY + caretGap }
        } else {
            let base = windowFrame ?? visibleFrame
            origin = CGPoint(x: base.midX - panelSize.width / 2, y: base.minY + bottomInset)
        }
        origin.x = min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - panelSize.width)
        origin.y = min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - panelSize.height)
        return origin
    }

    /// Fits the card to the answer, scrolling only past the maximum height.
    /// `font` matches the card's `.kuku(.body)` text and follows the Text Size setting.
    static func answerCardHeight(
        for text: String, font: NSFont = .preferredFont(forTextStyle: .body)
    ) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = KukuTypography.paragraphSpacing
        let textBounds = NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: paragraph])
            .boundingRect(
                with: NSSize(width: answerCardWidth - KukuLayout.cardPadding * 2, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
        let height = ceil(textBounds.height) + answerCardChrome
        return min(max(height, answerCardHeights.lowerBound), answerCardHeights.upperBound)
    }
}

private struct FloatingSystemOverlay: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let size = FloatingOverlayController.panelSize(
            answerHeight: appState.agentPhase == .answerReady ? appState.answerCardHeight : nil
        )
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
        .onChange(of: announcement) { _, announcement in
            if let announcement { AccessibilityNotification.Announcement(announcement).post() }
        }
    }

    /// The panel never takes focus, so VoiceOver only learns about a change through an announcement.
    /// Follows the phases rather than live text, so a streaming transcript isn't read out word by word.
    private var announcement: String? {
        // Speech while the mic is open would end up in the recording.
        if appState.dictationPhase == .listening || appState.agentPhase == .listening { return nil }
        if appState.agentPhase == .answerReady { return appState.pendingAnswerStatus ?? appState.pendingAnswerText }
        return appState.overlayError
            ?? appState.agentPhase.status(appState)
            ?? appState.dictationPhase.status(appState)
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
        .frame(width: OverlayLayout.answerCardWidth, height: appState.answerCardHeight)
        .kukuSurface(radius: KukuLayout.radiusLarge, elevated: true, fill: KukuColor.overlaySurface)
    }
}
