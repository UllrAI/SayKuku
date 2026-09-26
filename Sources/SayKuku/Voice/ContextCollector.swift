import AppKit

enum ContextCollector {
    /// Longest selected text or previous output sent to Qwen.
    static let textLimit = 10_000
    static let clipboardLimit = 4_000

    /// A text item titled with its length; text past `limit` is not sent, and the title says so.
    static func textItem(
        kind: ContextItem.Kind, symbol: String, title: String, value: String, limit: Int
    ) -> ContextItem {
        let isClipped = value.count > limit
        let length = isClipped ? localized("first \(limit) characters") : localized("\(value.count) characters")
        return ContextItem(
            kind: kind, symbol: symbol, title: "\(title) · \(length)",
            value: clipped(value, to: limit), isClipped: isClipped
        )
    }

    /// What SayKuku last wrote, titled with its start so people see which text the Agent would edit.
    static func previousOutputItem(_ text: String) -> ContextItem {
        let start = clipped(text, to: 20).split(whereSeparator: \.isNewline).joined(separator: " ")
        return ContextItem(
            kind: .previousOutput, symbol: "arrow.uturn.backward", title: localized("Just wrote: \(start)"),
            value: clipped(text, to: textLimit), isClipped: text.count > textLimit
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
        screenText: String,
        sessions: [AgentSession],
        domains: Set<DomainPreset>,
        memory: [MemoryEntity]
    ) -> [ContextItem] {
        guard !snapshot.isSensitive else { return [] }
        var items: [ContextItem] = []
        if currentAppAllowed {
            items.append(ContextItem(kind: .app, symbol: "app", title: snapshot.appName, value: snapshot.promptAppName))
        }
        if selectedTextAllowed, !snapshot.selectedText.isEmpty {
            items.append(textItem(
                kind: .selectedText,
                symbol: "text.quote",
                title: localized("Selected text"),
                value: snapshot.selectedText,
                limit: textLimit
            ))
        }
        if windowTitleAllowed, !snapshot.windowTitle.isEmpty {
            items.append(ContextItem(kind: .window, symbol: "macwindow", title: localized("Window title"), value: snapshot.windowTitle))
        }
        if clipboardAllowed, !PasteboardPolicy.isPrivate(NSPasteboard.general.types ?? []),
           let clipboard = NSPasteboard.general.string(forType: .string), !clipboard.isEmpty {
            items.append(textItem(
                kind: .clipboard,
                symbol: "clipboard",
                title: localized("Clipboard"),
                value: clipboard,
                limit: clipboardLimit
            ))
        }
        if let browserPage, !browserPage.isEmpty {
            items.append(ContextItem(kind: .browser, symbol: "globe", title: localized("Browser page"), value: browserPage))
        }
        if !screenText.isEmpty {
            items.append(textItem(
                kind: .screen,
                symbol: "text.viewfinder",
                title: localized("Text on screen"),
                value: screenText,
                limit: ScreenText.characterLimit
            ))
        }
        if !sessions.isEmpty {
            items.append(ContextItem(
                kind: .session, symbol: "bubble.left.and.bubble.right", title: localized("Recent conversation"),
                value: QwenReasoningClient.agentSessionText(sessions)
            ))
        }
        if !domains.isEmpty {
            items.append(ContextItem(
                kind: .domain,
                symbol: "text.bubble",
                title: localized("Domains"),
                value: MemoryPrompt.render(entities: [], domains: domains, purpose: .agent)
            ))
        }
        if !memory.isEmpty {
            items.append(ContextItem(
                kind: .memory,
                symbol: "books.vertical",
                title: localized("Memory"),
                value: MemoryPrompt.render(entities: memory, purpose: .agent)
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
