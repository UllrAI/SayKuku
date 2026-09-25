import AppKit
import Carbon.HIToolbox

/// Key codes name physical keys, so ⌘V has to be looked up in the active layout: on Dvorak the
/// ANSI V position types "k" and would send a different shortcut. Text Input Sources APIs must be
/// called on the main thread.
@MainActor
enum KeyboardLayout {
    /// The key that types "v" in the current keyboard layout, or ANSI V if none does. Input methods
    /// such as Pinyin report the ASCII layout they type with.
    static var currentPasteKeyCode: CGKeyCode {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutData = layoutData(of: source),
              let keyCode = pasteKeyCode(in: layoutData) else { return CGKeyCode(kVK_ANSI_V) }
        return keyCode
    }

    static func layoutData(of source: TISInputSource) -> Data? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        return Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
    }

    /// Translates with Command held, as apps match key equivalents, so layouts that switch to
    /// QWERTY under ⌘ (Dvorak – QWERTY ⌘) keep the V key.
    static func pasteKeyCode(in layoutData: Data) -> CGKeyCode? {
        let v = UniChar(UInt8(ascii: "v"))
        let commandModifier = UInt32(cmdKey >> 8) & 0xFF
        return layoutData.withUnsafeBytes { buffer -> CGKeyCode? in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            return (0..<CGKeyCode(128)).first { keyCode in
                var deadKeyState: UInt32 = 0
                var length = 0
                var characters = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(
                    layout, keyCode, UInt16(kUCKeyActionDown), commandModifier, UInt32(LMGetKbdType()),
                    OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState, characters.count, &length, &characters
                )
                return status == OSStatus(noErr) && length == 1 && characters[0] == v
            }
        }
    }
}
