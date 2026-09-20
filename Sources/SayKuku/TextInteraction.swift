import ApplicationServices
import AppKit
import CryptoKit
import Foundation

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
        case .sensitiveTarget: "SayKuku never reads or writes sensitive fields"
        case .targetChanged: "The text target changed. Trigger SayKuku again."
        case .writeFailed: "The target app did not accept the text"
        }
    }
}

struct TextTargetSnapshot: @unchecked Sendable {
    let appPID: pid_t
    let bundleID: String
    let appName: String
    let windowTitle: String
    let windowElement: AXUIElement?
    let element: AXUIElement
    let selectedRange: CFRange?
    let selectedText: String
    let selectedTextHash: String
    let valueBefore: String?
    let capturedAt: Date
    let isSensitive: Bool
}

@MainActor
final class TextInteraction {
    private let sensitiveBundleFragments = [
        "1password", "lastpass", "bitwarden", "dashlane", "keepass", "bank", "wallet"
    ]

    func captureTarget() throws -> TextTargetSnapshot {
        guard AXIsProcessTrusted() else { throw TextInteractionError.accessibilityRequired }
        guard let app = NSWorkspace.shared.frontmostApplication else { throw TextInteractionError.noFocusedElement }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        guard let element: AXUIElement = copyAttribute(application, kAXFocusedUIElementAttribute) else {
            throw TextInteractionError.noFocusedElement
        }
        let bundleID = app.bundleIdentifier ?? ""
        let appName = app.localizedName ?? bundleID
        let role: String = copyAttribute(element, kAXRoleAttribute) ?? ""
        let subrole: String = copyAttribute(element, kAXSubroleAttribute) ?? ""
        let window: AXUIElement? = copyAttribute(application, kAXFocusedWindowAttribute)
        let title: String = window.flatMap { copyAttribute($0, kAXTitleAttribute) } ?? ""
        let selectedText: String = copyAttribute(element, kAXSelectedTextAttribute) ?? ""
        let range = selectedRange(of: element)
        let lowerBundle = bundleID.lowercased()
        let lowerTitle = title.lowercased()
        let sensitive = role == "AXSecureTextField"
            || subrole.lowercased().contains("secure")
            || sensitiveBundleFragments.contains(where: lowerBundle.contains)
            || lowerTitle.contains("private browsing")
            || lowerTitle.contains("incognito")
            || lowerTitle.contains("隐私浏览")

        return TextTargetSnapshot(
            appPID: app.processIdentifier,
            bundleID: bundleID,
            appName: appName,
            windowTitle: title,
            windowElement: window,
            element: element,
            selectedRange: range,
            selectedText: selectedText,
            selectedTextHash: Self.hash(selectedText),
            valueBefore: copyAttribute(element, kAXValueAttribute),
            capturedAt: .now,
            isSensitive: sensitive
        )
    }

    func validate(_ snapshot: TextTargetSnapshot) throws {
        guard !snapshot.isSensitive else { throw TextInteractionError.sensitiveTarget }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier == snapshot.appPID,
              app.bundleIdentifier == snapshot.bundleID else { throw TextInteractionError.targetChanged }
        let application = AXUIElementCreateApplication(snapshot.appPID)
        guard let currentElement: AXUIElement = copyAttribute(application, kAXFocusedUIElementAttribute),
              CFEqual(currentElement, snapshot.element) else { throw TextInteractionError.targetChanged }
        let currentWindow: AXUIElement? = copyAttribute(application, kAXFocusedWindowAttribute)
        let currentTitle: String = currentWindow.flatMap { copyAttribute($0, kAXTitleAttribute) } ?? ""
        let sameWindow = snapshot.windowElement == nil && currentWindow == nil
            || (snapshot.windowElement != nil && currentWindow != nil && CFEqual(snapshot.windowElement, currentWindow))
        guard sameWindow, currentTitle == snapshot.windowTitle,
              selectedRange(of: currentElement) == snapshot.selectedRange else { throw TextInteractionError.targetChanged }
        let selectedText: String = copyAttribute(currentElement, kAXSelectedTextAttribute) ?? ""
        guard Self.hash(selectedText) == snapshot.selectedTextHash else { throw TextInteractionError.targetChanged }
    }

    func write(_ text: String, to snapshot: TextTargetSnapshot) async throws {
        try validate(snapshot)
        var settable = DarwinBoolean(false)
        let queryStatus = AXUIElementIsAttributeSettable(snapshot.element, kAXSelectedTextAttribute as CFString, &settable)
        if queryStatus == .success, settable.boolValue,
           AXUIElementSetAttributeValue(snapshot.element, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success {
            guard try await waitForWrite(text, to: snapshot) else { throw TextInteractionError.writeFailed }
            return
        }
        try await paste(text, to: snapshot)
    }

    func currentValue(of snapshot: TextTargetSnapshot) -> String? {
        copyAttribute(snapshot.element, kAXValueAttribute)
    }

    private func paste(_ text: String, to snapshot: TextTargetSnapshot) async throws {
        try validate(snapshot)
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            throw TextInteractionError.writeFailed
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)

        guard try await waitForWrite(text, to: snapshot) else {
            throw TextInteractionError.writeFailed
        }
        guard pasteboard.string(forType: .string) == text else { return }
        pasteboard.clearContents()
        if let previous {
            pasteboard.setString(previous, forType: .string)
        }
    }

    private func didWrite(_ text: String, to snapshot: TextTargetSnapshot) -> Bool {
        guard isSameTarget(snapshot), let current = currentValue(of: snapshot) else { return false }
        if let expected = Self.expectedValue(afterWriting: text, to: snapshot) {
            return current == expected
        }
        guard let previous = snapshot.valueBefore else { return false }
        return current != previous && current.contains(text)
    }

    private func waitForWrite(_ text: String, to snapshot: TextTargetSnapshot) async throws -> Bool {
        for _ in 0..<8 {
            try await Task.sleep(for: .milliseconds(80))
            if didWrite(text, to: snapshot) { return true }
        }
        return false
    }

    private func isSameTarget(_ snapshot: TextTargetSnapshot) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier == snapshot.appPID,
              app.bundleIdentifier == snapshot.bundleID else { return false }
        let application = AXUIElementCreateApplication(snapshot.appPID)
        guard let element: AXUIElement = copyAttribute(application, kAXFocusedUIElementAttribute),
              CFEqual(element, snapshot.element) else { return false }
        let window: AXUIElement? = copyAttribute(application, kAXFocusedWindowAttribute)
        if let originalWindow = snapshot.windowElement, let window {
            return CFEqual(originalWindow, window)
        }
        let title: String = window.flatMap { copyAttribute($0, kAXTitleAttribute) } ?? ""
        return snapshot.windowElement == nil && window == nil && title == snapshot.windowTitle
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

    private func copyAttribute<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? T
    }

    private static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

enum ContextCollector {
    @MainActor
    static func collect(
        snapshot: TextTargetSnapshot,
        selectedTextAllowed: Bool,
        currentAppAllowed: Bool,
        windowTitleAllowed: Bool,
        clipboardAllowed: Bool,
        browserPageAllowed: Bool,
        session: AgentSession?,
        knowledge: [KnowledgeEntity]
    ) -> [ContextItem] {
        guard !snapshot.isSensitive else { return [] }
        var items: [ContextItem] = []
        if currentAppAllowed {
            items.append(ContextItem(kind: .app, symbol: "app", title: snapshot.appName, value: snapshot.bundleID))
        }
        if selectedTextAllowed, !snapshot.selectedText.isEmpty {
            items.append(ContextItem(
                kind: .selectedText,
                symbol: "text.quote",
                title: "Selected text · \(snapshot.selectedText.count)",
                value: snapshot.selectedText
            ))
        }
        if windowTitleAllowed, !snapshot.windowTitle.isEmpty {
            items.append(ContextItem(kind: .window, symbol: "macwindow", title: "Window", value: snapshot.windowTitle))
        }
        if clipboardAllowed, let clipboard = NSPasteboard.general.string(forType: .string), !clipboard.isEmpty {
            items.append(ContextItem(kind: .clipboard, symbol: "clipboard", title: "Clipboard · \(clipboard.count)", value: clipboard))
        }
        if browserPageAllowed, let url = browserURL(bundleID: snapshot.bundleID), !url.isEmpty {
            items.append(ContextItem(kind: .browser, symbol: "globe", title: "Browser page", value: url))
        }
        if let session, session.expiresAt > .now {
            items.append(ContextItem(kind: .session, symbol: "bubble.left.and.bubble.right", title: "Recent session", value: session.contextSummary))
        }
        let haystack = ([snapshot.selectedText, snapshot.windowTitle] + (session.map { [$0.userCommand, $0.response] } ?? []))
            .joined(separator: " ")
        let matches = knowledge.filter { entity in
            haystack.localizedCaseInsensitiveContains(entity.name)
                || entity.aliases.contains(where: haystack.localizedCaseInsensitiveContains)
        }.prefix(8)
        if !matches.isEmpty {
            items.append(ContextItem(
                kind: .knowledge,
                symbol: "books.vertical",
                title: "Relevant Knowledge",
                value: matches.map { "\($0.name) [\($0.type.rawValue)] aliases: \($0.aliases.joined(separator: ", "))" }.joined(separator: "\n")
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

enum AgentActionExecutor {
    @MainActor
    static func execute(_ response: AgentResponse) throws {
        switch response.action {
        case .writeText:
            return
        case .openURL:
            guard let value = response.url, let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased()) else {
                throw QwenError.invalidResponse
            }
            NSWorkspace.shared.open(url)
        case .webSearch:
            guard let query = response.query?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "https://www.google.com/search?q=\(query)") else { throw QwenError.invalidResponse }
            NSWorkspace.shared.open(url)
        case .runShortcut:
            guard let name = response.shortcutName, !name.isEmpty else { throw QwenError.invalidResponse }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["run", name]
            try process.run()
        }
    }
}

private func == (lhs: CFRange?, rhs: CFRange?) -> Bool {
    switch (lhs, rhs) {
    case (nil, nil): true
    case let (left?, right?): left.location == right.location && left.length == right.length
    default: false
    }
}
