import AppKit
import Carbon.HIToolbox
import SwiftUI
import Testing
@testable import SayKuku

@Suite("Global shortcuts")
struct GlobalShortcutTests {
    private let controlOptionCommand = UInt32(controlKey | optionKey | cmdKey)

    @Test("defaults are valid, distinct, and avoid the old ⇧⌘ combinations")
    func defaults() {
        #expect(GlobalShortcut.defaultVoiceInput.isValid)
        #expect(GlobalShortcut.defaultVoiceAgent.isValid)
        #expect(GlobalShortcut.defaultVoiceInput != GlobalShortcut.defaultVoiceAgent)
        #expect(GlobalShortcut.defaultVoiceInput.displayString == "⌃⌥⌘V")
        #expect(GlobalShortcut.defaultVoiceAgent.displayString == "⌃⌥⌘A")
    }

    @Test("display uses Apple's modifier order and readable key names")
    func displayString() {
        let all = UInt32(controlKey | optionKey | shiftKey | cmdKey)
        #expect(GlobalShortcut(keyCode: UInt32(kVK_Space), carbonModifiers: all).displayString == "⌃⌥⇧⌘Space")
        #expect(GlobalShortcut(keyCode: UInt32(kVK_Return), carbonModifiers: UInt32(controlKey)).displayString == "⌃Return")
        #expect(GlobalShortcut(keyCode: UInt32(kVK_F5), carbonModifiers: UInt32(optionKey | cmdKey)).displayString == "⌥⌘F5")
        #expect(GlobalShortcut(keyCode: UInt32(kVK_F12), carbonModifiers: UInt32(optionKey)).displayString == "⌥F12")
        #expect(GlobalShortcut(keyCode: UInt32(kVK_ANSI_Slash), carbonModifiers: UInt32(cmdKey)).displayString == "⌘/")
        #expect(GlobalShortcut(keyCode: UInt32(kVK_UpArrow), carbonModifiers: UInt32(controlKey)).displayString == "⌃↑")
    }

    @Test("VoiceOver names spell out modifiers and symbol keys")
    func spokenString() {
        #expect(GlobalShortcut.defaultVoiceInput.spokenString == "Control-Option-Command-V")
        #expect(GlobalShortcut(keyCode: UInt32(kVK_UpArrow), carbonModifiers: UInt32(controlKey | shiftKey)).spokenString == "Control-Shift-Up Arrow")
        #expect(GlobalShortcut(keyCode: UInt32(kVK_F5), carbonModifiers: UInt32(cmdKey)).spokenString == "Command-F5")
    }

    @Test("storage round-trips, empty means off, and bad values fall back")
    func storage() {
        let shortcut = GlobalShortcut(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(controlKey | shiftKey))
        #expect(GlobalShortcut(storageValue: shortcut.storageValue) == shortcut)
        #expect(GlobalShortcut.restored(from: shortcut.storageValue, fallback: .defaultVoiceInput) == shortcut)
        #expect(GlobalShortcut.restored(from: "", fallback: .defaultVoiceInput) == nil)
        #expect(GlobalShortcut.restored(from: "garbage", fallback: .defaultVoiceInput) == .defaultVoiceInput)
        // Valid key but no ⌘ or ⌃, which could never be recorded.
        let shiftOnly = "\(kVK_ANSI_V):\(shiftKey)"
        #expect(GlobalShortcut(storageValue: shiftOnly) == nil)
        #expect(GlobalShortcut.restored(from: shiftOnly, fallback: .defaultVoiceAgent) == .defaultVoiceAgent)
        #expect(GlobalShortcut(storageValue: "\(kVK_ANSI_V):\(optionKey | shiftKey)") == nil)
        #expect(GlobalShortcut(storageValue: "\(kVK_ANSI_Keypad1):\(cmdKey)") == nil)
    }

    @Test("AppKit modifier flags map to Carbon and ignore non-shortcut flags")
    func modifierConversion() {
        let flags: NSEvent.ModifierFlags = [.command, .shift, .capsLock, .function, .numericPad]
        #expect(GlobalShortcut.carbonModifiers(from: flags) == UInt32(cmdKey | shiftKey))
        #expect(GlobalShortcut.carbonModifiers(from: [.control, .option]) == UInt32(controlKey | optionKey))
        #expect(GlobalShortcut.carbonModifiers(from: []) == 0)
    }

    @Test("menu key equivalents match the stored shortcut")
    @MainActor
    func keyboardShortcut() {
        let letter = GlobalShortcut.defaultVoiceInput.keyboardShortcut
        #expect(letter?.key.character == "v")
        #expect(letter?.modifiers == SwiftUI.EventModifiers([.control, .option, .command]))

        let space = GlobalShortcut(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(optionKey | shiftKey))
        #expect(space.keyboardShortcut?.key.character == " ")
        #expect(space.eventModifiers == [.option, .shift])
    }

    @Test("recording handles cancel, clear, and valid combinations")
    func recordingActions() {
        #expect(GlobalShortcut.recordingResult(
            keyCode: UInt16(kVK_Escape), carbonModifiers: 0, otherShortcut: nil
        ) == .cancel)
        #expect(GlobalShortcut.recordingResult(
            keyCode: UInt16(kVK_Delete), carbonModifiers: 0, otherShortcut: nil
        ) == .clear)
        #expect(GlobalShortcut.recordingResult(
            keyCode: UInt16(kVK_ForwardDelete), carbonModifiers: 0, otherShortcut: nil
        ) == .clear)
        #expect(GlobalShortcut.recordingResult(
            keyCode: UInt16(kVK_ANSI_K), carbonModifiers: controlOptionCommand, otherShortcut: .defaultVoiceAgent
        ) == .record(GlobalShortcut(keyCode: UInt32(kVK_ANSI_K), carbonModifiers: controlOptionCommand)))
    }

    @Test("recording rejects missing modifiers, unsupported keys, and duplicates")
    func recordingRejections() {
        #expect(GlobalShortcut.recordingResult(
            keyCode: UInt16(kVK_ANSI_K), carbonModifiers: 0, otherShortcut: nil
        ) == .reject(.needsModifier))
        #expect(GlobalShortcut.recordingResult(
            keyCode: UInt16(kVK_ANSI_K), carbonModifiers: UInt32(shiftKey), otherShortcut: nil
        ) == .reject(.needsModifier))
        #expect(GlobalShortcut.recordingResult(
            keyCode: UInt16(kVK_ANSI_K), carbonModifiers: UInt32(optionKey | shiftKey), otherShortcut: nil
        ) == .reject(.needsModifier))
        #expect(GlobalShortcut.recordingResult(
            keyCode: UInt16(kVK_F5), carbonModifiers: UInt32(optionKey), otherShortcut: nil
        ) == .reject(.needsModifier))
        #expect(GlobalShortcut.recordingResult(
            keyCode: UInt16(kVK_Escape), carbonModifiers: UInt32(cmdKey | optionKey), otherShortcut: nil
        ) == .reject(.unsupportedKey))
        #expect(GlobalShortcut.recordingResult(
            keyCode: UInt16(kVK_ANSI_Keypad1), carbonModifiers: UInt32(cmdKey), otherShortcut: nil
        ) == .reject(.unsupportedKey))
        #expect(GlobalShortcut.recordingResult(
            keyCode: UInt16(kVK_ANSI_A), carbonModifiers: controlOptionCommand, otherShortcut: .defaultVoiceAgent
        ) == .reject(.duplicate))
    }

    @Test("recording rejects standard macOS shortcuts but allows variants")
    func recordingReservedCombinations() {
        let command = UInt32(cmdKey)
        let commandKeys = [
            kVK_ANSI_V, kVK_ANSI_C, kVK_ANSI_X, kVK_ANSI_Z, kVK_ANSI_A, kVK_ANSI_Q,
            kVK_ANSI_W, kVK_ANSI_H, kVK_ANSI_M, kVK_Tab, kVK_Space, kVK_ANSI_Comma
        ]
        for key in commandKeys {
            #expect(GlobalShortcut.recordingResult(
                keyCode: UInt16(key), carbonModifiers: command, otherShortcut: nil
            ) == .reject(.reserved))
        }
        #expect(GlobalShortcut.recordingResult(
            keyCode: UInt16(kVK_ANSI_Z), carbonModifiers: UInt32(shiftKey | cmdKey), otherShortcut: nil
        ) == .reject(.reserved))

        let optionCommandV = GlobalShortcut(keyCode: UInt32(kVK_ANSI_V), carbonModifiers: UInt32(optionKey | cmdKey))
        #expect(GlobalShortcut.recordingResult(
            keyCode: UInt16(kVK_ANSI_V), carbonModifiers: optionCommandV.carbonModifiers, otherShortcut: nil
        ) == .record(optionCommandV))
        let controlSpace = GlobalShortcut(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(controlKey))
        #expect(GlobalShortcut.recordingResult(
            keyCode: UInt16(kVK_Space), carbonModifiers: controlSpace.carbonModifiers, otherShortcut: nil
        ) == .record(controlSpace))
    }

    @Test("status reports which shortcut failed before Accessibility")
    @MainActor
    func status() {
        #expect(ShortcutController.status(fnReady: true, failedHotKeys: []) == .ready)
        #expect(ShortcutController.status(fnReady: false, failedHotKeys: []) == .accessibilityRequired)
        #expect(ShortcutController.status(fnReady: true, failedHotKeys: [.voiceAgent]) == .hotKeyConflict([.voiceAgent]))
        #expect(ShortcutController.status(fnReady: false, failedHotKeys: [.voiceInput, .voiceAgent])
            == .hotKeyConflict([.voiceInput, .voiceAgent]))
    }

    @Test("hot key IDs stay stable and each action points at the other")
    func actions() {
        #expect(GlobalShortcutAction.voiceInput.rawValue == 1)
        #expect(GlobalShortcutAction.voiceAgent.rawValue == 2)
        #expect(GlobalShortcutAction.voiceInput.other == .voiceAgent)
        #expect(GlobalShortcutAction.voiceAgent.other == .voiceInput)
    }
}
