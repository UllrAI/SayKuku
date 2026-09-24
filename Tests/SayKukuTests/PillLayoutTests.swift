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

    @Test("long error copy caps at a width that fits the overlay panel")
    func longErrorWidth() {
        let width = KukuPillLayout.errorWidth(
            for: "The request timed out. Check your network connection and Qwen region, then try again."
        )
        let panelWidth = FloatingOverlayController.panelSize(answerVisible: false).width

        #expect(width == 340)
        #expect(width < panelWidth)
    }
}
