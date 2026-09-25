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
    /// The caret's screen rectangle in AppKit coordinates, for placing the overlay. Only read
    /// when the overlay follows the cursor.
    let caretFrame: CGRect?
}

extension TextTargetSnapshot {
    var agentTextField: AgentTextField {
        if textElement != nil { return .focused }
        return windowElement != nil ? .unknown : .absent
    }
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

    private static let pasteSessionType = NSPasteboard.PasteboardType("com.saykuku.paste-session")
    private static let textRoles = Set(["AXTextArea", "AXTextField", "AXComboBox", "AXSearchField"])
    /// Keeps a slow or hung target app from stalling the main thread for the default ~6 s per AX call.
    private static let messagingTimeout: Float = 0.4
    /// Upper bounds for searching an element tree, such as a focused container for its text field.
    /// Finding nothing is fine: the window is then treated as having no known text field.
    private static let elementSearchBudget = Duration.milliseconds(100)
    private static let elementSearchLimit = 40
    /// Delays between reads while verifying a write; roughly the same 0.5 s window with fewer AX round trips.
    private static let verificationDelays = [50, 75, 100, 125, 150]

    /// Dictation needs a window to write into; the Agent can also answer, open links or run shortcuts
    /// from the desktop, so `requiringWindow: false` returns a snapshot without a window or text field.
    /// `includingCaretFrame` reads the caret rectangle, which only the cursor-following overlay needs.
    func captureTarget(requiringWindow: Bool = true, includingCaretFrame: Bool = false) throws -> TextTargetSnapshot {
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
        let caret = includingCaretFrame
            ? element.flatMap { element in range.flatMap { caretFrame(of: element, at: $0) } }
            : nil

        Log.text.info(
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
            isSensitive: sensitive,
            caretFrame: caret
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
        if let element = try validate(snapshot),
           let outcome = try await insertWithAccessibility(text, into: element, snapshot: snapshot) {
            logWrite(to: snapshot, route: "accessibility", result: String(describing: outcome))
            return outcome
        }

        try Task.checkCancellation()
        do {
            let outcome = try await paste(text, to: snapshot)
            logWrite(to: snapshot, route: "paste", result: String(describing: outcome))
            return outcome
        } catch {
            logWrite(to: snapshot, route: "paste", result: String(describing: error))
            throw error
        }
    }

    /// Returns nil when the field can't take an Accessibility write or visibly ignored it, so the caller pastes.
    private func insertWithAccessibility(
        _ text: String, into element: AXUIElement, snapshot: TextTargetSnapshot
    ) async throws -> TextWriteOutcome? {
        var settable = DarwinBoolean(false)
        guard let expectedValue = Self.expectedValue(afterWriting: text, to: snapshot),
              AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success,
              settable.boolValue else { return nil }
        try Task.checkCancellation()
        guard AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success else {
            return nil
        }

        // The text may already be in, so a cancel must not cut verification short (see `paste`).
        return try await Task<TextWriteOutcome?, Error> {
            if try await waitForExpectedValue(expectedValue, in: element, snapshot: snapshot) { return .verified }
            let ignored = Self.insertionWasIgnored(
                caret: selectedRange(of: element),
                value: currentValue(in: snapshot),
                snapshot: snapshot
            )
            return ignored ? nil : .deliveredUnverified
        }.value
    }

    /// Some apps update AXValue well after the verification window while the caret has already moved
    /// past the inserted text. Only an untouched caret and value show the write was ignored; pasting
    /// after anything else risks inserting the text twice.
    nonisolated static func insertionWasIgnored(
        caret: CFRange?, value: String?, snapshot: TextTargetSnapshot
    ) -> Bool {
        caret == snapshot.selectedRange && value == snapshot.valueBefore
    }

    private func logWrite(to snapshot: TextTargetSnapshot, route: String, result: String) {
        Log.text.info(
            "Text write bundle=\(snapshot.bundleID, privacy: .public) route=\(route, privacy: .public) result=\(result, privacy: .public)"
        )
    }

    func currentValue(of snapshot: TextTargetSnapshot) -> String? {
        currentValue(in: snapshot)
    }

    /// The address of the page in the captured Safari or Chrome window, read through Accessibility under
    /// the same per-call timeout. Safari keeps it as `AXURL` on the web area, Chrome as `AXDocument` on the window.
    func browserPageAddress(in snapshot: TextTargetSnapshot) -> String? {
        guard let window = snapshot.windowElement else { return nil }
        let address: AnyObject?
        switch snapshot.bundleID {
        case "com.apple.Safari":
            address = webArea(in: window).flatMap { copyAttribute($0, kAXURLAttribute) }
        case "com.google.Chrome":
            address = copyAttribute(window, kAXDocumentAttribute)
        default:
            return nil
        }
        // AXURL holds a CFURL, AXDocument a string.
        let url = (address as? URL)?.absoluteString ?? (address as? String)
        return url.flatMap(ContextCollector.pageAddress)
    }

    /// Descends only through containers, so toolbar buttons and tabs don't use up the search limit.
    private func webArea(in window: AXUIElement) -> AXUIElement? {
        var queue = childElements(of: window)
        var visited = 0
        let deadline = ContinuousClock.now + Self.elementSearchBudget
        while !queue.isEmpty, visited < Self.elementSearchLimit, ContinuousClock.now < deadline {
            let element = queue.removeFirst()
            visited += 1
            switch role(of: element) {
            case "AXWebArea":
                return element
            case "AXSplitGroup", "AXTabGroup", "AXGroup", "AXScrollArea":
                queue.append(contentsOf: childElements(of: element))
            default:
                continue
            }
        }
        return nil
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
                return .verified
            }

            if expectedValue != nil,
               let current = currentValue(in: snapshot),
               current == snapshot.valueBefore {
                Log.text.error("Synthetic paste posted but readable target text did not change")
                restore(previous, ifOwnedBy: sessionID, on: pasteboard)
                throw TextInteractionError.writeFailed
            }

            guard element != nil else {
                // Nothing shows where a blind paste landed, so keep the text on the clipboard.
                Log.text.info("Text pasted without an exposed text field; kept on the clipboard")
                return .deliveredUnverified
            }
            try? await Task.sleep(for: .milliseconds(350))
            restore(previous, ifOwnedBy: sessionID, on: pasteboard)
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

    /// The screen rectangle of the selection start, which is the caret when nothing is selected.
    private func caretFrame(of element: AXUIElement, at range: CFRange) -> CGRect? {
        var start = CFRange(location: range.location, length: 0)
        guard let parameter = AXValueCreate(.cfRange, &start),
              let value: AXValue = copyParameterizedAttribute(element, kAXBoundsForRangeParameterizedAttribute, parameter),
              AXValueGetType(value) == .cgRect else { return nil }
        var rect = CGRect.zero
        // Some apps answer with an empty rectangle at the screen origin instead of failing.
        guard AXValueGetValue(value, .cgRect, &rect), rect.height > 0 else { return nil }
        return appKitFrame(fromAX: rect)
    }

    /// Accessibility measures down from the top of the primary screen; AppKit measures up from its bottom.
    private func appKitFrame(fromAX rect: CGRect) -> CGRect? {
        guard let primaryScreenHeight = NSScreen.screens.first?.frame.height else { return nil }
        return CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
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
        while !queue.isEmpty, visited < Self.elementSearchLimit, ContinuousClock.now < deadline {
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
        return Self.isSensitiveWithoutAccessibility(bundleID: bundleID)
            || elementRole == "AXSecureTextField"
            || subrole.lowercased().contains("secure")
    }

    /// The checks that need no Accessibility round trip, so a voice workflow can refuse a password field
    /// or manager before the microphone starts. The focused element is checked again once it's read.
    nonisolated static func isSensitiveWithoutAccessibility(bundleID: String) -> Bool {
        IsSecureEventInputEnabled() || SensitiveApps.contains(bundleID: bundleID)
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

    private func copyParameterizedAttribute<T>(_ element: AXUIElement, _ attribute: String, _ parameter: CFTypeRef) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, attribute as CFString, parameter, &value
        ) == .success else { return nil }
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
    /// Longest selected text or previous output sent to Qwen.
    static let textLimit = 10_000
    static let clipboardLimit = 4_000

    /// A text item titled with its length; text past `limit` is not sent, and the title says so.
    static func textItem(
        kind: ContextItem.Kind, symbol: String, title: String, value: String, limit: Int, isChineseUI: Bool
    ) -> ContextItem {
        let isClipped = value.count > limit
        let length = switch (isClipped, isChineseUI) {
        case (true, true): "前 \(limit) 字"
        case (true, false): "first \(limit) characters"
        case (false, true): "\(value.count) 字"
        case (false, false): value.count == 1 ? "1 character" : "\(value.count) characters"
        }
        return ContextItem(
            kind: kind, symbol: symbol, title: "\(title) · \(length)",
            value: clipped(value, to: limit), isClipped: isClipped
        )
    }

    @MainActor
    static func collect(
        snapshot: TextTargetSnapshot,
        selectedTextAllowed: Bool,
        currentAppAllowed: Bool,
        windowTitleAllowed: Bool,
        clipboardAllowed: Bool,
        browserPage: String?,
        session: AgentSession?,
        domains: Set<DomainPreset>,
        knowledge: [KnowledgeEntity],
        isChineseUI: Bool
    ) -> [ContextItem] {
        guard !snapshot.isSensitive else { return [] }
        func title(_ chinese: String, _ english: String) -> String { isChineseUI ? chinese : english }
        var items: [ContextItem] = []
        if currentAppAllowed {
            // The display name tells the model what a niche app is; the bundle ID keeps it unambiguous.
            items.append(ContextItem(
                kind: .app, symbol: "app", title: snapshot.appName, value: "\(snapshot.appName) (\(snapshot.bundleID))"
            ))
        }
        if selectedTextAllowed, !snapshot.selectedText.isEmpty {
            items.append(textItem(
                kind: .selectedText,
                symbol: "text.quote",
                title: title("选中文字", "Selected text"),
                value: snapshot.selectedText,
                limit: textLimit,
                isChineseUI: isChineseUI
            ))
        }
        if windowTitleAllowed, !snapshot.windowTitle.isEmpty {
            items.append(ContextItem(kind: .window, symbol: "macwindow", title: title("窗口标题", "Window title"), value: snapshot.windowTitle))
        }
        if clipboardAllowed, !PasteboardPolicy.isPrivate(NSPasteboard.general.types ?? []),
           let clipboard = NSPasteboard.general.string(forType: .string), !clipboard.isEmpty {
            items.append(textItem(
                kind: .clipboard,
                symbol: "clipboard",
                title: title("剪贴板", "Clipboard"),
                value: clipboard,
                limit: clipboardLimit,
                isChineseUI: isChineseUI
            ))
        }
        if let browserPage, !browserPage.isEmpty {
            items.append(ContextItem(kind: .browser, symbol: "globe", title: title("浏览器页面", "Browser page"), value: browserPage))
        }
        if let session, session.expiresAt > .now {
            items.append(ContextItem(kind: .session, symbol: "bubble.left.and.bubble.right", title: title("最近对话", "Recent conversation"), value: session.contextSummary))
        }
        if !domains.isEmpty {
            items.append(ContextItem(
                kind: .domain,
                symbol: "text.bubble",
                title: title("常用领域", "Domains"),
                value: DomainPreset.allCases.filter(domains.contains).map(\.promptName).joined(separator: ", ")
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

    /// Query and fragment can carry OAuth codes or reset tokens, so only the page address is sent.
    static func pageAddress(_ url: String) -> String? {
        guard var components = URLComponents(string: url) else { return nil }
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        return components.string
    }
}

enum AgentActionError: Error {
    case shortcutFailed
    case shortcutTimedOut
}

enum AgentActionExecutor {
    /// Context that someone other than the user may have written, such as a web page hiding instructions.
    private static let untrustedContextKinds: [ContextItem.Kind] = [
        .selectedText, .previousOutput, .window, .clipboard, .browser, .session
    ]

    @MainActor
    static func execute(_ response: AgentResponse, engine: SearchEngine) async throws {
        if let url = try validate(response, engine: engine) {
            NSWorkspace.shared.open(url)
        } else if response.action == .runShortcut, let name = response.shortcutName {
            try await runShortcut(named: name)
        }
    }

    /// Checks the payload an action needs, before a confirmation card offers it or the action runs.
    /// Returns the address to open for links and searches.
    @discardableResult
    static func validate(_ response: AgentResponse, engine: SearchEngine) throws -> URL? {
        switch response.action {
        case .writeText, .answer:
            return nil
        case .openURL:
            guard let url = webURL(response.url) else { throw QwenError.invalidResponse }
            return url
        case .webSearch:
            guard let query = response.query, !query.isEmpty, let url = engine.url(for: query) else {
                throw QwenError.invalidResponse
            }
            return url
        case .runShortcut:
            guard response.shortcutName?.isEmpty == false else { throw QwenError.invalidResponse }
            return nil
        }
    }

    /// The model reads context and picks the action in one reply, so injected text could choose a link, a search
    /// that sends the clipboard away, or a shortcut, and even the transcript beside it. Every action that leaves
    /// the app waits for the user when untrusted context is attached; writes and answers stay in view.
    static func needsConfirmation(_ response: AgentResponse, context: [ContextItem]) -> Bool {
        [.openURL, .webSearch, .runShortcut].contains(response.action)
            && context.contains { untrustedContextKinds.contains($0.kind) }
    }

    /// Whether a writeText reply replaces text the model saw only the start of, which would drop the rest.
    static func replacesClippedText(_ response: AgentResponse, context: [ContextItem]) -> Bool {
        let source: ContextItem.Kind = response.target == .previous ? .previousOutput : .selectedText
        return response.action == .writeText && context.contains { $0.kind == source && $0.isClipped }
    }

    /// Only plain web links; credentials such as `https://google.com@evil.com` would disguise the real host.
    private static func webURL(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased()),
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    /// Waits for `shortcuts run` off the main thread so a failing shortcut is reported instead of shown as done.
    /// A stuck shortcut is stopped after a minute, and cancelling the workflow stops it right away.
    private static func runShortcut(named name: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name]
        // Launch and cancel share a lock, so a cancel either stops the launch or sees the running process.
        let cancelled = OSAllocatedUnfairLock(initialState: false)
        let timedOut = OSAllocatedUnfairLock(initialState: false)
        let timeout = Task {
            try await Task.sleep(for: .seconds(60))
            timedOut.withLock { didTimeOut in
                guard process.isRunning else { return }
                didTimeOut = true
                process.terminate()
            }
        }
        defer { timeout.cancel() }
        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
                let launchError: (any Error)? = cancelled.withLock { isCancelled in
                    guard !isCancelled else { return CancellationError() }
                    do {
                        try process.run()
                        return nil
                    } catch {
                        return error
                    }
                }
                if let launchError { continuation.resume(throwing: launchError) }
            }
        } onCancel: {
            cancelled.withLock { isCancelled in
                isCancelled = true
                // Terminating a process that never launched raises an exception.
                if process.isRunning { process.terminate() }
            }
        }
        try Task.checkCancellation()
        if timedOut.withLock({ $0 }) { throw AgentActionError.shortcutTimedOut }
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
