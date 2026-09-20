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
}
