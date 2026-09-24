import ApplicationServices
import AppKit
import Carbon.HIToolbox
import CryptoKit
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
        case .accessibilityRequired: "Accessibility permission is required"
        case .noFocusedElement: "No editable text field is focused"
        case .sensitiveTarget: "SayKuku never reads or writes sensitive fields"
        case .targetChanged: "The text target changed. Trigger SayKuku again."
        case .writeFailed: "The target app did not accept the text"
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
    let selectedTextHash: String
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
    private let sensitiveBundleFragments = [
        "1password", "lastpass", "bitwarden", "dashlane", "keepass", "bank", "wallet"
    ]

    func captureTarget() throws -> TextTargetSnapshot {
        guard AXIsProcessTrusted() else { throw TextInteractionError.accessibilityRequired }
        guard let app = NSWorkspace.shared.frontmostApplication else { throw TextInteractionError.noFocusedElement }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        let focusedElement = focusedElement(for: app.processIdentifier)
        let element = focusedElement.flatMap(preferredTextElement(from:))
        let window = element.flatMap(window(of:))
            ?? focusedElement.flatMap(window(of:))
            ?? copyAttribute(application, kAXFocusedWindowAttribute)
        guard element != nil || window != nil else { throw TextInteractionError.noFocusedElement }
        let title: String = window.flatMap { copyAttribute($0, kAXTitleAttribute) } ?? ""
        let bundleID = app.bundleIdentifier ?? ""
        let range = element.flatMap(selectedRange(of:))
        let value = element.flatMap { normalizedValue(of: $0, selectedRange: range) }
        let selectedText = element.map { selectedText(of: $0, value: value, range: range) } ?? ""
        let sensitive = isSensitive(element: element, bundleID: bundleID, windowTitle: title)

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
            selectedText: selectedText,
            selectedTextHash: Self.hash(selectedText),
            valueBefore: value,
            isSensitive: sensitive
        )
    }

    private func validate(_ snapshot: TextTargetSnapshot) throws -> AXUIElement? {
        guard !snapshot.isSensitive else { throw TextInteractionError.sensitiveTarget }
        guard !IsSecureEventInputEnabled() else { throw TextInteractionError.sensitiveTarget }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier == snapshot.appPID,
              app.bundleIdentifier == snapshot.bundleID else { throw TextInteractionError.targetChanged }

        let application = AXUIElementCreateApplication(snapshot.appPID)
        let focusedElement = focusedElement(for: snapshot.appPID)
        let element = focusedElement.flatMap(preferredTextElement(from:))
        let currentWindow = element.flatMap(window(of:))
            ?? focusedElement.flatMap(window(of:))
            ?? copyAttribute(application, kAXFocusedWindowAttribute)
        guard element != nil || currentWindow != nil else { throw TextInteractionError.targetChanged }
        guard sameWindow(snapshot.windowElement, currentWindow) else {
            throw TextInteractionError.targetChanged
        }
        if let original = snapshot.textElement {
            guard let element, CFEqual(original, element) else { throw TextInteractionError.targetChanged }
        }
        let currentTitle: String = currentWindow.flatMap { copyAttribute($0, kAXTitleAttribute) } ?? ""
        guard !isSensitive(element: element, bundleID: snapshot.bundleID, windowTitle: currentTitle) else {
            throw TextInteractionError.sensitiveTarget
        }

        let range = element.flatMap(selectedRange(of:))
        let value = element.flatMap { normalizedValue(of: $0, selectedRange: range) }
        if snapshot.valueBefore != nil, snapshot.selectedRange != nil {
            guard let element else { throw TextInteractionError.targetChanged }
            let selectedText = selectedText(of: element, value: value, range: range)
            guard value == snapshot.valueBefore,
                  range == snapshot.selectedRange,
                  Self.hash(selectedText) == snapshot.selectedTextHash else {
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
                if try await waitForExpectedValue(expectedValue, in: snapshot) {
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
        _ = try validate(snapshot)
        let pasteboard = NSPasteboard.general
        let previous = Self.snapshot(of: pasteboard)
        let sessionID = UUID().uuidString
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setString(sessionID, forType: Self.pasteSessionType)
        guard pasteboard.writeObjects([item]), pasteboard.string(forType: .string) == text else {
            throw TextInteractionError.writeFailed
        }

        do {
            try await Task.sleep(for: .milliseconds(80))
            _ = try validate(snapshot)
            try await postPasteCommand()
        } catch {
            restore(previous, ifOwnedBy: sessionID, on: pasteboard)
            throw error
        }

        let expectedValue = Self.expectedValue(afterWriting: text, to: snapshot)
        if let expectedValue, try await waitForExpectedValue(expectedValue, in: snapshot) {
            try? await Task.sleep(for: .milliseconds(180))
            restore(previous, ifOwnedBy: sessionID, on: pasteboard)
            Self.logger.info("Text delivered with verified synthetic paste")
            return .verified
        }

        if expectedValue != nil,
           let current = currentValue(in: snapshot),
           current == snapshot.valueBefore {
            Self.logger.error("Synthetic paste posted but readable target text did not change")
            throw TextInteractionError.writeFailed
        }

        try? await Task.sleep(for: .milliseconds(350))
        restore(previous, ifOwnedBy: sessionID, on: pasteboard)
        Self.logger.info("Text delivered with synthetic paste; target does not expose verifiable text")
        return .deliveredUnverified
    }

    private func postPasteCommand() async throws {
        guard let source = CGEventSource(stateID: .privateState),
              let commandDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true),
              let pasteDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let pasteUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false),
              let commandUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false) else {
            throw TextInteractionError.writeFailed
        }
        pasteDown.flags = .maskCommand
        pasteUp.flags = .maskCommand
        for event in [commandDown, pasteDown, pasteUp, commandUp] {
            event.post(tap: .cghidEventTap)
            try await Task.sleep(for: .milliseconds(8))
        }
    }

    private func waitForExpectedValue(_ expectedValue: String, in snapshot: TextTargetSnapshot) async throws -> Bool {
        for _ in 0..<10 {
            try await Task.sleep(for: .milliseconds(50))
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
        let application = AXUIElementCreateApplication(snapshot.appPID)
        let currentWindow = window(of: element) ?? copyAttribute(application, kAXFocusedWindowAttribute)
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
        if let element: AXUIElement = copyAttribute(systemWide, kAXFocusedUIElementAttribute),
           processID(of: element) == expectedPID {
            return element
        }
        let application = AXUIElementCreateApplication(expectedPID)
        guard let element: AXUIElement = copyAttribute(application, kAXFocusedUIElementAttribute),
              processID(of: element) == expectedPID else { return nil }
        return element
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
        while !queue.isEmpty, visited < 80 {
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

    private func isSensitive(element: AXUIElement?, bundleID: String, windowTitle: String) -> Bool {
        let elementRole = element.map(role(of:)) ?? ""
        let subrole: String = element.flatMap { copyAttribute($0, kAXSubroleAttribute) } ?? ""
        let lowerBundle = bundleID.lowercased()
        let lowerTitle = windowTitle.lowercased()
        return IsSecureEventInputEnabled()
            || elementRole == "AXSecureTextField"
            || subrole.lowercased().contains("secure")
            || sensitiveBundleFragments.contains(where: lowerBundle.contains)
            || lowerTitle.contains("private browsing")
            || lowerTitle.contains("incognito")
            || lowerTitle.contains("隐私浏览")
    }

    static func snapshot(of pasteboard: NSPasteboard) -> PasteboardSnapshot {
        (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
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
                title: title("选中文字 · \(snapshot.selectedText.count) 字", "Selected text · \(snapshot.selectedText.count) chars"),
                value: snapshot.selectedText
            ))
        }
        if windowTitleAllowed, !snapshot.windowTitle.isEmpty {
            items.append(ContextItem(kind: .window, symbol: "macwindow", title: title("窗口标题", "Window title"), value: snapshot.windowTitle))
        }
        if clipboardAllowed, let clipboard = NSPasteboard.general.string(forType: .string), !clipboard.isEmpty {
            items.append(ContextItem(kind: .clipboard, symbol: "clipboard", title: title("剪贴板 · \(clipboard.count) 字", "Clipboard · \(clipboard.count) chars"), value: clipboard))
        }
        if browserPageAllowed, let url = browserURL(bundleID: snapshot.bundleID), !url.isEmpty {
            items.append(ContextItem(kind: .browser, symbol: "globe", title: title("浏览器页面", "Browser page"), value: url))
        }
        if let session, session.expiresAt > .now {
            items.append(ContextItem(kind: .session, symbol: "bubble.left.and.bubble.right", title: title("最近的交流", "Recent conversation"), value: session.contextSummary))
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
            items.append(ContextItem(
                kind: .knowledge,
                symbol: "books.vertical",
                title: title("已保存的知识", "Saved knowledge"),
                value: knowledge.map { entity in
                    let aliases = entity.aliases.isEmpty ? "(none)" : entity.aliases.joined(separator: ", ")
                    let detail = entity.detail.isEmpty ? "(none)" : entity.detail
                    return "\(entity.name) [\(entity.type.rawValue)] aliases: \(aliases) detail: \(detail)"
                }.joined(separator: "\n")
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
        case .writeText, .answer:
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
