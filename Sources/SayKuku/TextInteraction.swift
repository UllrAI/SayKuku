import ApplicationServices
import AppKit
import Carbon.HIToolbox
import Foundation
import os
import UniformTypeIdentifiers

enum TextInteractionError: LocalizedError {
    case accessibilityRequired
    case noFocusedElement
    case sensitiveTarget
    case targetChanged
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityRequired: "Accessibility permission is required"
        case .noFocusedElement: "No editable text field is focused"
        case .sensitiveTarget: "SayKuku doesn’t work in password fields or password managers."
        case .targetChanged: "The text field changed. Click back into it and try again."
        case .writeFailed: "This app didn’t accept the text. Try again."
        }
    }
}

enum TextWriteOutcome: Equatable {
    case verified
    case deliveredUnverified
}

struct TextTargetSnapshot: @unchecked Sendable {
    let appPID: pid_t
    let bundleID: String
    let appName: String
    let windowTitle: String
    let windowElement: AXUIElement?
    let textElement: AXUIElement?
    let selectedRange: CFRange?
    let selectedText: String
    let valueBefore: String?
    let isSensitive: Bool
}

struct VerifiedWrite {
    let id = UUID()
    let target: TextTargetSnapshot
    let text: String
    let createdAt: Date = .now

    var expectedValue: String? { TextInteraction.expectedValue(afterWriting: text, to: target) }
    var isRecent: Bool { Date.now.timeIntervalSince(createdAt) < 5 * 60 }
}

enum DictationTextJoiner {
    static func join(_ text: String, to snapshot: TextTargetSnapshot) -> String {
        guard let previous = snapshot.valueBefore, let range = snapshot.selectedRange,
              range.location >= 0, range.length >= 0,
              range.location + range.length <= (previous as NSString).length,
              let first = text.utf16.first, let last = text.utf16.last else { return text }

        let source = previous as NSString
        let needsLeadingSpace = range.location > 0
            && isASCIIWord(source.character(at: range.location - 1)) && isASCIIWord(first)
        let next = range.location + range.length
        let needsTrailingSpace = next < source.length
            && isASCIIWord(last) && isASCIIWord(source.character(at: next))
        return (needsLeadingSpace ? " " : "") + text + (needsTrailingSpace ? " " : "")
    }

    private static func isASCIIWord(_ character: UInt16) -> Bool {
        (65...90).contains(character) || (97...122).contains(character) || (48...57).contains(character)
    }
}

@MainActor
final class TextInteraction {
    typealias PasteboardItemSnapshot = [NSPasteboard.PasteboardType: Data]
    typealias PasteboardSnapshot = [PasteboardItemSnapshot]

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "SayKuku",
        category: "TextInteraction"
    )
    private static let pasteSessionType = NSPasteboard.PasteboardType("com.saykuku.paste-session")
    private static let textRoles = Set(["AXTextArea", "AXTextField", "AXComboBox", "AXSearchField"])
    /// Keeps a slow or hung target app from stalling the main thread for the default ~6 s per AX call.
    private static let messagingTimeout: Float = 0.4
    /// Upper bound for searching a focused container for its text field.
    private static let elementSearchBudget = Duration.milliseconds(250)
    /// Delays between reads while verifying a write; roughly the same 0.5 s window with fewer AX round trips.
    private static let verificationDelays = [50, 75, 100, 125, 150]

    /// Dictation needs a window to write into; the Agent can also answer, open links or run shortcuts
    /// from the desktop, so `requiringWindow: false` returns a snapshot without a window or text field.
    func captureTarget(requiringWindow: Bool = true) throws -> TextTargetSnapshot {
        guard AXIsProcessTrusted() else { throw TextInteractionError.accessibilityRequired }
        guard let app = NSWorkspace.shared.frontmostApplication else { throw TextInteractionError.noFocusedElement }
        let application = applicationElement(for: app.processIdentifier)
        let focusedElement = focusedElement(for: app.processIdentifier)
        let element = focusedElement.flatMap(preferredTextElement(from:))
        let window = element.flatMap(window(of:))
            ?? focusedElement.flatMap(window(of:))
            ?? copyAttribute(application, kAXFocusedWindowAttribute)
        if requiringWindow, element == nil, window == nil { throw TextInteractionError.noFocusedElement }
        let title: String = window.flatMap { copyAttribute($0, kAXTitleAttribute) } ?? ""
        let bundleID = app.bundleIdentifier ?? ""
        let range = element.flatMap(selectedRange(of:))
        let value = element.flatMap { normalizedValue(of: $0, selectedRange: range) }
        let selection = element.map { self.selectedText(of: $0, value: value, range: range) } ?? ""
        let sensitive = isSensitive(element: element, bundleID: bundleID)

        Self.logger.info(
            "Captured target bundle=\(bundleID, privacy: .public) role=\(element.map(self.role(of:)) ?? "unavailable", privacy: .public) readable=\(value != nil, privacy: .public)"
        )
        return TextTargetSnapshot(
            appPID: app.processIdentifier,
            bundleID: bundleID,
            appName: app.localizedName ?? bundleID,
            windowTitle: title,
            windowElement: window,
            textElement: element,
            selectedRange: range,
            selectedText: selection,
            valueBefore: value,
            isSensitive: sensitive
        )
    }

    /// Returns the text field to write into, or nil when the focused window exposes none.
    /// Electron and some web views hide their text fields from Accessibility, so a window
    /// without one still gets a paste; `paste` then leaves the text on the clipboard.
    private func validate(_ snapshot: TextTargetSnapshot) throws -> AXUIElement? {
        guard !snapshot.isSensitive else { throw TextInteractionError.sensitiveTarget }
        guard !IsSecureEventInputEnabled() else { throw TextInteractionError.sensitiveTarget }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier == snapshot.appPID,
              app.bundleIdentifier == snapshot.bundleID else { throw TextInteractionError.targetChanged }

        let focusedElement = focusedElement(for: snapshot.appPID)
        let element = focusedElement.flatMap(preferredTextElement(from:))
        let currentWindow = element.flatMap(window(of:))
            ?? focusedElement.flatMap(window(of:))
            ?? copyAttribute(applicationElement(for: snapshot.appPID), kAXFocusedWindowAttribute)
        guard element != nil || currentWindow != nil else { throw TextInteractionError.noFocusedElement }
        guard sameWindow(snapshot.windowElement, currentWindow) else {
            throw TextInteractionError.targetChanged
        }
        if let original = snapshot.textElement {
            guard let element, CFEqual(original, element) else { throw TextInteractionError.targetChanged }
        }
        guard !isSensitive(element: element, bundleID: snapshot.bundleID) else {
            throw TextInteractionError.sensitiveTarget
        }

        if let element, snapshot.valueBefore != nil, snapshot.selectedRange != nil {
            let range = selectedRange(of: element)
            let value = normalizedValue(of: element, selectedRange: range)
            guard value == snapshot.valueBefore,
                  range == snapshot.selectedRange,
                  selectedText(of: element, value: value, range: range) == snapshot.selectedText else {
                throw TextInteractionError.targetChanged
            }
        }
        return element
    }

    @discardableResult
    func write(_ text: String, to snapshot: TextTargetSnapshot) async throws -> TextWriteOutcome {
        try Task.checkCancellation()
        let element = try validate(snapshot)
        let expectedValue = Self.expectedValue(afterWriting: text, to: snapshot)
        var settable = DarwinBoolean(false)

        if let element, let expectedValue,
           AXUIElementIsAttributeSettable(
               element,
               kAXSelectedTextAttribute as CFString,
               &settable
           ) == .success,
           settable.boolValue {
            try Task.checkCancellation()
            let setStatus = AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextAttribute as CFString,
                text as CFTypeRef
            )
            if setStatus == .success {
                // The text is already in, so a cancel must not cut verification short (see `paste`).
                let verified = try await Task {
                    try await waitForExpectedValue(expectedValue, in: element, snapshot: snapshot)
                }.value
                if verified {
                    Self.logger.info("Text delivered with verified Accessibility insertion")
                    return .verified
                }
                guard let current = currentValue(in: snapshot) else {
                    Self.logger.info("Accessibility insertion made the target unreadable; avoiding a duplicate paste")
                    return .deliveredUnverified
                }
                if current != snapshot.valueBefore {
                    Self.logger.info("Accessibility insertion changed text but could not be verified exactly")
                    return .deliveredUnverified
                }
                Self.logger.info("Accessibility insertion made no observable change; falling back to paste")
            }
        }

        try Task.checkCancellation()
        return try await paste(text, to: snapshot)
    }

    func currentValue(of snapshot: TextTargetSnapshot) -> String? {
        currentValue(in: snapshot)
    }

    func replacementSnapshot(for write: VerifiedWrite) throws -> TextTargetSnapshot {
        guard let expected = write.expectedValue,
              currentValue(in: write.target) == expected,
              let originalRange = write.target.selectedRange,
              let app = NSWorkspace.shared.frontmostApplication,
              let focused = focusedElement(for: app.processIdentifier),
              let element = preferredTextElement(from: focused),
              let original = write.target.textElement,
              CFEqual(original, element),
              !IsSecureEventInputEnabled() else { throw TextInteractionError.targetChanged }

        let previousSelection = selectedRange(of: element)
        var selectionValidated = false
        defer {
            if !selectionValidated, var previousSelection,
               let value = AXValueCreate(.cfRange, &previousSelection) {
                AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value)
            }
        }
        var range = CFRange(location: originalRange.location, length: (write.text as NSString).length)
        guard let value = AXValueCreate(.cfRange, &range),
              AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success else {
            throw TextInteractionError.targetChanged
        }
        let snapshot = try captureTarget()
        guard !snapshot.isSensitive,
              snapshot.valueBefore == expected,
              snapshot.selectedRange == range,
              snapshot.selectedText == write.text else { throw TextInteractionError.targetChanged }
        selectionValidated = true
        return snapshot
    }

    private func paste(_ text: String, to snapshot: TextTargetSnapshot) async throws -> TextWriteOutcome {
        let element = try validate(snapshot)
        let pasteboard = NSPasteboard.general
        let previous = Self.snapshot(of: pasteboard)
        let sessionID = UUID().uuidString
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setString(sessionID, forType: Self.pasteSessionType)
        // Tell clipboard history tools this short-lived, app-generated content is not worth keeping.
        item.setData(Data(), forType: PasteboardPolicy.transientType)
        item.setData(Data(), forType: PasteboardPolicy.autoGeneratedType)
        guard pasteboard.writeObjects([item]), pasteboard.string(forType: .string) == text else {
            throw TextInteractionError.writeFailed
        }

        do {
            try await Task.sleep(for: .milliseconds(80))
            _ = try validate(snapshot)
            try postPasteCommand()
        } catch {
            restore(previous, ifOwnedBy: sessionID, on: pasteboard)
            throw error
        }

        // A posted ⌘V can't be taken back. Verifying and restoring the clipboard run in their own
        // task, so a cancel from here on neither loses the user's clipboard nor reports a
        // delivered write as cancelled.
        return try await Task<TextWriteOutcome, Error> {
            let expectedValue = Self.expectedValue(afterWriting: text, to: snapshot)
            if let element, let expectedValue,
               try await waitForExpectedValue(expectedValue, in: element, snapshot: snapshot) {
                try? await Task.sleep(for: .milliseconds(180))
                restore(previous, ifOwnedBy: sessionID, on: pasteboard)
                Self.logger.info("Text delivered with verified synthetic paste")
                return .verified
            }

            if expectedValue != nil,
               let current = currentValue(in: snapshot),
               current == snapshot.valueBefore {
                Self.logger.error("Synthetic paste posted but readable target text did not change")
                restore(previous, ifOwnedBy: sessionID, on: pasteboard)
                throw TextInteractionError.writeFailed
            }

            guard element != nil else {
                // Nothing shows where a blind paste landed, so keep the text on the clipboard.
                Self.logger.info("Text pasted without an exposed text field; kept on the clipboard")
                return .deliveredUnverified
            }
            try? await Task.sleep(for: .milliseconds(350))
            restore(previous, ifOwnedBy: sessionID, on: pasteboard)
            Self.logger.info("Text delivered with synthetic paste; target does not expose verifiable text")
            return .deliveredUnverified
        }.value
    }

    /// Posts ⌘ down, V down, V up, ⌘ up back to back with no suspension point in between, so a
    /// cancel can't leave Command held. The ⌘ key events stay for remote desktop and VM clients
    /// that only sync modifiers from flagsChanged.
    private func postPasteCommand() throws {
        let command = CGKeyCode(kVK_Command)
        let key = KeyboardLayout.currentPasteKeyCode
        guard let source = CGEventSource(stateID: .privateState),
              let commandDown = CGEvent(keyboardEventSource: source, virtualKey: command, keyDown: true),
              let pasteDown = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let pasteUp = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false),
              let commandUp = CGEvent(keyboardEventSource: source, virtualKey: command, keyDown: false) else {
            throw TextInteractionError.writeFailed
        }
        commandDown.flags = .maskCommand
        pasteDown.flags = .maskCommand
        pasteUp.flags = .maskCommand
        for event in [commandDown, pasteDown, pasteUp, commandUp] {
            event.post(tap: .cghidEventTap)
        }
    }

    private func waitForExpectedValue(
        _ expectedValue: String, in element: AXUIElement, snapshot: TextTargetSnapshot
    ) async throws -> Bool {
        let expectedLength = (expectedValue as NSString).length
        for (index, delay) in Self.verificationDelays.enumerated() {
            try await Task.sleep(for: .milliseconds(delay))
            // A cheap length check skips reading the whole field while the app is still catching up.
            // The last attempt always does the full read in case an app counts characters differently.
            let isLastAttempt = index == Self.verificationDelays.count - 1
            if !isLastAttempt, let count: NSNumber = copyAttribute(element, kAXNumberOfCharactersAttribute),
               count.intValue != expectedLength {
                continue
            }
            if currentValue(in: snapshot) == expectedValue { return true }
        }
        return false
    }

    private func currentValue(in snapshot: TextTargetSnapshot) -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier == snapshot.appPID,
              app.bundleIdentifier == snapshot.bundleID,
              let focusedElement = focusedElement(for: snapshot.appPID) else { return nil }
        guard let element = preferredTextElement(from: focusedElement) else { return nil }
        let currentWindow = window(of: element)
            ?? copyAttribute(applicationElement(for: snapshot.appPID), kAXFocusedWindowAttribute)
        guard sameWindow(snapshot.windowElement, currentWindow) else { return nil }
        if let original = snapshot.textElement, !CFEqual(original, element) { return nil }
        let range = selectedRange(of: element)
        return normalizedValue(of: element, selectedRange: range)
    }

    nonisolated static func expectedValue(afterWriting text: String, to snapshot: TextTargetSnapshot) -> String? {
        guard let previous = snapshot.valueBefore, let range = snapshot.selectedRange,
              range.location >= 0, range.length >= 0,
              range.location + range.length <= (previous as NSString).length else { return nil }
        return (previous as NSString).replacingCharacters(
            in: NSRange(location: range.location, length: range.length),
            with: text
        )
    }

    private func selectedRange(of element: AXUIElement) -> CFRange? {
        guard let value: AXValue = copyAttribute(element, kAXSelectedTextRangeAttribute),
              AXValueGetType(value) == .cfRange else { return nil }
        var range = CFRange()
        return AXValueGetValue(value, .cfRange, &range) ? range : nil
    }

    private func focusedElement(for expectedPID: pid_t) -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        // Setting the timeout on the system-wide element makes it the default for every AX call.
        AXUIElementSetMessagingTimeout(systemWide, Self.messagingTimeout)
        if let element: AXUIElement = copyAttribute(systemWide, kAXFocusedUIElementAttribute),
           processID(of: element) == expectedPID {
            return element
        }
        guard let element: AXUIElement = copyAttribute(applicationElement(for: expectedPID), kAXFocusedUIElementAttribute),
              processID(of: element) == expectedPID else { return nil }
        return element
    }

    private func applicationElement(for pid: pid_t) -> AXUIElement {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, Self.messagingTimeout)
        return application
    }

    private func processID(of element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        return AXUIElementGetPid(element, &pid) == .success ? pid : nil
    }

    private func preferredTextElement(from root: AXUIElement) -> AXUIElement? {
        if isTextElement(root) { return root }
        var queue = childElements(of: root).map { (element: $0, depth: 1) }
        var seen: [AXUIElement] = []
        var candidates: [AXUIElement] = []
        var visited = 0
        let deadline = ContinuousClock.now + Self.elementSearchBudget
        while !queue.isEmpty, visited < 80, ContinuousClock.now < deadline {
            let current = queue.removeFirst()
            guard !seen.contains(where: { CFEqual($0, current.element) }) else { continue }
            seen.append(current.element)
            visited += 1
            if isTextElement(current.element) {
                let focused: NSNumber? = copyAttribute(current.element, kAXFocusedAttribute)
                if focused?.boolValue == true { return current.element }
                candidates.append(current.element)
                continue
            }
            if current.depth < 6 {
                queue.append(contentsOf: childElements(of: current.element).map {
                    (element: $0, depth: current.depth + 1)
                })
            }
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

    private func isTextElement(_ element: AXUIElement) -> Bool {
        let elementRole = role(of: element)
        if elementRole == "AXSecureTextField" || Self.textRoles.contains(elementRole) { return true }
        let editable: NSNumber? = copyAttribute(element, kAXIsEditableAttribute)
        return editable?.boolValue == true
    }

    private func childElements(of element: AXUIElement) -> [AXUIElement] {
        var result: [AXUIElement] = []
        for attribute in [kAXChildrenAttribute, kAXContentsAttribute, "AXVisibleChildren"] {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
                  let value else { continue }
            if CFGetTypeID(value) == AXUIElementGetTypeID() {
                result.append(value as! AXUIElement)
            } else if let children = value as? [AXUIElement] {
                result.append(contentsOf: children)
            } else if let children = value as? [AnyObject] {
                result.append(contentsOf: children.compactMap { child in
                    guard CFGetTypeID(child) == AXUIElementGetTypeID() else { return nil }
                    return (child as! AXUIElement)
                })
            }
        }
        return result
    }

    private func window(of element: AXUIElement) -> AXUIElement? {
        copyAttribute(element, kAXWindowAttribute)
    }

    private func sameWindow(_ original: AXUIElement?, _ current: AXUIElement?) -> Bool {
        switch (original, current) {
        case (nil, nil): true
        case let (original?, current?): CFEqual(original, current)
        default: false
        }
    }

    private func role(of element: AXUIElement) -> String {
        copyAttribute(element, kAXRoleAttribute) ?? ""
    }

    private func normalizedValue(of element: AXUIElement, selectedRange: CFRange?) -> String? {
        guard let value: String = copyAttribute(element, kAXValueAttribute) else { return nil }
        let placeholder: String? = copyAttribute(element, kAXPlaceholderValueAttribute)
        if let placeholder, !placeholder.isEmpty, value == placeholder,
           selectedRange == CFRange(location: 0, length: 0) {
            return ""
        }
        return value
    }

    private func selectedText(of element: AXUIElement, value: String?, range: CFRange?) -> String {
        if let selected: String = copyAttribute(element, kAXSelectedTextAttribute), !selected.isEmpty {
            return selected
        }
        guard let value, let range, range.location >= 0, range.length > 0,
              range.location + range.length <= (value as NSString).length else { return "" }
        return (value as NSString).substring(
            with: NSRange(location: range.location, length: range.length)
        )
    }

    private func isSensitive(element: AXUIElement?, bundleID: String) -> Bool {
        let elementRole = element.map(role(of:)) ?? ""
        let subrole: String = element.flatMap { copyAttribute($0, kAXSubroleAttribute) } ?? ""
        return IsSecureEventInputEnabled()
            || elementRole == "AXSecureTextField"
            || subrole.lowercased().contains("secure")
            || SensitiveApps.contains(bundleID: bundleID)
    }

    static func snapshot(of pasteboard: NSPasteboard) -> PasteboardSnapshot {
        (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: PasteboardPolicy.backupTypes(item.types).compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        }
    }

    static func restore(_ snapshot: PasteboardSnapshot, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let items = snapshot.map { values in
            let item = NSPasteboardItem()
            for (type, data) in values { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }

    private func restore(
        _ snapshot: PasteboardSnapshot,
        ifOwnedBy sessionID: String,
        on pasteboard: NSPasteboard
    ) {
        guard pasteboard.string(forType: Self.pasteSessionType) == sessionID else { return }
        Self.restore(snapshot, to: pasteboard)
    }

    private func copyAttribute<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? T
    }
}

/// Apps whose windows SayKuku never reads from or writes into, matched by bundle ID prefix.
enum SensitiveApps {
    static let bundlePrefixes = [
        "com.1password", "com.agilebits", "com.bitwarden", "com.lastpass", "com.dashlane",
        "org.keepassxc", "com.apple.keychainaccess", "com.apple.passwords"
    ]

    static func contains(bundleID: String) -> Bool {
        let lowercased = bundleID.lowercased()
        return bundlePrefixes.contains { lowercased.hasPrefix($0) }
    }
}

/// Clipboard conventions from nspasteboard.org shared by password managers and clipboard history tools.
enum PasteboardPolicy {
    // Computed so this nonisolated enum holds no global state of a possibly non-Sendable type.
    static var concealedType: NSPasteboard.PasteboardType { .init("org.nspasteboard.ConcealedType") }
    static var transientType: NSPasteboard.PasteboardType { .init("org.nspasteboard.TransientType") }
    static var autoGeneratedType: NSPasteboard.PasteboardType { .init("org.nspasteboard.AutoGeneratedType") }

    /// Secrets and short-lived content are marked by their source and never used as Agent context.
    static func isPrivate(_ types: [NSPasteboard.PasteboardType]) -> Bool {
        types.contains(concealedType) || types.contains(transientType)
    }

    /// Types worth backing up before a temporary paste. Reading a type forces its owner to produce
    /// lazily provided data, so file promises are skipped (they cannot be restored without their
    /// provider anyway) and only the owner's first, preferred image representation is kept instead
    /// of making it render every image format it offers.
    static func backupTypes(_ types: [NSPasteboard.PasteboardType]) -> [NSPasteboard.PasteboardType] {
        var result: [NSPasteboard.PasteboardType] = []
        var hasImage = false
        for type in types where !type.rawValue.localizedCaseInsensitiveContains("promise") {
            if UTType(type.rawValue)?.conforms(to: .image) == true {
                guard !hasImage else { continue }
                hasImage = true
            }
            result.append(type)
        }
        return result
    }
}

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

enum ContextCollector {
    /// Length label for context items, e.g. "12 字" or "1 character".
    static func characterCount(_ count: Int, isChineseUI: Bool) -> String {
        if isChineseUI { return "\(count) 字" }
        return count == 1 ? "1 character" : "\(count) characters"
    }

    @MainActor
    static func collect(
        snapshot: TextTargetSnapshot,
        selectedTextAllowed: Bool,
        currentAppAllowed: Bool,
        windowTitleAllowed: Bool,
        clipboardAllowed: Bool,
        browserPageAllowed: Bool,
        session: AgentSession?,
        domains: Set<DomainPreset>,
        customDomainTerms: [String],
        knowledge: [KnowledgeEntity],
        isChineseUI: Bool
    ) -> [ContextItem] {
        guard !snapshot.isSensitive else { return [] }
        func title(_ chinese: String, _ english: String) -> String { isChineseUI ? chinese : english }
        var items: [ContextItem] = []
        if currentAppAllowed {
            items.append(ContextItem(kind: .app, symbol: "app", title: snapshot.appName, value: snapshot.bundleID))
        }
        if selectedTextAllowed, !snapshot.selectedText.isEmpty {
            items.append(ContextItem(
                kind: .selectedText,
                symbol: "text.quote",
                title: title("选中文字", "Selected text") + " · " + characterCount(snapshot.selectedText.count, isChineseUI: isChineseUI),
                value: snapshot.selectedText
            ))
        }
        if windowTitleAllowed, !snapshot.windowTitle.isEmpty {
            items.append(ContextItem(kind: .window, symbol: "macwindow", title: title("窗口标题", "Window title"), value: snapshot.windowTitle))
        }
        if clipboardAllowed, !PasteboardPolicy.isPrivate(NSPasteboard.general.types ?? []),
           let clipboard = NSPasteboard.general.string(forType: .string), !clipboard.isEmpty {
            items.append(ContextItem(
                kind: .clipboard,
                symbol: "clipboard",
                title: title("剪贴板", "Clipboard") + " · " + characterCount(clipboard.count, isChineseUI: isChineseUI),
                value: clipboard
            ))
        }
        if browserPageAllowed, let url = browserURL(bundleID: snapshot.bundleID), !url.isEmpty {
            items.append(ContextItem(kind: .browser, symbol: "globe", title: title("浏览器页面", "Browser page"), value: url))
        }
        if let session, session.expiresAt > .now {
            items.append(ContextItem(kind: .session, symbol: "bubble.left.and.bubble.right", title: title("最近对话", "Recent conversation"), value: session.contextSummary))
        }
        if !domains.isEmpty || !customDomainTerms.isEmpty {
            let domainNames = DomainPreset.allCases.filter(domains.contains).map(\.promptName)
            items.append(ContextItem(
                kind: .domain,
                symbol: "text.bubble",
                title: title("常用领域与词汇", "Domains & vocabulary"),
                value: (domainNames + customDomainTerms).joined(separator: ", ")
            ))
        }
        if !knowledge.isEmpty {
            // Only marks knowledge as enabled for this run; the prompt is rendered from AppState's entities.
            items.append(ContextItem(
                kind: .knowledge,
                symbol: "books.vertical",
                title: title("已保存的知识", "Saved knowledge"),
                value: "\(knowledge.count)"
            ))
        }
        return items
    }

    @MainActor
    private static func browserURL(bundleID: String) -> String? {
        let source: String
        switch bundleID {
        case "com.apple.Safari":
            source = "tell application \"Safari\" to return URL of current tab of front window"
        case "com.google.Chrome":
            source = "tell application \"Google Chrome\" to return URL of active tab of front window"
        default:
            return nil
        }
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil ? result?.stringValue : nil
    }
}

enum AgentActionError: Error {
    case shortcutFailed
}

enum AgentActionExecutor {
    /// RFC 3986 unreserved characters; everything else, including `&`, `+` and `=`, is percent-encoded.
    private static let queryValueAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    @MainActor
    static func execute(_ response: AgentResponse) async throws {
        switch response.action {
        case .writeText, .answer:
            return
        case .openURL:
            guard let value = response.url, let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased()) else {
                throw QwenError.invalidResponse
            }
            NSWorkspace.shared.open(url)
        case .webSearch:
            guard let query = response.query, let url = webSearchURL(for: query) else { throw QwenError.invalidResponse }
            NSWorkspace.shared.open(url)
        case .runShortcut:
            guard let name = response.shortcutName, !name.isEmpty else { throw QwenError.invalidResponse }
            try await runShortcut(named: name)
        }
    }

    static func webSearchURL(for query: String) -> URL? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: queryValueAllowed) else { return nil }
        return URL(string: "https://www.google.com/search?q=\(encoded)")
    }

    /// Waits for `shortcuts run` off the main thread so a failing shortcut is reported instead of shown as done.
    private static func runShortcut(named name: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name]
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
        guard status == 0 else { throw AgentActionError.shortcutFailed }
    }
}

private func == (lhs: CFRange?, rhs: CFRange?) -> Bool {
    switch (lhs, rhs) {
    case (nil, nil): true
    case let (left?, right?): left.location == right.location && left.length == right.length
    default: false
    }
}
