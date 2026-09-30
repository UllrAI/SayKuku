import ApplicationServices
import AppKit
import Carbon.HIToolbox
import Foundation
import os

enum TextInteractionError: LocalizedError {
    case accessibilityRequired
    case noFocusedElement
    case sensitiveTarget
    case targetChanged
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityRequired: localized("Allow Accessibility access for SayKuku first")
        case .noFocusedElement: localized("Click where you want to type first")
        case .sensitiveTarget: localized("SayKuku doesn’t work in password fields or password managers.")
        case .targetChanged: localized("The text field changed. Click back into it and try again.")
        case .writeFailed: localized("This app didn’t accept the text. Try again.")
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
    /// Dictation can target either an exposed text field or a focused window for paste fallback.
    let hasDictationTarget: Bool
    let windowElement: AXUIElement?
    let textElement: AXUIElement?
    /// The focused element when it exposes a selection outside the recognized text field.
    let selectionElement: AXUIElement?
    let selectedRange: CFRange?
    let selectedText: String
    let valueBefore: String?
    let isSensitive: Bool
    /// The caret's screen rectangle in AppKit coordinates, for placing the overlay. Only read
    /// when the overlay follows the cursor.
    let caretFrame: CGRect?
}

extension TextTargetSnapshot {
    /// The display name tells the model what a niche app is; the bundle ID keeps it unambiguous.
    var promptAppName: String { "\(appName) (\(bundleID))" }

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

/// The focused app's text as the voice workflows use it; tests pass a fake.
@MainActor
protocol TextWriting: AnyObject {
    /// Calls `onSafeTarget` after checking the focused field, before reading optional text and geometry.
    func captureTarget(
        requiringWindow: Bool, includingCaretFrame: Bool, onSafeTarget: () -> Void
    ) throws -> TextTargetSnapshot
    func write(_ text: String, to snapshot: TextTargetSnapshot) async throws -> TextWriteOutcome
    func currentValue(of snapshot: TextTargetSnapshot) -> String?
    func browserPageAddress(in snapshot: TextTargetSnapshot) -> String?
    func visibleText(in snapshot: TextTargetSnapshot) -> String
    func replacementSnapshot(for write: VerifiedWrite) throws -> TextTargetSnapshot
}

@MainActor
final class TextInteraction: TextWriting {
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
    /// Processes already asked to expose their Electron accessibility tree.
    private var manualAccessibilityPIDs: Set<pid_t> = []

    /// Dictation needs a window to write into; the Agent can also answer, open links or run shortcuts
    /// from the desktop, so `requiringWindow: false` returns a snapshot without a window or text field.
    /// `includingCaretFrame` reads the caret rectangle, which only the cursor-following overlay needs.
    func captureTarget(
        requiringWindow: Bool = true, includingCaretFrame: Bool = false,
        onSafeTarget: () -> Void = {}
    ) throws -> TextTargetSnapshot {
        guard AXIsProcessTrusted() else { throw TextInteractionError.accessibilityRequired }
        guard let app = NSWorkspace.shared.frontmostApplication else { throw TextInteractionError.noFocusedElement }
        let application = applicationElement(for: app.processIdentifier)
        let focusedElement = focusedElement(for: app.processIdentifier)
        let element = focusedElement.flatMap(preferredTextElement(from:))
        let resolveWindow = {
            element.flatMap(self.window(of:))
                ?? focusedElement.flatMap(self.window(of:))
                ?? self.copyAttribute(application, kAXFocusedWindowAttribute)
        }
        let checkedWindow = requiringWindow ? resolveWindow() : nil
        if requiringWindow, element == nil, checkedWindow == nil { throw TextInteractionError.noFocusedElement }
        let bundleID = app.bundleIdentifier ?? ""
        let sensitive = OSSignposter.performance.withIntervalSignpost("secure target check") {
            isSensitive(element: element, bundleID: bundleID)
                || isSensitive(element: focusedElement, bundleID: bundleID)
        }
        guard !sensitive else { throw TextInteractionError.sensitiveTarget }
        onSafeTarget()
        let window = checkedWindow ?? (requiringWindow ? nil : resolveWindow())
        let title: String = window.flatMap { copyAttribute($0, kAXTitleAttribute) } ?? ""
        let range = element.flatMap(selectedRange(of:))
        let value = element.flatMap { normalizedValue(of: $0, selectedRange: range) }
        var selection = element.map { self.selectedText(of: $0, value: value, range: range) } ?? ""
        var selectionElement: AXUIElement?
        if selection.isEmpty, let focusedElement,
           element.map({ !CFEqual($0, focusedElement) }) ?? true {
            let focusedSelection = selectedText(of: focusedElement, value: nil, range: nil)
            if !focusedSelection.isEmpty {
                selection = focusedSelection
                selectionElement = focusedElement
            }
        }
        let caret = includingCaretFrame
            ? element.flatMap { element in range.flatMap { caretFrame(of: element, at: $0) } }
            : nil

        Log.text.info(
            "Captured target bundle=\(bundleID, privacy: .public) role=\(element.map(self.role(of:)) ?? "unavailable", privacy: .public) focusRole=\(focusedElement.map(self.role(of:)) ?? "unavailable", privacy: .public) readable=\(value != nil, privacy: .public) selectionLength=\(selection.count, privacy: .public)"
        )
        return TextTargetSnapshot(
            appPID: app.processIdentifier,
            bundleID: bundleID,
            appName: app.localizedName ?? bundleID,
            windowTitle: title,
            hasDictationTarget: element != nil || window != nil,
            windowElement: window,
            textElement: element,
            selectionElement: selectionElement,
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
        guard !isSensitive(element: element, bundleID: snapshot.bundleID),
              !isSensitive(element: focusedElement, bundleID: snapshot.bundleID) else {
            throw TextInteractionError.sensitiveTarget
        }
        if let original = snapshot.selectionElement {
            guard let focusedElement, CFEqual(original, focusedElement),
                  selectedText(of: focusedElement, value: nil, range: nil) == snapshot.selectedText else {
                throw TextInteractionError.targetChanged
            }
        }

        if let element, snapshot.valueBefore != nil, snapshot.selectedRange != nil {
            let range = selectedRange(of: element)
            let value = normalizedValue(of: element, selectedRange: range)
            guard value == snapshot.valueBefore,
                  range == snapshot.selectedRange,
                  (snapshot.selectionElement != nil
                    || selectedText(of: element, value: value, range: range) == snapshot.selectedText) else {
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
        // A selection exposed by the focused container may not belong to this text field.
        guard snapshot.selectionElement == nil,
              let expectedValue = Self.expectedValue(afterWriting: text, to: snapshot),
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

    /// Text visible in the captured window, for Voice Agent commands such as "reply to this". Walks the
    /// window breadth-first within `ScreenText`'s budgets and skips the focused field, whose text is
    /// already the selection or last insertion. Sensitive targets and windows exposing no text give "".
    func visibleText(in snapshot: TextTargetSnapshot) -> String {
        guard !snapshot.isSensitive, let window = snapshot.windowElement else { return "" }
        enableElectronAccessibility(for: snapshot.appPID)
        let deadline = ContinuousClock.now + ScreenText.timeBudget
        var queue: [(element: AXUIElement, path: [Int])] = [(window, [])]
        var next = 0
        let nodes = AnyIterator<ScreenText.Node> {
            guard next < queue.count else { return nil }
            let (element, path) = queue[next]
            next += 1
            let node = self.screenTextNode(element, path: path, focused: snapshot.textElement)
            if node.descends { self.enqueueChildren(of: element, path: path, into: &queue) }
            return node.node
        }
        let text = ScreenText.collect(IteratorSequence(nodes), deadline: deadline)
        Log.text.info(
            "Read visible text bundle=\(snapshot.bundleID, privacy: .public) nodes=\(next, privacy: .public) characters=\(text.count, privacy: .public)"
        )
        return text
    }

    /// Reads a node's text only for text roles. Its children are skipped once it has text, so a cell and
    /// the static text inside it aren't both read, and always for the focused field and password fields.
    private func screenTextNode(
        _ element: AXUIElement, path: [Int], focused: AXUIElement?
    ) -> (node: ScreenText.Node, descends: Bool) {
        if let focused, CFEqual(element, focused) { return (ScreenText.Node(path: path, role: "", text: nil), false) }
        let elementRole = role(of: element)
        if elementRole == "AXSecureTextField"
            || (["AXTextField", "AXTextArea"].contains(elementRole) && hasSecureSubrole(element)) {
            return (ScreenText.Node(path: path, role: "AXSecureTextField", text: nil), false)
        }
        guard ScreenText.textRoles.contains(elementRole) else {
            return (ScreenText.Node(path: path, role: elementRole, text: nil), true)
        }
        let value: String? = copyAttribute(element, kAXValueAttribute)
        let text: String? = value?.isEmpty == false ? value : copyAttribute(element, kAXTitleAttribute)
        return (ScreenText.Node(path: path, role: elementRole, text: text), text?.isEmpty != false)
    }

    /// `childElements` merges several attributes that can list the same child. The queue never grows past
    /// the node limit, since nodes beyond it would not be visited.
    private func enqueueChildren(
        of element: AXUIElement, path: [Int], into queue: inout [(element: AXUIElement, path: [Int])]
    ) {
        var siblings: [AXUIElement] = []
        for child in childElements(of: element) where queue.count < ScreenText.nodeLimit {
            guard !siblings.contains(where: { CFEqual($0, child) }) else { continue }
            queue.append((child, path + [siblings.count]))
            siblings.append(child)
        }
    }

    /// Electron apps build their accessibility tree only for assistive apps they recognize, or once
    /// `AXManualAccessibility` is set on the app. Tried once per process; a failure leaves the text empty.
    private func enableElectronAccessibility(for pid: pid_t) {
        guard manualAccessibilityPIDs.insert(pid).inserted,
              let bundleURL = NSRunningApplication(processIdentifier: pid)?.bundleURL else { return }
        let framework = bundleURL.appendingPathComponent("Contents/Frameworks/Electron Framework.framework")
        guard FileManager.default.fileExists(atPath: framework.path) else { return }
        AXUIElementSetAttributeValue(applicationElement(for: pid), "AXManualAccessibility" as CFString, kCFBooleanTrue)
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
        guard !Self.isSensitiveWithoutAccessibility(bundleID: bundleID) else { return true }
        guard let element else { return false }
        return role(of: element) == "AXSecureTextField" || hasSecureSubrole(element)
    }

    /// Web password inputs keep the text field role and mark themselves with a secure subrole.
    private func hasSecureSubrole(_ element: AXUIElement) -> Bool {
        let subrole: String = copyAttribute(element, kAXSubroleAttribute) ?? ""
        return subrole.lowercased().contains("secure")
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

/// Budgets and rules for the focused window's visible text. The budgets keep a large window, such as a
/// mail list or an IDE, from stalling the main thread; the text is a sample, not the whole window.
enum ScreenText {
    static let nodeLimit = 300
    static let timeBudget = Duration.milliseconds(150)
    static let characterLimit = 2_000
    /// Roles whose `AXValue` or `AXTitle` is read.
    static let textRoles: Set<String> = ["AXStaticText", "AXTextArea", "AXTextField", "AXCell", "AXLink", "AXHeading"]

    struct Node {
        /// Child indices from the window down, so text found breadth-first can be put back in reading order.
        let path: [Int]
        let role: String
        let text: String?
    }

    /// Visits `nodes` until the node, time or character budget runs out, then joins their text in tree
    /// order, one line per node, dropping a line that repeats the one before it. Nodes are pulled lazily,
    /// so none is read past a budget.
    static func collect(_ nodes: some Sequence<Node>, deadline: ContinuousClock.Instant) -> String {
        var lines: [(path: [Int], text: String)] = []
        var characters = 0
        var visited = 0
        var iterator = nodes.makeIterator()
        while visited < nodeLimit, characters < characterLimit, ContinuousClock.now < deadline,
              let node = iterator.next() {
            visited += 1
            guard textRoles.contains(node.role),
                  let text = node.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { continue }
            let line = String(text.prefix(characterLimit - characters))
            lines.append((node.path, line))
            // Counts the line break that joins it to the next line.
            characters += line.count + 1
        }
        var result: [String] = []
        for line in lines.sorted(by: { $0.path.lexicographicallyPrecedes($1.path) }) where line.text != result.last {
            result.append(line.text)
        }
        return result.joined(separator: "\n")
    }
}

private func == (lhs: CFRange?, rhs: CFRange?) -> Bool {
    switch (lhs, rhs) {
    case (nil, nil): true
    case let (left?, right?): left.location == right.location && left.length == right.length
    default: false
    }
}
