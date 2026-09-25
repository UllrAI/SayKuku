import SwiftUI
import Testing
@testable import SayKuku

@Suite("Typography")
struct TypographyTests {
    @Test("text roles map onto system text styles so they follow Text Size")
    func textStyleMapping() {
        let expected: [(KukuTextStyle, Font.TextStyle)] = [
            (.largeTitle, .title),
            (.title, .title2),
            (.title3, .title3),
            (.headline, .body),
            (.body, .body),
            (.callout, .callout),
            (.subheadline, .subheadline),
            (.caption, .footnote),
        ]

        for (style, textStyle) in expected {
            #expect(style.textStyle == textStyle)
        }
    }
}
