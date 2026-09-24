import Foundation
import Testing
@testable import SayKuku

@Suite("App state")
struct AppStateTests {
    @Test("main navigation titles follow the selected language")
    @MainActor
    func navigationLocalization() {
        let environment = AppStateTestEnvironment()
        defer { environment.clean() }
        let state = environment.makeState()
        state.appLanguage = .chinese
        #expect(AppState.Destination.knowledge.title(state) == "知识")
        #expect(state.voiceInputTitle == "语音输入")
        #expect(state.voiceAgentTitle == "语音 Agent")
        state.appLanguage = .english
        #expect(AppState.Destination.knowledge.title(state) == "Knowledge")
        #expect(state.voiceInputTitle == "Voice Input")
        #expect(state.voiceAgentTitle == "Voice Agent")
    }

    @Test("toasts with the same copy are still distinct")
    func toastIdentity() {
        #expect(ToastMessage(text: "已复制", symbol: "doc.on.doc") != ToastMessage(text: "已复制", symbol: "doc.on.doc"))
    }
}
