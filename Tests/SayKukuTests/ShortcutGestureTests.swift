import Carbon.HIToolbox
import Testing
@testable import SayKuku

@Suite("Fn gesture routing")
struct FnGestureRoutingTests {
    @Test("single Fn release stops an active agent before starting dictation")
    func agentStopHasPriority() {
        #expect(ShortcutController.releaseAction(
            wasChorded: false,
            agentIsListening: true,
            dictationIsListening: false
        ) == .finishAgent)
        #expect(!ShortcutController.shouldArmHold(inputMode: .hold, agentIsListening: true, dictationIsListening: false))
        #expect(!ShortcutController.shouldArmHold(inputMode: .tap, agentIsListening: true, dictationIsListening: false))
    }

    @Test("holding Fn during shortcut-started dictation finishes it instead of restarting")
    func holdFinishesListeningDictation() {
        #expect(!ShortcutController.shouldArmHold(inputMode: .hold, agentIsListening: false, dictationIsListening: true))
        #expect(ShortcutController.releaseAction(
            wasChorded: false,
            agentIsListening: false,
            dictationIsListening: true
        ) == .finishDictation)
    }

    @Test("dictation and unused taps keep their existing routing")
    func existingRoutesRemainStable() {
        #expect(ShortcutController.releaseAction(
            wasChorded: false,
            agentIsListening: false,
            dictationIsListening: true
        ) == .finishDictation)
        #expect(ShortcutController.releaseAction(
            wasChorded: false,
            agentIsListening: false,
            dictationIsListening: false
        ) == .registerQuickTap)
        #expect(ShortcutController.releaseAction(
            wasChorded: true,
            agentIsListening: true,
            dictationIsListening: false
        ) == .ignore)
        #expect(ShortcutController.shouldArmHold(inputMode: .hold, agentIsListening: false, dictationIsListening: false))
    }

    @Test("escape cancels only while recording or processing")
    func escapeRouting() {
        let escape = UInt16(kVK_Escape)
        for phase in [AppState.DictationPhase.listening, .processing] {
            #expect(ShortcutController.shouldCancelForEscape(
                keyCode: escape,
                dictationIsCancellable: phase.isCancellable,
                agentIsCancellable: AppState.AgentPhase.hidden.isCancellable
            ))
        }
        for phase in [AppState.AgentPhase.listening, .transcribing, .processing] {
            #expect(ShortcutController.shouldCancelForEscape(
                keyCode: escape,
                dictationIsCancellable: AppState.DictationPhase.idle.isCancellable,
                agentIsCancellable: phase.isCancellable
            ))
        }
        // Finished states close on their own or from their card; Esc there belongs to the frontmost app.
        for phase in [AppState.DictationPhase.idle, .success, .copyReady] {
            #expect(!ShortcutController.shouldCancelForEscape(
                keyCode: escape,
                dictationIsCancellable: phase.isCancellable,
                agentIsCancellable: AppState.AgentPhase.hidden.isCancellable
            ))
        }
        for phase in [AppState.AgentPhase.hidden, .result, .copyReady, .answerReady] {
            #expect(!ShortcutController.shouldCancelForEscape(
                keyCode: escape,
                dictationIsCancellable: AppState.DictationPhase.idle.isCancellable,
                agentIsCancellable: phase.isCancellable
            ))
        }
        #expect(!ShortcutController.shouldCancelForEscape(
            keyCode: UInt16(kVK_Return),
            dictationIsCancellable: true,
            agentIsCancellable: false
        ))
    }
}
