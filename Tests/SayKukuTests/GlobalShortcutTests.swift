import AppKit
import Carbon.HIToolbox
import SwiftUI
import Testing
@testable import SayKuku

@Suite("Global shortcuts")
struct GlobalShortcutTests {
    private let controlOptionCommand = UInt32(controlKey | optionKey | cmdKey)

    @Test("defaults use two modifiers and remain distinct")
    func defaults() {
        #expect(GlobalShortcut.defaultVoiceInput.isValid)
        #expect(GlobalShortcut.defaultVoiceAgent.isValid)
        #expect(GlobalShortcut.defaultVoiceInput != GlobalShortcut.defaultVoiceAgent)
        #expect(GlobalShortcut.defaultVoiceInput.displayString == "⌃⌘V")
        #expect(GlobalShortcut.defaultVoiceAgent.displayString == "⌃⌘A")
    }

    @Test("new defaults do not replace saved shortcuts or an explicit off state")
    @MainActor
    func savedPreferences() {
        let environment = AppStateTestEnvironment()
        defer { environment.clean() }
        let settings = AppSettings(defaults: environment.defaults, keychain: environment.keychain)
        #expect(settings.voiceInputShortcut == .defaultVoiceInput)
        #expect(settings.voiceAgentShortcut == .defaultVoiceAgent)

        let oldInput = GlobalShortcut(keyCode: UInt32(kVK_ANSI_V), carbonModifiers: UInt32(controlKey | optionKey | cmdKey))
        settings.voiceInputShortcut = oldInput
        settings.voiceAgentShortcut = nil

        let reloaded = AppSettings(defaults: environment.defaults, keychain: environment.keychain)
        #expect(reloaded.voiceInputShortcut == oldInput)
        #expect(reloaded.voiceAgentShortcut == nil)
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
        #expect(GlobalShortcut.defaultVoiceInput.spokenString == "Control-Command-V")
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
        let rightCommand = GlobalShortcut(keyCode: UInt32(kVK_RightCommand), carbonModifiers: 0)
        #expect(rightCommand.isValid)
        #expect(rightCommand.isModifierOnly)
        #expect(GlobalShortcut.restored(from: rightCommand.storageValue, fallback: .defaultVoiceInput) == rightCommand)
        #expect(rightCommand.displayString == "\(localized("Right")) ⌘")
        #expect(rightCommand.spokenString == "\(localized("Right")) \(localized("Command"))")
        #expect(rightCommand.keyboardShortcut == nil)

        let doubleCommand = GlobalShortcut(keyCode: UInt32(kVK_RightCommand), carbonModifiers: 0, modifierTapCount: 2)
        #expect(doubleCommand.isValid)
        #expect(doubleCommand.displayString == "\(localized("Right")) ⌘ ×2")
        #expect(doubleCommand.storageValue == "\(kVK_RightCommand):0:2")
        #expect(GlobalShortcut(storageValue: doubleCommand.storageValue) == doubleCommand)
        #expect(GlobalShortcut.modifierOnlyResult(
            keyCode: UInt16(kVK_RightCommand), tapCount: 2, otherShortcut: rightCommand
        ) == .record(doubleCommand))
        #expect(GlobalShortcut.modifierOnlyResult(
            keyCode: UInt16(kVK_RightCommand), tapCount: 2, otherShortcut: doubleCommand
        ) == .reject(.duplicate))
        #expect(!GlobalShortcut(keyCode: UInt32(kVK_ANSI_V), carbonModifiers: UInt32(cmdKey), modifierTapCount: 2).isValid)
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
        #expect(letter?.modifiers == SwiftUI.EventModifiers([.control, .command]))

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
        let rightCommand = GlobalShortcut(keyCode: UInt32(kVK_RightCommand), carbonModifiers: 0)
        #expect(GlobalShortcut.modifierOnlyResult(keyCode: UInt16(kVK_RightCommand), otherShortcut: nil) == .record(rightCommand))
        #expect(GlobalShortcut.modifierOnlyResult(keyCode: UInt16(kVK_RightCommand), otherShortcut: rightCommand) == .reject(.duplicate))
        #expect(GlobalShortcut.modifierOnlyResult(keyCode: UInt16(kVK_Function), otherShortcut: nil) == nil)
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
            keyCode: UInt16(kVK_ANSI_A), carbonModifiers: UInt32(controlKey | cmdKey), otherShortcut: .defaultVoiceAgent
        ) == .reject(.duplicate))
    }

    @Test("recording rejects every ⌘ and ⇧⌘ combination")
    func recordingAppReservedCombinations() {
        let command = UInt32(cmdKey)
        let shiftCommand = UInt32(shiftKey | cmdKey)
        let keys = [kVK_ANSI_V, kVK_ANSI_S, kVK_ANSI_F, kVK_ANSI_P, kVK_ANSI_3, kVK_Space, kVK_Tab, kVK_F5]
        for key in keys {
            #expect(GlobalShortcut.recordingResult(
                keyCode: UInt16(key), carbonModifiers: command, otherShortcut: nil
            ) == .reject(.reserved))
            #expect(GlobalShortcut.recordingResult(
                keyCode: UInt16(key), carbonModifiers: shiftCommand, otherShortcut: nil
            ) == .reject(.reserved))
        }
    }

    @Test("recording rejects macOS system combinations but allows ⌃ and ⌥ variants")
    func recordingSystemCombinations() {
        let system: [(Int, Int)] = [
            (kVK_ANSI_D, optionKey | cmdKey), (kVK_ANSI_H, optionKey | cmdKey), (kVK_ANSI_M, optionKey | cmdKey),
            (kVK_ANSI_W, optionKey | cmdKey), (kVK_ANSI_I, optionKey | cmdKey), (kVK_Space, optionKey | cmdKey),
            (kVK_ANSI_Q, controlKey | cmdKey), (kVK_Space, controlKey | cmdKey),
            (kVK_ANSI_F, controlKey | cmdKey), (kVK_ANSI_D, controlKey | cmdKey),
            (kVK_Space, controlKey | optionKey), (kVK_Space, controlKey)
        ]
        for (key, modifiers) in system {
            #expect(GlobalShortcut.recordingResult(
                keyCode: UInt16(key), carbonModifiers: UInt32(modifiers), otherShortcut: nil
            ) == .reject(.system))
        }

        let allowed = [
            GlobalShortcut(keyCode: UInt32(kVK_ANSI_V), carbonModifiers: UInt32(controlKey | cmdKey)),
            GlobalShortcut(keyCode: UInt32(kVK_ANSI_V), carbonModifiers: UInt32(optionKey | cmdKey)),
            GlobalShortcut(keyCode: UInt32(kVK_ANSI_S), carbonModifiers: UInt32(optionKey | shiftKey | cmdKey)),
            GlobalShortcut(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(controlKey | shiftKey)),
            GlobalShortcut.defaultVoiceInput,
            GlobalShortcut.defaultVoiceAgent
        ]
        for shortcut in allowed {
            #expect(GlobalShortcut.recordingResult(
                keyCode: UInt16(shortcut.keyCode), carbonModifiers: shortcut.carbonModifiers, otherShortcut: nil
            ) == .record(shortcut))
        }
    }

    @Test("a reserved combination saved by an older version falls back to the default")
    func restoredReservedCombination() {
        let commandS = GlobalShortcut(keyCode: UInt32(kVK_ANSI_S), carbonModifiers: UInt32(cmdKey))
        #expect(GlobalShortcut.restored(from: commandS.storageValue, fallback: .defaultVoiceInput) == .defaultVoiceInput)
        let shiftCommand3 = GlobalShortcut(keyCode: UInt32(kVK_ANSI_3), carbonModifiers: UInt32(shiftKey | cmdKey))
        #expect(GlobalShortcut.restored(from: shiftCommand3.storageValue, fallback: .defaultVoiceAgent) == .defaultVoiceAgent)
        let controlSpace = GlobalShortcut(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(controlKey))
        #expect(GlobalShortcut.restored(from: controlSpace.storageValue, fallback: .defaultVoiceInput) == .defaultVoiceInput)
        let optionCommandV = GlobalShortcut(keyCode: UInt32(kVK_ANSI_V), carbonModifiers: UInt32(optionKey | cmdKey))
        #expect(GlobalShortcut.restored(from: optionCommandV.storageValue, fallback: .defaultVoiceInput) == optionCommandV)
    }

    @Test("status reports which shortcut failed before Accessibility")
    @MainActor
    func status() {
        #expect(ShortcutController.status(gestureReady: true, failedHotKeys: []) == .ready)
        #expect(ShortcutController.status(gestureReady: false, failedHotKeys: []) == .accessibilityRequired)
        #expect(ShortcutController.status(gestureReady: true, failedHotKeys: [.voiceAgent]) == .hotKeyConflict([.voiceAgent]))
        #expect(ShortcutController.status(gestureReady: false, failedHotKeys: [.voiceInput, .voiceAgent])
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
