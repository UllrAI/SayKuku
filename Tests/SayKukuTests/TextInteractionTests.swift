import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation
import Testing
@testable import SayKuku

@Suite("Text write verification")
struct TextWriteVerificationTests {
    @Test("insertion builds the exact expected field value")
    func insertion() {
        let snapshot = target(value: "你好世界", range: CFRange(location: 2, length: 0))
        #expect(TextInteraction.expectedValue(afterWriting: "，", to: snapshot) == "你好，世界")
    }

    @Test("deleting the previous output replaces its range with nothing")
    func deletion() {
        let snapshot = target(value: "会议改到周四，方案带上。", range: CFRange(location: 7, length: 5))
        #expect(TextInteraction.expectedValue(afterWriting: "", to: snapshot) == "会议改到周四，")
    }

    @Test("selection replacement uses UTF-16 accessibility ranges")
    func replacement() {
        let snapshot = target(value: "A😀BC", range: CFRange(location: 1, length: 2))
        #expect(TextInteraction.expectedValue(afterWriting: "好", to: snapshot) == "A好BC")
    }

    @Test("only an untouched caret and value count as an ignored Accessibility write")
    func ignoredInsertion() {
        let snapshot = target(value: "A😀BC", range: CFRange(location: 1, length: 2))
        // AXValue lags behind, but the caret already sits after the inserted text.
        #expect(!TextInteraction.insertionWasIgnored(caret: CFRange(location: 2, length: 0), value: "A😀BC", snapshot: snapshot))
        #expect(!TextInteraction.insertionWasIgnored(caret: CFRange(location: 1, length: 2), value: "A好BC", snapshot: snapshot))
        #expect(!TextInteraction.insertionWasIgnored(caret: nil, value: nil, snapshot: snapshot))
        #expect(TextInteraction.insertionWasIgnored(caret: CFRange(location: 1, length: 2), value: "A😀BC", snapshot: snapshot))
    }

    @Test("the Agent is told whether a text field is focused, unknown within a window, or absent")
    func agentTextField() {
        let element = AXUIElementCreateApplication(getpid())
        #expect(target(value: nil, range: nil, window: element, text: element).agentTextField == .focused)
        #expect(target(value: nil, range: nil, window: element).agentTextField == .unknown)
        #expect(target(value: nil, range: nil).agentTextField == .absent)
    }

    @Test("dictation joins ASCII words without changing Chinese or punctuation")
    func dictationSpacing() {
        #expect(DictationTextJoiner.join("nice", to: target(value: "helloWorld", range: CFRange(location: 5, length: 0))) == " nice ")
        #expect(DictationTextJoiner.join("世界", to: target(value: "你好。", range: CFRange(location: 2, length: 0))) == "世界")
        #expect(DictationTextJoiner.join("B", to: target(value: "A😀C", range: CFRange(location: 3, length: 0))) == "B ")
        #expect(DictationTextJoiner.join("hello", to: target(value: nil, range: nil)) == "hello")
    }

    @Test("invalid accessibility ranges cannot be treated as verified")
    func invalidRange() {
        let snapshot = target(value: "abc", range: CFRange(location: 4, length: 0))
        #expect(TextInteraction.expectedValue(afterWriting: "x", to: snapshot) == nil)
    }

    @Test("unreadable accessibility state is not treated as verifiable")
    func unreadableTarget() {
        let snapshot = target(value: nil, range: nil)
        #expect(TextInteraction.expectedValue(afterWriting: "text", to: snapshot) == nil)
    }

    @Test("clipboard snapshots preserve every pasteboard type")
    @MainActor
    func clipboardSnapshot() {
        let pasteboard = NSPasteboard(name: .init("SayKukuTests.TextWriteVerification"))
        let customType = NSPasteboard.PasteboardType("com.saykuku.tests.custom")
        let item = NSPasteboardItem()
        item.setString("original", forType: .string)
        item.setData(Data([0x01, 0x02, 0x03]), forType: customType)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])

        let snapshot = TextInteraction.snapshot(of: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("temporary", forType: .string)
        TextInteraction.restore(snapshot, to: pasteboard)

        #expect(pasteboard.string(forType: .string) == "original")
        #expect(pasteboard.data(forType: customType) == Data([0x01, 0x02, 0x03]))
        pasteboard.releaseGlobally()
    }

    @Test("clipboard backup skips file promises and extra image renditions")
    func clipboardBackupTypes() {
        let custom = NSPasteboard.PasteboardType("com.saykuku.tests.custom")
        let promise = NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url")
        let types = PasteboardPolicy.backupTypes([.string, promise, .tiff, .png, custom, .fileURL])
        #expect(types == [.string, .tiff, custom, .fileURL])
    }

    @Test("concealed or transient clipboard content is private")
    func privateClipboard() {
        #expect(PasteboardPolicy.isPrivate([.string, PasteboardPolicy.concealedType]))
        #expect(PasteboardPolicy.isPrivate([.string, PasteboardPolicy.transientType]))
        #expect(!PasteboardPolicy.isPrivate([.string, PasteboardPolicy.autoGeneratedType]))
        #expect(!PasteboardPolicy.isPrivate([.string]))
    }

    @Test("sensitive apps are matched by explicit bundle ID prefixes")
    func sensitiveApps() {
        #expect(SensitiveApps.contains(bundleID: "com.1password.1password"))
        #expect(SensitiveApps.contains(bundleID: "com.agilebits.onepassword7"))
        #expect(SensitiveApps.contains(bundleID: "com.bitwarden.desktop"))
        #expect(SensitiveApps.contains(bundleID: "org.keepassxc.keepassxc"))
        #expect(SensitiveApps.contains(bundleID: "com.apple.Passwords"))
        #expect(!SensitiveApps.contains(bundleID: "com.example.bankside-notes"))
        #expect(!SensitiveApps.contains(bundleID: "com.example.walletpaper"))
        #expect(!SensitiveApps.contains(bundleID: "com.apple.Safari"))
        // The pre-start check refuses password managers without reading any element.
        #expect(TextInteraction.isSensitiveWithoutAccessibility(bundleID: "com.1password.1password"))
    }

    @Test("every search engine encodes each reserved query character")
    func searchEngineURL() {
        let prefixes: [SearchEngine: String] = [
            .google: "https://www.google.com/search?q=",
            .bing: "https://www.bing.com/search?q=",
            .baidu: "https://www.baidu.com/s?wd=",
            .duckduckgo: "https://duckduckgo.com/?q=",
        ]
        #expect(Set(prefixes.keys) == Set(SearchEngine.allCases))
        for (engine, prefix) in prefixes {
            #expect(engine.url(for: "C++ & Rust")?.absoluteString == prefix + "C%2B%2B%20%26%20Rust")
            #expect(engine.url(for: "a=b#c?d/e")?.absoluteString == prefix + "a%3Db%23c%3Fd%2Fe")
            #expect(engine.url(for: "你好 swift-6_x.y~")?.absoluteString == prefix + "%E4%BD%A0%E5%A5%BD%20swift-6_x.y~")
        }
    }

    @Test("the first search engine follows the region, and Baidu is the only localized name")
    func searchEngineDefaults() {
        #expect(SearchEngine.defaultEngine(for: .beijing) == .bing)
        #expect(SearchEngine.defaultEngine(for: .singapore) == .google)
        #expect(SearchEngine.baidu.title == localized("Baidu"))
        #expect(SearchEngine.google.title == "Google")
        #expect(SearchEngine.duckduckgo.title == "DuckDuckGo")
    }

    @Test("links, searches and shortcuts chosen with untrusted context wait for confirmation")
    func actionConfirmation() {
        let open = AgentResponse(transcript: "打开官网", action: .openURL, url: "https://example.com")
        let shortcut = AgentResponse(transcript: "运行早安", action: .runShortcut, shortcutName: "早安")
        let search = AgentResponse(transcript: "搜一下", action: .webSearch, query: "SayKuku")
        let app = ContextItem(kind: .app, symbol: "app", title: "Notes", value: "com.apple.Notes")
        let domain = ContextItem(kind: .domain, symbol: "text.bubble", title: "Domains", value: "Swift")
        #expect(!AgentActionExecutor.needsConfirmation(open, context: [app, domain]))
        #expect(AgentActionExecutor.needsConfirmation(shortcut, context: [app, domain]))
        #expect(AgentActionExecutor.needsConfirmation(shortcut, context: []))
        #expect(!AgentActionExecutor.needsConfirmation(search, context: [app, domain]))
        #expect(!AgentActionExecutor.needsConfirmation(search, context: []))
        for kind: ContextItem.Kind in [.selectedText, .previousOutput, .window, .clipboard, .browser, .screen, .session] {
            let untrusted = ContextItem(kind: kind, symbol: "", title: "", value: "text")
            #expect(AgentActionExecutor.needsConfirmation(open, context: [app, untrusted]))
            #expect(AgentActionExecutor.needsConfirmation(shortcut, context: [app, untrusted]))
            #expect(AgentActionExecutor.needsConfirmation(search, context: [untrusted]))
        }
    }

    @Test("a failed workspace open reports an action failure")
    @MainActor
    func failedWorkspaceOpen() async throws {
        let link = AgentResponse(transcript: "打开", action: .openURL, url: "https://example.com")
        await #expect(throws: AgentActionError.self) {
            try await AgentActionExecutor.execute(link, engine: .google, openURL: { _ in false })
        }
    }

    @Test("actions without a usable payload are rejected before they are offered or run")
    func actionValidation() throws {
        func link(_ url: String) -> AgentResponse { AgentResponse(transcript: "打开", action: .openURL, url: url) }
        #expect(try AgentActionExecutor.validate(link("https://example.com"), engine: .google)?.host == "example.com")
        for url in ["file:///etc/passwd", "https://google.com@evil.example/", "https://user:pass@example.com/"] {
            #expect(throws: QwenError.invalidResponse) { try AgentActionExecutor.validate(link(url), engine: .google) }
        }
        let search = AgentResponse(transcript: "搜一下", action: .webSearch, query: "SayKuku")
        #expect(try AgentActionExecutor.validate(search, engine: .bing)?.host == "www.bing.com")
        #expect(try AgentActionExecutor.validate(search, engine: .duckduckgo)?.host == "duckduckgo.com")
        let emptySearch = AgentResponse(transcript: "搜一下", action: .webSearch, query: "")
        #expect(throws: QwenError.invalidResponse) { try AgentActionExecutor.validate(emptySearch, engine: .bing) }
        let shortcut = AgentResponse(transcript: "运行早安", action: .runShortcut, shortcutName: "早安")
        #expect(try AgentActionExecutor.validate(shortcut, engine: .bing) == nil)
        let unnamed = AgentResponse(transcript: "运行", action: .runShortcut, shortcutName: "")
        #expect(throws: QwenError.invalidResponse) { try AgentActionExecutor.validate(unnamed, engine: .bing) }
    }

    @Test("rewriting clipped text is not written back")
    func clippedWriteBack() {
        let clipped = ContextItem(kind: .selectedText, symbol: "", title: "", value: "…", isClipped: true)
        let whole = ContextItem(kind: .previousOutput, symbol: "", title: "", value: "done")
        let rewrite = AgentResponse(transcript: "翻译", action: .writeText, target: .current, output: "x")
        let revision = AgentResponse(transcript: "再短一点", action: .writeText, target: .previous, output: "x")
        let deletion = AgentResponse(transcript: "删掉刚才那段", action: .writeText, target: .previous, output: "")
        let clippedPrevious = ContextItem(kind: .previousOutput, symbol: "", title: "", value: "…", isClipped: true)
        #expect(AgentActionExecutor.replacesClippedText(rewrite, context: [clipped, whole]))
        #expect(!AgentActionExecutor.replacesClippedText(revision, context: [clipped, whole]))
        #expect(!AgentActionExecutor.replacesClippedText(rewrite, context: [whole]))
        #expect(AgentActionExecutor.replacesClippedText(revision, context: [clippedPrevious]))
        // Deleting drops the whole output, so seeing only its start is enough.
        #expect(!AgentActionExecutor.replacesClippedText(deletion, context: [clippedPrevious]))
    }

    @Test("the previous output is titled with its first words")
    func previousOutputItem() {
        let long = ContextCollector.previousOutputItem("周四下午三点开会，\n把方案带上，记得提前十分钟到。")
        #expect(long.kind == .previousOutput)
        #expect(long.title == localized("Just wrote: \("周四下午三点开会， 把方案带上，记得提前…")"))
        #expect(long.value == "周四下午三点开会，\n把方案带上，记得提前十分钟到。")
        #expect(!long.isClipped)

        let short = ContextCollector.previousOutputItem("好的")
        #expect(short.title == localized("Just wrote: \("好的")"))
    }

    @Test("long context is clipped and labeled")
    func clippedContextItem() {
        let long = ContextCollector.textItem(
            kind: .selectedText, symbol: "text.quote", title: "Selected text", value: String(repeating: "字", count: 12),
            limit: 10
        )
        #expect(long.isClipped)
        #expect(long.title == "Selected text · " + localized("first \(10) characters"))
        #expect(long.value == String(repeating: "字", count: 10) + "…")

        let short = ContextCollector.textItem(
            kind: .clipboard, symbol: "clipboard", title: "Clipboard", value: "a", limit: 10
        )
        #expect(!short.isClipped)
        #expect(short.title == "Clipboard · " + localized("\(1) characters"))
        #expect(short.value == "a")
    }

    @Test("browser context keeps only the page address")
    func browserPageAddress() {
        #expect(ContextCollector.pageAddress("https://user:secret@example.com:8443/reset/a%20b?token=abc#code=1")
            == "https://example.com:8443/reset/a%20b")
        #expect(ContextCollector.pageAddress("https://example.com") == "https://example.com")
    }

    @Test("memory context previews the exact saved entries sent to the Agent")
    @MainActor
    func memoryContextItem() {
        let items = ContextCollector.collect(
            snapshot: target(value: nil, range: nil),
            selectedTextAllowed: false,
            currentAppAllowed: false,
            windowTitleAllowed: false,
            clipboardAllowed: false,
            browserPage: nil,
            screenText: "",
            sessions: [],
            domains: [],
            memory: [
                MemoryEntity(name: "WorkBuddy", type: .project),
                MemoryEntity(name: "SayKuku", type: .project)
            ]
        )
        #expect(items.count == 1)
        #expect(items.first?.kind == .memory)
        #expect(items.first?.value.contains("WorkBuddy") == true)
        #expect(items.first?.value.contains("SayKuku") == true)
    }

    private func target(
        value: String?, range: CFRange?, window: AXUIElement? = nil, text: AXUIElement? = nil
    ) -> TextTargetSnapshot {
        TextTargetSnapshot(
            appPID: 0,
            bundleID: "tests",
            appName: "Tests",
            windowTitle: "",
            hasDictationTarget: window != nil || text != nil,
            windowElement: window,
            textElement: text,
            selectionElement: nil,
            selectedRange: range,
            selectedText: "",
            valueBefore: value,
            isSensitive: false,
            caretFrame: nil
        )
    }
}

@Suite("Paste key lookup")
@MainActor
struct PasteKeyTests {
    @Test("⌘V uses the key that types v in the layout")
    func pasteKeyCode() throws {
        #expect(try pasteKeyCode(layout: "com.apple.keylayout.US") == CGKeyCode(kVK_ANSI_V))
        #expect(try pasteKeyCode(layout: "com.apple.keylayout.Dvorak") == CGKeyCode(kVK_ANSI_Period))
        // This layout switches to QWERTY while ⌘ is held.
        #expect(try pasteKeyCode(layout: "com.apple.keylayout.DVORAK-QWERTYCMD") == CGKeyCode(kVK_ANSI_V))
    }

    private func pasteKeyCode(layout id: String) throws -> CGKeyCode? {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        let sources = try #require(TISCreateInputSourceList(filter, true)).takeRetainedValue() as NSArray
        let source = try #require(sources.firstObject) as! TISInputSource
        let layoutData = try #require(KeyboardLayout.layoutData(of: source))
        return KeyboardLayout.pasteKeyCode(in: layoutData)
    }
}

@Suite("Screen text")
struct ScreenTextTests {
    private let later = ContinuousClock.now + .seconds(60)

    private func node(_ path: [Int], _ role: String, _ text: String?) -> ScreenText.Node {
        ScreenText.Node(path: path, role: role, text: text)
    }

    @Test("text roles are joined in reading order, one trimmed line each")
    func readingOrder() {
        // Breadth-first: the heading sits above the list whose rows are visited later.
        let nodes = [
            node([0], "AXHeading", " 周报 "),
            node([1], "AXGroup", nil),
            node([2], "AXButton", "发送"),
            node([1, 0], "AXStaticText", "周四方便吗"),
            node([1, 1], "AXSecureTextField", "hunter2"),
            node([1, 2], "AXLink", "\n"),
            node([1, 3], "AXCell", "下周一")
        ]
        #expect(ScreenText.collect(nodes, deadline: later) == "周报\n周四方便吗\n下周一")
    }

    @Test("only a line repeating the one before it is dropped")
    func adjacentRepeats() {
        let nodes = [
            node([0], "AXStaticText", "完成"),
            node([1], "AXStaticText", "完成"),
            node([2], "AXStaticText", "进行中"),
            node([3], "AXStaticText", "完成")
        ]
        #expect(ScreenText.collect(nodes, deadline: later) == "完成\n进行中\n完成")
    }

    @Test("collecting stops at the node limit without reading further nodes")
    func nodeLimit() {
        var pulled = 0
        let nodes = AnyIterator<ScreenText.Node> {
            pulled += 1
            return ScreenText.Node(path: [pulled], role: "AXStaticText", text: "\(pulled)")
        }
        let text = ScreenText.collect(IteratorSequence(nodes), deadline: later)
        #expect(pulled == ScreenText.nodeLimit)
        #expect(text.split(separator: "\n").count == ScreenText.nodeLimit)
    }

    @Test("text stops at the character limit, line breaks included")
    func characterLimit() {
        let paragraph = String(repeating: "字", count: 500)
        let nodes = (0..<10).map { node([$0], "AXStaticText", paragraph + "\($0)") }
        let text = ScreenText.collect(nodes, deadline: later)
        #expect(text.count == ScreenText.characterLimit)
        #expect(text.hasPrefix(paragraph + "0\n" + paragraph + "1"))
    }

    @Test("nothing is read once the time budget has run out")
    func timeBudget() {
        var pulled = 0
        let nodes = AnyIterator<ScreenText.Node> {
            pulled += 1
            return ScreenText.Node(path: [pulled], role: "AXStaticText", text: "x")
        }
        #expect(ScreenText.collect(IteratorSequence(nodes), deadline: ContinuousClock.now - .seconds(1)).isEmpty)
        #expect(pulled == 0)
    }
}
