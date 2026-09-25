import AppKit
import Testing
@testable import SayKuku

@Suite("Pill layout")
struct PillLayoutTests {
    @Test("width follows rendered text length")
    func textDrivenWidth() {
        let short = KukuPillLayout.width(for: "好", minimum: 78, fixedContentWidth: 38)
        let medium = KukuPillLayout.width(for: "已完成 · 打开链接", minimum: 78, fixedContentWidth: 38)

        #expect(short < medium)
    }

    @Test("width respects compact and expanded bounds")
    func widthBounds() {
        let compact = KukuPillLayout.width(for: "", minimum: 78, fixedContentWidth: 38, maximum: 320)
        let expanded = KukuPillLayout.width(
            for: String(repeating: "很长的任务描述", count: 20),
            minimum: 78,
            fixedContentWidth: 38,
            maximum: 320
        )

        #expect(compact == 78)
        #expect(expanded == 320)
    }

    @Test("short error copy keeps a compact pill")
    func compactErrorWidth() {
        let width = KukuPillLayout.errorWidth(for: "没有听清，请重试")

        #expect(width >= 120)
        #expect(width < 200)
    }

    @Test("buttons after a message get their own room within the same cap")
    func errorWidthWithButtons() {
        let message = "把“张月”记为“张越”？"
        let plain = KukuPillLayout.errorWidth(for: message)
        let withButtons = KukuPillLayout.errorWidth(for: message, buttons: ["暂不", "记住"])

        #expect(withButtons > plain)
        #expect(withButtons <= 340)
    }

    @Test("long error copy caps at a width that fits the overlay panel")
    func longErrorWidth() {
        let width = KukuPillLayout.errorWidth(
            for: "The request timed out. Check your network connection and Qwen region, then try again."
        )
        let panelWidth = FloatingOverlayController.panelSize(answerHeight: nil).width

        #expect(width == 340)
        #expect(width < panelWidth)
    }
}

@Suite("Overlay layout")
struct OverlayLayoutTests {
    /// A screen whose Dock takes the bottom 70 pt.
    private let visibleFrame = CGRect(x: 0, y: 70, width: 1440, height: 805)
    private let pillSize = CGSize(width: 380, height: 92)

    @Test("defaults to the bottom center of the visible frame")
    func bottomCenter() {
        let origin = OverlayLayout.origin(
            placement: .bottom, caretFrame: nil, visibleFrame: visibleFrame, panelSize: pillSize, contentHeight: 36
        )

        #expect(origin == CGPoint(x: 530, y: 78))
    }

    @Test("top placement puts the content just below the menu bar")
    func topCenter() {
        let pill = OverlayLayout.origin(
            placement: .top, caretFrame: nil, visibleFrame: visibleFrame, panelSize: pillSize, contentHeight: 36
        )
        let card = OverlayLayout.origin(
            placement: .top, caretFrame: nil, visibleFrame: visibleFrame,
            panelSize: CGSize(width: 460, height: 190), contentHeight: 160
        )

        #expect(pill == CGPoint(x: 530, y: 875 - 8 - 16 - 36))
        #expect(pill.y + 16 + 36 == visibleFrame.maxY - 8)
        #expect(card == CGPoint(x: 490, y: 875 - 8 - 16 - 160))
    }

    @Test("bottom and top placements ignore the caret")
    func placementIgnoresCaret() {
        let caret = CGRect(x: 700, y: 500, width: 2, height: 18)
        let bottom = OverlayLayout.origin(
            placement: .bottom, caretFrame: caret, visibleFrame: visibleFrame, panelSize: pillSize, contentHeight: 36
        )
        let top = OverlayLayout.origin(
            placement: .top, caretFrame: caret, visibleFrame: visibleFrame, panelSize: pillSize, contentHeight: 36
        )

        #expect(bottom == CGPoint(x: 530, y: 78))
        #expect(top == CGPoint(x: 530, y: 815))
    }

    @Test("sits below the caret, centered on it")
    func belowCaret() {
        let origin = OverlayLayout.origin(
            placement: .caret, caretFrame: CGRect(x: 700, y: 500, width: 2, height: 18),
            visibleFrame: visibleFrame, panelSize: pillSize, contentHeight: 36
        )

        #expect(origin == CGPoint(x: 511, y: 500 - 12 - 16 - 36))
    }

    @Test("moves above the caret when there's no room below")
    func aboveCaret() {
        let origin = OverlayLayout.origin(
            placement: .caret, caretFrame: CGRect(x: 700, y: 100, width: 2, height: 18),
            visibleFrame: visibleFrame, panelSize: pillSize, contentHeight: 36
        )

        #expect(origin == CGPoint(x: 511, y: 118 + 12 - 16))
    }

    @Test("stays inside the visible frame near a screen edge")
    func clampedToScreen() {
        let right = OverlayLayout.origin(
            placement: .caret, caretFrame: CGRect(x: 1430, y: 500, width: 2, height: 18),
            visibleFrame: visibleFrame, panelSize: pillSize, contentHeight: 36
        )
        let left = OverlayLayout.origin(
            placement: .caret, caretFrame: CGRect(x: 4, y: 500, width: 2, height: 18),
            visibleFrame: visibleFrame, panelSize: pillSize, contentHeight: 36
        )

        #expect(right.x == 1440 - 380)
        #expect(left.x == 0)
    }

    @Test("following the cursor falls back to the bottom center without a caret")
    func caretFallback() {
        let origin = OverlayLayout.origin(
            placement: .caret, caretFrame: nil, visibleFrame: visibleFrame, panelSize: pillSize, contentHeight: 36
        )

        #expect(origin == CGPoint(x: 530, y: 78))
    }

    @Test("answer card grows with its text within its height bounds")
    func answerCardHeight() {
        let font = NSFont.systemFont(ofSize: 13)
        let short = OverlayLayout.answerCardHeight(for: "好的。", font: font)
        let long = OverlayLayout.answerCardHeight(
            for: String(repeating: "这是一段很长的回答，用来测试卡片高度。", count: 60), font: font
        )

        #expect(short < long)
        #expect(short == OverlayLayout.answerCardHeights.lowerBound)
        #expect(long == OverlayLayout.answerCardHeights.upperBound)
    }
}
