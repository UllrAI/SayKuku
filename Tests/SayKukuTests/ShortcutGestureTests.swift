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

    @Test("escape cancels only while a voice workflow is active")
    func escapeRouting() {
        #expect(ShortcutController.shouldCancelForEscape(
            keyCode: UInt16(kVK_Escape),
            dictationIsActive: true,
            agentIsActive: false
        ))
        #expect(ShortcutController.shouldCancelForEscape(
            keyCode: UInt16(kVK_Escape),
            dictationIsActive: false,
            agentIsActive: true
        ))
        #expect(!ShortcutController.shouldCancelForEscape(
            keyCode: UInt16(kVK_Escape),
            dictationIsActive: false,
            agentIsActive: false
        ))
        #expect(!ShortcutController.shouldCancelForEscape(
            keyCode: UInt16(kVK_Return),
            dictationIsActive: true,
            agentIsActive: false
        ))
    }
}
