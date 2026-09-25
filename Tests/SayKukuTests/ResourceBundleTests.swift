import Foundation
import Testing
@testable import SayKuku

@Suite("Resource bundle")
struct ResourceBundleTests {
    @Test("brand icons resolve")
    func brandIcons() {
        #expect(Bundle.appResources.url(forResource: "SayKuku", withExtension: "svg") != nil)
        #expect(Bundle.appResources.url(forResource: "MenuBarIcon", withExtension: "svg") != nil)
    }
}
