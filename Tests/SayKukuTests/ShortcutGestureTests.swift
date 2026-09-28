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

    @Test("tap mode starts audio on the first release and reuses it for a double tap")
    @MainActor
    func tapStartsImmediatelyAndPromotes() async throws {
        let environment = AppStateTestEnvironment()
        defer { environment.clean() }
        let audio = FakeAudioCapturing()
        let state = environment.makeState(dependencies: .fake(audio: audio))
        state.settings.inputMode = .tap
        state.settings.soundCuesEnabled = false
        try state.settings.saveAPIKey("test")
        let controller = ShortcutController(appState: state)

        controller.handle(fn(down: true, at: 1.00))
        controller.handle(fn(down: false, at: 1.02))
        #expect(audio.startCount == 1)

        // The events arrived late, but their keyboard timestamps still form a double tap.
        try await Task.sleep(for: .milliseconds(550))
        controller.handle(fn(down: true, at: 1.42))
        controller.handle(fn(down: false, at: 1.46))
        #expect(audio.startCount == 1)
        #expect(state.workflow.agentIsListening)
        #expect(!state.workflow.dictationIsListening)
    }

    @Test("double Fn accepts a relaxed cadence but leaves later taps separate")
    func doubleTapBoundary() {
        #expect(ShortcutController.isDoubleTap(first: 1, second: 1.45, wasChorded: false))
        #expect(!ShortcutController.isDoubleTap(first: 1, second: 1.451, wasChorded: false))
        #expect(!ShortcutController.isDoubleTap(first: 1, second: 1.4, wasChorded: true))
    }

    @Test("a later tap stops the capture started by the first tap")
    @MainActor
    func laterTapStopsDictation() async throws {
        let environment = AppStateTestEnvironment()
        defer { environment.clean() }
        let audio = FakeAudioCapturing()
        let state = environment.makeState(dependencies: .fake(audio: audio))
        state.settings.inputMode = .tap
        state.settings.soundCuesEnabled = false
        try state.settings.saveAPIKey("test")
        let controller = ShortcutController(appState: state)

        controller.handle(fn(down: true, at: 1.00))
        controller.handle(fn(down: false, at: 1.02))
        #expect(audio.startCount == 1)
        try await Task.sleep(for: .milliseconds(350))
        controller.handle(fn(down: true, at: 2.00))
        controller.handle(fn(down: false, at: 2.02))
        for _ in 0..<200 {
            if state.workflow.dictationPhase == .processing || state.workflow.dictationPhase == .success { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(state.workflow.dictationPhase == .processing || state.workflow.dictationPhase == .success)
        #expect(audio.startCount == 1)
    }

    private func fn(down: Bool, at timestamp: TimeInterval) -> KeyboardEventSample {
        KeyboardEventSample(
            kind: .flagsChanged,
            functionIsPressed: down,
            keyCode: UInt16(kVK_Function),
            timestamp: timestamp
        )
    }

    @Test("escape cancels only while recording or processing")
    func escapeRouting() {
        let escape = UInt16(kVK_Escape)
        for phase in [VoiceWorkflow.DictationPhase.listening, .processing] {
            #expect(ShortcutController.shouldCancelForEscape(
                keyCode: escape,
                dictationIsCancellable: phase.isCancellable,
                agentIsCancellable: VoiceWorkflow.AgentPhase.hidden.isCancellable
            ))
        }
        for phase in [VoiceWorkflow.AgentPhase.listening, .transcribing, .processing] {
            #expect(ShortcutController.shouldCancelForEscape(
                keyCode: escape,
                dictationIsCancellable: VoiceWorkflow.DictationPhase.idle.isCancellable,
                agentIsCancellable: phase.isCancellable
            ))
        }
        // Finished states close on their own or from their card; Esc there belongs to the frontmost app.
        for phase in [VoiceWorkflow.DictationPhase.idle, .success, .copyReady] {
            #expect(!ShortcutController.shouldCancelForEscape(
                keyCode: escape,
                dictationIsCancellable: phase.isCancellable,
                agentIsCancellable: VoiceWorkflow.AgentPhase.hidden.isCancellable
            ))
        }
        for phase in [VoiceWorkflow.AgentPhase.hidden, .result, .copyReady, .answerReady] {
            #expect(!ShortcutController.shouldCancelForEscape(
                keyCode: escape,
                dictationIsCancellable: VoiceWorkflow.DictationPhase.idle.isCancellable,
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
