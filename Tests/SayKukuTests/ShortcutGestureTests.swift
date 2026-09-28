import AppKit
import Carbon.HIToolbox
import Testing
@testable import SayKuku

@Suite("Fn gesture routing")
struct FnGestureRoutingTests {
    @Test("mouse down becomes other input without reading a keyboard key code")
    func mouseEventSample() throws {
        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 1,
            windowNumber: 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))
        let sample = try #require(KeyboardEventSample.from(event))
        #expect(sample.kind == .otherInput)
        #expect(sample.keyCode == 0)
    }

    @Test("single right Command fires on release but chords and mouse gestures do not")
    func modifierTap() {
        let rightCommand = UInt16(kVK_RightCommand)
        let configured: Set<UInt16> = [rightCommand]
        var tracker = ModifierTapTracker()
        let command = UInt32(cmdKey)
        func sample(_ kind: KeyboardEventSample.Kind, _ key: UInt16, _ modifiers: UInt32) -> KeyboardEventSample {
            KeyboardEventSample(kind: kind, functionIsPressed: false, keyCode: key, timestamp: 1, carbonModifiers: modifiers)
        }

        #expect(tracker.release(in: sample(.flagsChanged, rightCommand, command), configuredKeys: configured) == nil)
        #expect(tracker.release(in: sample(.flagsChanged, rightCommand, 0), configuredKeys: configured) == rightCommand)

        #expect(tracker.release(in: sample(.flagsChanged, rightCommand, command), configuredKeys: configured) == nil)
        #expect(tracker.release(in: sample(.keyDown, UInt16(kVK_ANSI_C), command), configuredKeys: configured) == nil)
        #expect(tracker.release(in: sample(.flagsChanged, rightCommand, 0), configuredKeys: configured) == nil)

        #expect(tracker.release(in: sample(.flagsChanged, rightCommand, command), configuredKeys: configured) == nil)
        #expect(tracker.release(in: sample(.otherInput, 0, command), configuredKeys: configured) == nil)
        #expect(tracker.release(in: sample(.flagsChanged, rightCommand, 0), configuredKeys: configured) == nil)

        #expect(tracker.release(in: sample(.flagsChanged, rightCommand, command), configuredKeys: configured) == nil)
        #expect(tracker.release(in: sample(.flagsChanged, UInt16(kVK_Shift), command | UInt32(shiftKey)), configuredKeys: configured) == nil)
        #expect(tracker.release(in: sample(.flagsChanged, UInt16(kVK_Shift), command), configuredKeys: configured) == nil)
        #expect(tracker.release(in: sample(.flagsChanged, rightCommand, 0), configuredKeys: configured) == nil)
    }

    @Test("two right Command taps start and stop voice input")
    @MainActor
    func modifierTapTogglesDictation() async throws {
        let environment = AppStateTestEnvironment()
        defer { environment.clean() }
        let audio = FakeAudioCapturing()
        let state = environment.makeState(dependencies: .fake(audio: audio))
        state.settings.soundCuesEnabled = false
        state.settings.voiceInputShortcut = GlobalShortcut(keyCode: UInt32(kVK_RightCommand), carbonModifiers: 0)
        try state.settings.saveAPIKey("test")
        let controller = ShortcutController(appState: state)
        let rightCommand = UInt16(kVK_RightCommand)

        func event(down: Bool) -> KeyboardEventSample {
            KeyboardEventSample(
                kind: .flagsChanged,
                functionIsPressed: false,
                keyCode: rightCommand,
                timestamp: 1,
                carbonModifiers: down ? UInt32(cmdKey) : 0
            )
        }

        controller.handle(event(down: true))
        #expect(audio.startCount == 0)
        controller.handle(event(down: false))
        for _ in 0..<100 {
            if state.workflow.dictationIsListening { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(state.workflow.dictationIsListening)
        #expect(audio.startCount == 1)

        controller.handle(event(down: true))
        controller.handle(event(down: false))
        #expect(!state.workflow.dictationIsListening)
    }

    @Test("a shared modifier distinguishes one tap for input from two for Agent")
    @MainActor
    func sharedModifierTapCounts() async throws {
        let environment = AppStateTestEnvironment()
        defer { environment.clean() }
        let audio = FakeAudioCapturing()
        let state = environment.makeState(dependencies: .fake(audio: audio))
        state.settings.soundCuesEnabled = false
        state.settings.voiceInputShortcut = GlobalShortcut(keyCode: UInt32(kVK_RightCommand), carbonModifiers: 0)
        state.settings.voiceAgentShortcut = GlobalShortcut(
            keyCode: UInt32(kVK_RightCommand), carbonModifiers: 0, modifierTapCount: 2
        )
        try state.settings.saveAPIKey("test")
        let controller = ShortcutController(appState: state)

        func tap(at timestamp: TimeInterval) {
            controller.handle(KeyboardEventSample(
                kind: .flagsChanged, functionIsPressed: false,
                keyCode: UInt16(kVK_RightCommand), timestamp: timestamp,
                carbonModifiers: UInt32(cmdKey)
            ))
            controller.handle(KeyboardEventSample(
                kind: .flagsChanged, functionIsPressed: false,
                keyCode: UInt16(kVK_RightCommand), timestamp: timestamp + 0.02,
                carbonModifiers: 0
            ))
        }

        tap(at: 1)
        #expect(audio.startCount == 1)
        tap(at: 1.2)
        for _ in 0..<100 {
            if state.workflow.agentIsListening { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(state.workflow.agentIsListening)
        #expect(!state.workflow.dictationIsListening)
        #expect(audio.startCount == 1)

        state.workflow.cancelActiveVoiceWorkflow()
        tap(at: 2)
        #expect(audio.startCount == 2)
        for _ in 0..<100 {
            if state.workflow.dictationIsListening { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(state.workflow.dictationIsListening)
        #expect(audio.startCount == 2)
    }

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
