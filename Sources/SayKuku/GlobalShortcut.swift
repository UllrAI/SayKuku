import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Actions that can be bound to a system-wide shortcut.
/// Raw values double as Carbon hot key IDs.
enum GlobalShortcutAction: UInt32, CaseIterable, Sendable {
    case voiceInput = 1
    case voiceAgent = 2

    var other: GlobalShortcutAction {
        switch self {
        case .voiceInput: .voiceAgent
        case .voiceAgent: .voiceInput
        }
    }

    /// The Fn gesture that keeps working whether or not the shortcut is set.
    var fnGesture: String {
        switch self {
        case .voiceInput: "Fn"
        case .voiceAgent: "Fn Fn"
        }
    }

    @MainActor func title(_ appState: AppState) -> String {
        switch self {
        case .voiceInput: appState.voiceInputTitle
        case .voiceAgent: appState.voiceAgentTitle
        }
    }
}

/// A system-wide shortcut: a virtual key code plus Carbon modifier flags,
/// exactly what `RegisterEventHotKey` expects.
struct GlobalShortcut: Hashable, Sendable {
    let keyCode: UInt32
    let carbonModifiers: UInt32

    // ⌃⌥Space is the macOS "Select next source in Input menu" default, so both
    // defaults use ⌃⌥⌘, which neither macOS nor common apps bind out of the box.
    static let defaultVoiceInput = GlobalShortcut(
        keyCode: UInt32(kVK_ANSI_V),
        carbonModifiers: UInt32(controlKey | optionKey | cmdKey)
    )
    static let defaultVoiceAgent = GlobalShortcut(
        keyCode: UInt32(kVK_ANSI_A),
        carbonModifiers: UInt32(controlKey | optionKey | cmdKey)
    )

    enum RecordingIssue: Equatable, Sendable {
        case needsModifier, unsupportedKey, duplicate
    }

    enum RecordingResult: Equatable, Sendable {
        case cancel
        case clear
        case record(GlobalShortcut)
        case reject(RecordingIssue)
    }

    var isValid: Bool {
        carbonModifiers & Self.requiredModifiers != 0
            && carbonModifiers & ~Self.supportedModifiers == 0
            && Self.keys[Int(keyCode)] != nil
    }

    /// Standard macOS notation, e.g. "⌃⌥⌘V" or "⌃⇧Space".
    var displayString: String {
        let modifiers = Self.modifierSymbols
            .filter { carbonModifiers & $0.mask != 0 }
            .map { $0.symbol }
            .joined()
        return modifiers + (Self.keys[Int(keyCode)]?.name ?? "?")
    }

    var eventModifiers: EventModifiers {
        var result: EventModifiers = []
        if carbonModifiers & UInt32(controlKey) != 0 { result.insert(.control) }
        if carbonModifiers & UInt32(optionKey) != 0 { result.insert(.option) }
        if carbonModifiers & UInt32(shiftKey) != 0 { result.insert(.shift) }
        if carbonModifiers & UInt32(cmdKey) != 0 { result.insert(.command) }
        return result
    }

    /// Used to label menu items with the active combination.
    var keyboardShortcut: KeyboardShortcut? {
        guard let key = Self.keys[Int(keyCode)] else { return nil }
        return KeyboardShortcut(KeyEquivalent(key.character), modifiers: eventModifiers)
    }

    var storageValue: String { "\(keyCode):\(carbonModifiers)" }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }

    /// Decodes a stored setting. An empty string means the shortcut was turned off;
    /// an unreadable value falls back to the default.
    static func restored(from storageValue: String, fallback: GlobalShortcut) -> GlobalShortcut? {
        guard !storageValue.isEmpty else { return nil }
        return GlobalShortcut(storageValue: storageValue) ?? fallback
    }

    /// Interprets one key press while the settings page is recording.
    /// Plain Esc cancels and plain Delete turns the shortcut off.
    static func recordingResult(
        keyCode: UInt16,
        carbonModifiers: UInt32,
        otherShortcut: GlobalShortcut?
    ) -> RecordingResult {
        if carbonModifiers == 0 {
            switch Int(keyCode) {
            case kVK_Escape: return .cancel
            case kVK_Delete, kVK_ForwardDelete: return .clear
            default: break
            }
        }

        let shortcut = GlobalShortcut(keyCode: UInt32(keyCode), carbonModifiers: carbonModifiers)
        guard carbonModifiers & requiredModifiers != 0 else { return .reject(.needsModifier) }
        guard shortcut.isValid else { return .reject(.unsupportedKey) }
        guard shortcut != otherShortcut else { return .reject(.duplicate) }
        return .record(shortcut)
    }

    // ⌥ and ⌥⇧ alone type special characters, and macOS 15 refuses to register
    // hot keys that use only them, so every shortcut needs ⌘ or ⌃.
    private static let requiredModifiers = UInt32(cmdKey | controlKey)
    private static let supportedModifiers = UInt32(cmdKey | optionKey | controlKey | shiftKey)

    // Apple's canonical order: Control, Option, Shift, Command.
    private static let modifierSymbols: [(mask: UInt32, symbol: String)] = [
        (UInt32(controlKey), "⌃"),
        (UInt32(optionKey), "⌥"),
        (UInt32(shiftKey), "⇧"),
        (UInt32(cmdKey), "⌘")
    ]

    private struct Key: Sendable {
        let name: String
        /// Menu key equivalent; function keys use AppKit's private-use code points.
        let character: Character
    }

    /// Recordable keys. Names follow the US layout printed on Mac keyboards.
    /// Esc and Delete are left out because they cancel and clear recording.
    private static let keys: [Int: Key] = {
        var keys: [Int: Key] = [
            kVK_Space: Key(name: "Space", character: " "),
            kVK_Return: Key(name: "Return", character: "\r"),
            kVK_Tab: Key(name: "Tab", character: "\t"),
            kVK_UpArrow: Key(name: "↑", character: "\u{F700}"),
            kVK_DownArrow: Key(name: "↓", character: "\u{F701}"),
            kVK_LeftArrow: Key(name: "←", character: "\u{F702}"),
            kVK_RightArrow: Key(name: "→", character: "\u{F703}"),
            kVK_Home: Key(name: "Home", character: "\u{F729}"),
            kVK_End: Key(name: "End", character: "\u{F72B}"),
            kVK_PageUp: Key(name: "Page Up", character: "\u{F72C}"),
            kVK_PageDown: Key(name: "Page Down", character: "\u{F72D}")
        ]

        let printable: [(Int, String)] = [
            (kVK_ANSI_A, "A"), (kVK_ANSI_B, "B"), (kVK_ANSI_C, "C"), (kVK_ANSI_D, "D"),
            (kVK_ANSI_E, "E"), (kVK_ANSI_F, "F"), (kVK_ANSI_G, "G"), (kVK_ANSI_H, "H"),
            (kVK_ANSI_I, "I"), (kVK_ANSI_J, "J"), (kVK_ANSI_K, "K"), (kVK_ANSI_L, "L"),
            (kVK_ANSI_M, "M"), (kVK_ANSI_N, "N"), (kVK_ANSI_O, "O"), (kVK_ANSI_P, "P"),
            (kVK_ANSI_Q, "Q"), (kVK_ANSI_R, "R"), (kVK_ANSI_S, "S"), (kVK_ANSI_T, "T"),
            (kVK_ANSI_U, "U"), (kVK_ANSI_V, "V"), (kVK_ANSI_W, "W"), (kVK_ANSI_X, "X"),
            (kVK_ANSI_Y, "Y"), (kVK_ANSI_Z, "Z"),
            (kVK_ANSI_0, "0"), (kVK_ANSI_1, "1"), (kVK_ANSI_2, "2"), (kVK_ANSI_3, "3"),
            (kVK_ANSI_4, "4"), (kVK_ANSI_5, "5"), (kVK_ANSI_6, "6"), (kVK_ANSI_7, "7"),
            (kVK_ANSI_8, "8"), (kVK_ANSI_9, "9"),
            (kVK_ANSI_Minus, "-"), (kVK_ANSI_Equal, "="), (kVK_ANSI_LeftBracket, "["),
            (kVK_ANSI_RightBracket, "]"), (kVK_ANSI_Backslash, "\\"), (kVK_ANSI_Semicolon, ";"),
            (kVK_ANSI_Quote, "'"), (kVK_ANSI_Comma, ","), (kVK_ANSI_Period, "."),
            (kVK_ANSI_Slash, "/"), (kVK_ANSI_Grave, "`")
        ]
        for (code, name) in printable {
            keys[code] = Key(name: name, character: Character(name.lowercased()))
        }

        let functionKeys = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
            kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20
        ]
        for (index, code) in functionKeys.enumerated() {
            // NSF1FunctionKey is U+F704; F2–F20 follow consecutively.
            guard let scalar = Unicode.Scalar(0xF704 + UInt32(index)) else { continue }
            keys[code] = Key(name: "F\(index + 1)", character: Character(scalar))
        }
        return keys
    }()
}

extension GlobalShortcut {
    init?(storageValue: String) {
        let parts = storageValue.split(separator: ":")
        guard parts.count == 2,
              let keyCode = UInt32(parts[0]),
              let modifiers = UInt32(parts[1]) else { return nil }
        self.init(keyCode: keyCode, carbonModifiers: modifiers)
        guard isValid else { return nil }
    }
}

extension AppState {
    func globalShortcut(for action: GlobalShortcutAction) -> GlobalShortcut? {
        switch action {
        case .voiceInput: voiceInputShortcut
        case .voiceAgent: voiceAgentShortcut
        }
    }

    func setGlobalShortcut(_ shortcut: GlobalShortcut?, for action: GlobalShortcutAction) {
        switch action {
        case .voiceInput: voiceInputShortcut = shortcut
        case .voiceAgent: voiceAgentShortcut = shortcut
        }
    }
}
