import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import SayKuku

private func makeTestKeychain() -> KeychainStore {
    KeychainStore(service: "com.saykuku.tests.\(UUID().uuidString)")
}

private func cleanTestKeychain(_ keychain: KeychainStore) {
    try? keychain.remove("qwen.apiKey")
    try? keychain.remove("history-encryption-key")
}

@Suite("Knowledge pipeline")
struct KnowledgePipelineTests {
    @Test("normalization removes separators and case")
    func normalization() {
        #expect(KnowledgeNormalizer.key(" Bifro-MQ ") == "bifromq")
        #expect(KnowledgeNormalizer.key("Ani Kuku") == "anikuku")
    }

    @Test("PII is redacted before model extraction")
    func redaction() {
        let result = KnowledgePipeline.redactingPII(in: "王涛 18600000000 wang@example.com\n地址：北京市朝阳区测试路 1 号")
        #expect(!result.text.contains("18600000000"))
        #expect(!result.text.contains("wang@example.com"))
        #expect(result.ignored.count == 3)
        #expect(result.ignored.allSatisfy { $0.status == .ignored })
    }

    @Test("exact aliases merge while similar names require confirmation")
    func deduplication() {
        let existing = [KnowledgeEntity(name: "WorkBuddy", type: .product, aliases: ["work body"])]
        let proposals = [
            ProposedEntity(name: "work body", type: .product, detail: "", aliases: [], evidence: "work body"),
            ProposedEntity(name: "WorkBudy", type: .product, detail: "", aliases: [], evidence: "WorkBudy"),
            ProposedEntity(name: "AniKuku", type: .project, detail: "", aliases: [], evidence: "AniKuku")
        ]
        let result = KnowledgePipeline.analyze(proposals: proposals, relationships: [], existing: existing, ignored: [])
        let statuses = Dictionary(uniqueKeysWithValues: result.candidates.map { ($0.entity.name, $0.status) })
        #expect(statuses["work body"] == .merge)
        #expect(statuses["WorkBudy"] == .conflict)
        #expect(statuses["AniKuku"] == .new)
    }

    @Test("only selected candidates and evidenced relationships are committed")
    func commit() {
        let proposals = [
            ProposedEntity(name: "张越", type: .person, detail: "Founder", aliases: ["Visoar"], evidence: "负责人张越"),
            ProposedEntity(name: "AniKuku", type: .project, detail: "Project", aliases: [], evidence: "项目 AniKuku")
        ]
        let relationships = [ProposedRelationship(from: "张越", type: .owns, to: "AniKuku", evidence: "负责人张越")]
        let analysis = KnowledgePipeline.analyze(proposals: proposals, relationships: relationships, existing: [], ignored: [])
        let result = KnowledgePipeline.commit(
            analysis: analysis,
            selectedIDs: Set(analysis.candidates.map(\.id) + analysis.relationships.map(\.id)),
            existing: []
        )
        #expect(result.entities.count == 2)
        #expect(result.relationships.count == 1)
    }

    @Test("long imports are split without losing text")
    func chunking() {
        let source = String(repeating: "abcdef", count: 100)
        let chunks = KnowledgePipeline.chunks(source, limit: 64)
        #expect(chunks.allSatisfy { $0.count <= 64 })
        #expect(chunks.joined() == source)
    }

    @Test("knowledge edits preserve identity and normalize aliases")
    @MainActor
    func knowledgeEditing() {
        let suite = "SayKukuTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let keychain = makeTestKeychain()
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
            cleanTestKeychain(keychain)
        }
        let originalDate = Date(timeIntervalSince1970: 1_700_000_000)
        let original = KnowledgeEntity(
            name: "AniKuku",
            detail: "Project",
            type: .project,
            aliases: ["Ani Kuku"],
            source: .importText,
            createdAt: originalDate
        )
        let state = AppState(
            defaults: defaults,
            store: LocalStore(root: root, keychain: keychain),
            keychain: keychain
        )
        state.knowledgeEntities = [original, KnowledgeEntity(name: "WorkBuddy", type: .product)]

        #expect(state.updateKnowledge(
            id: original.id,
            name: " AniKuku Pro ",
            type: .product,
            detail: " Updated project ",
            aliases: ["Ani Kuku", " ani kuku ", "AniKuku Pro", ""]
        ))
        let edited = state.knowledgeEntities[0]
        #expect(edited.id == original.id)
        #expect(edited.name == "AniKuku Pro")
        #expect(edited.detail == "Updated project")
        #expect(edited.aliases == ["Ani Kuku"])
        #expect(edited.source == .importText)
        #expect(edited.createdAt == originalDate)
        #expect(!state.updateKnowledge(
            id: original.id,
            name: "WorkBuddy",
            type: .product,
            detail: "",
            aliases: []
        ))
    }

    @Test("main navigation titles follow the selected language")
    @MainActor
    func navigationLocalization() {
        let suite = "SayKukuTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let keychain = makeTestKeychain()
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
            cleanTestKeychain(keychain)
        }
        let state = AppState(
            defaults: defaults,
            store: LocalStore(root: root, keychain: keychain),
            keychain: keychain
        )
        state.appLanguage = .chinese
        #expect(AppState.Destination.knowledge.title(state) == "知识")
        #expect(state.voiceInputTitle == "语音输入")
        #expect(state.voiceAgentTitle == "语音 Agent")
        state.appLanguage = .english
        #expect(AppState.Destination.knowledge.title(state) == "Knowledge")
        #expect(state.voiceInputTitle == "Voice Input")
        #expect(state.voiceAgentTitle == "Voice Agent")
    }
}

@Suite("Configuration and persistence")
struct PersistenceTests {
    @Test("regional endpoint uses legacy or workspace host")
    func endpoints() {
        var config = QwenConfiguration(region: .beijing, workspaceID: "", realtimeModel: "r", reasoningModel: "m")
        #expect(config.realtimeURL?.host == "dashscope.aliyuncs.com")
        config.workspaceID = "ws123"
        #expect(config.chatCompletionsURL?.host == "ws123.cn-beijing.maas.aliyuncs.com")
    }

    @Test("dictation preferences persist across app state reloads")
    @MainActor
    func dictationPreferencePersistence() {
        let suite = "SayKukuTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let keychain = makeTestKeychain()
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
            cleanTestKeychain(keychain)
        }

        let state = AppState(
            defaults: defaults,
            store: LocalStore(root: root, keychain: keychain),
            keychain: keychain
        )
        #expect(state.automaticAgentWriteBack)
        state.recognitionLanguage = .english
        state.dictationNumberFormat = .spoken
        state.selectedDomains = [.aiVibeCoding, .softwareDevelopment]
        state.customDomainTerms = ["SayKuku", "Vibe Coding"]
        state.didCompleteOnboarding = true
        state.automaticAgentWriteBack = false

        let reloaded = AppState(
            defaults: defaults,
            store: LocalStore(root: root, keychain: keychain),
            keychain: keychain
        )
        #expect(reloaded.recognitionLanguage == .english)
        #expect(reloaded.dictationNumberFormat == .spoken)
        #expect(reloaded.selectedDomains == [.aiVibeCoding, .softwareDevelopment])
        #expect(reloaded.customDomainTerms == ["SayKuku", "Vibe Coding"])
        #expect(reloaded.didCompleteOnboarding)
        #expect(!reloaded.automaticAgentWriteBack)
    }

    @Test("menu bar-only close preference persists and keeps a recovery entry")
    @MainActor
    func menuBarOnlyClosePreference() {
        let suite = "SayKukuTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let keychain = makeTestKeychain()
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
            cleanTestKeychain(keychain)
        }

        let state = AppState(
            defaults: defaults,
            store: LocalStore(root: root, keychain: keychain),
            keychain: keychain
        )
        #expect(!state.hideDockIconAfterMainWindowCloses)
        state.setShowInMenuBar(false)
        #expect(!state.showInMenuBar)

        state.hideDockIconAfterMainWindowCloses = true
        #expect(state.showInMenuBar)
        state.setShowInMenuBar(false)
        #expect(state.showInMenuBar)

        let reloaded = AppState(
            defaults: defaults,
            store: LocalStore(root: root, keychain: keychain),
            keychain: keychain
        )
        #expect(reloaded.hideDockIconAfterMainWindowCloses)
        #expect(reloaded.showInMenuBar)

        reloaded.hideDockIconAfterMainWindowCloses = false
        reloaded.setShowInMenuBar(false)
        #expect(!reloaded.showInMenuBar)
    }

    @Test("snapshot persists and reloads")
    func persistence() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let keychain = makeTestKeychain()
        defer {
            try? FileManager.default.removeItem(at: root)
            cleanTestKeychain(keychain)
        }
        let store = LocalStore(root: root, keychain: keychain)
        let entry = HistoryEntry(
            mode: .dictation, app: "Tests", createdAt: Date(timeIntervalSince1970: 1_700_000_000.123),
            durationSeconds: 1, input: "hello", output: "",
            status: .failed, errorMessage: "timeout"
        )
        try await store.replace(.init(history: [entry]))
        let reloaded = LocalStore(root: root, keychain: keychain)
        let snapshot = await reloaded.load()
        #expect(snapshot.history == [entry])
        let storedBytes = try Data(contentsOf: root.appendingPathComponent("store.data"))
        #expect(!String(decoding: storedBytes, as: UTF8.self).contains("hello"))
    }

    @Test("legacy history without a status remains readable")
    func legacyHistoryStatus() throws {
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "mode": "dictation",
          "app": "Tests",
          "createdAt": 1700000000123,
          "durationSeconds": 1.25,
          "input": "hello",
          "output": "hello",
          "isStarred": false
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let entry = try decoder.decode(HistoryEntry.self, from: Data(json.utf8))

        #expect(entry.id == id)
        #expect(entry.status == .completed)
        #expect(entry.errorMessage == nil)
    }

    @Test("audio is encrypted and decrypts for playback")
    func audioEncryption() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let keychain = makeTestKeychain()
        defer {
            try? FileManager.default.removeItem(at: root)
            cleanTestKeychain(keychain)
        }
        let store = LocalStore(root: root, keychain: keychain)
        let audio = Data("RIFF-private-audio-payload".utf8)
        let filename = try await store.saveAudio(audio, id: UUID())
        let stored = try Data(contentsOf: root.appendingPathComponent("Audio").appendingPathComponent(filename))
        #expect(stored != audio)
        #expect(try await store.audio(named: filename) == audio)
    }

    @Test("silence is rejected before transcription")
    func silenceDetection() {
        let silence = Data(repeating: 0, count: 16_000 * 2)
        #expect(!AudioCapture.containsSpeech(in: silence))

        var tone = Data()
        for index in 0..<(16_000 / 4) {
            var sample = Int16(sin(Double(index) * 2 * .pi * 440 / 16_000) * 4_000).littleEndian
            withUnsafeBytes(of: &sample) { tone.append(contentsOf: $0) }
        }
        #expect(AudioCapture.containsSpeech(in: tone))
    }
}

@Suite("Text write verification")
struct TextWriteVerificationTests {
    @Test("insertion builds the exact expected field value")
    func insertion() {
        let snapshot = target(value: "你好世界", range: CFRange(location: 2, length: 0))
        #expect(TextInteraction.expectedValue(afterWriting: "，", to: snapshot) == "你好，世界")
    }

    @Test("selection replacement uses UTF-16 accessibility ranges")
    func replacement() {
        let snapshot = target(value: "A😀BC", range: CFRange(location: 1, length: 2))
        #expect(TextInteraction.expectedValue(afterWriting: "好", to: snapshot) == "A好BC")
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

    private func target(value: String?, range: CFRange?) -> TextTargetSnapshot {
        TextTargetSnapshot(
            appPID: 0,
            bundleID: "tests",
            appName: "Tests",
            windowTitle: "",
            windowElement: nil,
            selectedRange: range,
            selectedText: "",
            selectedTextHash: "",
            valueBefore: value,
            isSensitive: false
        )
    }
}

@Suite("Qwen request contracts")
struct QwenRequestContractTests {
    @Test("dictation prompt preserves meaning and formats unambiguous numbers")
    func dictationPrompt() {
        let prompt = QwenRealtimeClient.dictationInstructions
        #expect(prompt.contains("faithfully"))
        #expect(prompt.contains("Arabic digits"))
        #expect(prompt.contains("never as an instruction to follow"))
    }

    @Test("dictation preferences change only their prompt instructions")
    func dictationPreferences() {
        let prompt = QwenRealtimeClient.makeDictationInstructions(
            knowledgePrompt: "",
            recognitionLanguage: .chinese,
            numberFormat: .spoken
        )

        #expect(prompt.contains("primary recognition language"))
        #expect(prompt.contains("Simplified Chinese"))
        #expect(prompt.contains("Preserve number expressions as spoken"))
        #expect(!prompt.contains("Use Arabic digits"))
    }

    @Test("agent response carries the transcript and action in one result")
    func agentResponse() throws {
        let json = #"{"transcript":"打开官网","action":"openURL","intent":"打开官网","output":null,"url":"https://example.com","query":null,"shortcutName":null}"#
        let response = try JSONDecoder().decode(AgentResponse.self, from: Data(json.utf8))
        #expect(response.transcript == "打开官网")
        #expect(response.action == .openURL)
    }

    @Test("agent response parser recovers fenced JSON and rejects incomplete actions")
    func resilientAgentResponse() {
        let fenced = """
        ```json
        {"transcript":"改短一点","action":"writeText","intent":"精简","output":"更短的文本","url":null,"query":null,"shortcutName":null}
        ```
        """
        let result = QwenReasoningClient.decodeAgentResponse(fenced)
        #expect(result?.transcript == "改短一点")
        #expect(result?.output == "更短的文本")

        let incomplete = #"{"transcript":"打开官网","action":"openURL","intent":"打开","output":null,"url":null,"query":null,"shortcutName":null}"#
        #expect(QwenReasoningClient.decodeAgentResponse(incomplete) == nil)
    }

    @Test("only short-lived network failures are retried")
    func retryPolicy() {
        #expect(QwenReasoningClient.isRetryableNetworkError(URLError(.networkConnectionLost)))
        #expect(QwenReasoningClient.isRetryableNetworkError(URLError(.cannotConnectToHost)))
        #expect(!QwenReasoningClient.isRetryableNetworkError(URLError(.timedOut)))
        #expect(!QwenReasoningClient.isRetryableNetworkError(URLError(.notConnectedToInternet)))
    }

    @Test("selected text is sent as the primary agent input")
    func selectedTextInput() {
        let input = QwenReasoningClient.agentInput(
            context: [
                ContextItem(kind: .app, symbol: "app", title: "Notes", value: "com.apple.Notes"),
                ContextItem(kind: .selectedText, symbol: "text.quote", title: "Selected text", value: "明天下午见")
            ],
            session: nil
        )
        #expect(QwenReasoningClient.agentInstructions.contains("primary object"))
        #expect(QwenReasoningClient.agentInstructions.contains("Transform the selected text, not the spoken command"))
        #expect(input.contains("<selected_text>\n明天下午见\n</selected_text>"))
        #expect(input.contains("Notes:\ncom.apple.Notes"))
    }

    @Test("recent agent session is included in the next agent prompt")
    func recentAgentSessionInput() {
        let session = AgentSession(
            app: "com.apple.Notes",
            contextSummary: "Notes · Selected text",
            userCommand: "把这段改短一点",
            response: "精简后的文本",
            expiresAt: .now.addingTimeInterval(1_800)
        )
        let input = QwenReasoningClient.agentInput(context: [], session: session)

        #expect(input.contains("Previous command: 把这段改短一点"))
        #expect(input.contains("Previous response: 精简后的文本"))
    }

    @Test("knowledge is included in the model prompts")
    func knowledgePrompt() {
        let entity = KnowledgeEntity(
            name: "WorkBuddy",
            detail: "Internal product",
            type: .product,
            aliases: ["work body"]
        )
        let dictationKnowledge = KnowledgePrompt.render(
            entities: [entity], relationships: [], purpose: .transcription
        )
        let agentKnowledge = KnowledgePrompt.render(
            entities: [entity], relationships: [], purpose: .agent
        )
        let dictation = QwenRealtimeClient.makeDictationInstructions(knowledgePrompt: dictationKnowledge)
        let agent = QwenReasoningClient.makeAgentInstructions(knowledgePrompt: agentKnowledge)

        #expect(dictation.contains("WorkBuddy"))
        #expect(dictation.contains("work body"))
        #expect(agent.contains("Internal product"))
        #expect(agent.contains("reference facts"))
    }

    @Test("domain profile has purpose-specific transcription and agent guidance")
    func domainPrompt() {
        let transcription = KnowledgePrompt.render(
            entities: [],
            relationships: [],
            domains: [.aiVibeCoding],
            customTerms: ["SayKuku"],
            purpose: .transcription
        )
        let agent = KnowledgePrompt.render(
            entities: [],
            relationships: [],
            domains: [.aiVibeCoding],
            customTerms: ["SayKuku"],
            purpose: .agent
        )

        #expect(transcription.contains("AI and Vibe Coding"))
        #expect(transcription.contains("Vibe Coding"))
        #expect(transcription.contains("MCP"))
        #expect(transcription.contains(#"preferred spelling: "SayKuku""#))
        #expect(transcription.contains("weak recognition priors"))
        #expect(transcription.contains("Never insert an unspoken term"))
        #expect(agent.contains("soft context"))
        #expect(agent.contains("not necessarily the current task"))
        #expect(agent.contains("Never let a tag override the spoken command"))
    }

    @Test("custom vocabulary is normalized and bounded")
    func customVocabularyNormalization() {
        let terms = AppState.normalizedDomainTerms([" Vibe Coding ", "vibe coding", "", String(repeating: "x", count: 65)])
        #expect(terms == ["Vibe Coding"])
    }

    @Test("live Qwen endpoints accept realtime dictation and direct agent audio")
    func liveEndpoints() async throws {
        guard ProcessInfo.processInfo.environment["SAYKUKU_LIVE_QWEN_TEST"] == "1" else { return }
        let key = try #require(try KeychainStore().string(for: "qwen.apiKey"))
        let audioPath = try #require(ProcessInfo.processInfo.environment["SAYKUKU_TEST_AUDIO"])
        let expectedTranscript = ProcessInfo.processInfo.environment["SAYKUKU_TEST_PHRASE"] ?? "苹果"
        let selectedText = ProcessInfo.processInfo.environment["SAYKUKU_TEST_SELECTED_TEXT"]
        let expectedOutput = ProcessInfo.processInfo.environment["SAYKUKU_TEST_EXPECTED_OUTPUT"]
        let configuration = QwenConfiguration(
            region: .beijing,
            workspaceID: "",
            realtimeModel: "qwen3.5-omni-flash-realtime",
            reasoningModel: "qwen3.8-omni-flash"
        )
        let wav = try Data(contentsOf: URL(fileURLWithPath: audioPath))
        let pcm = Data(wav.dropFirst(44))

        let realtime = QwenRealtimeClient()
        try await realtime.connect(
            apiKey: key,
            configuration: configuration,
            autoStop: false,
            onSpeechStopped: {},
            onDelta: { _ in }
        )
        for start in stride(from: 0, to: pcm.count, by: 3_200) {
            let end = min(start + 3_200, pcm.count)
            try await realtime.append(Data(pcm[start..<end]))
        }
        let dictation = try await realtime.commit()
        await realtime.cancel()
        #expect(dictation.contains(expectedTranscript))

        try await realtime.connect(
            apiKey: key,
            configuration: configuration,
            autoStop: true,
            onSpeechStopped: {},
            onDelta: { _ in }
        )
        await realtime.cancel()

        let response = try await QwenReasoningClient().respondToAudio(
            apiKey: key,
            configuration: configuration,
            wav: wav,
            context: selectedText.map {
                [ContextItem(kind: .selectedText, symbol: "text.quote", title: "Selected text", value: $0)]
            } ?? [],
            session: nil
        )
        #expect(response.transcript?.contains(expectedTranscript) == true)
        if let expectedOutput {
            #expect(response.action == .writeText)
            #expect(response.output?.localizedCaseInsensitiveContains(expectedOutput) == true)
        }
    }
}

@Suite("Fn gesture routing")
struct FnGestureRoutingTests {
    @Test("single Fn release stops an active agent before starting dictation")
    func agentStopHasPriority() {
        #expect(ShortcutController.releaseAction(
            wasChorded: false,
            agentIsListening: true,
            dictationIsListening: false
        ) == .finishAgent)
        #expect(!ShortcutController.shouldArmHold(inputMode: .hold, agentIsListening: true))
        #expect(!ShortcutController.shouldArmHold(inputMode: .tap, agentIsListening: true))
    }

    @Test("dictation and unused taps keep their existing routing")
    func existingRoutesRemainStable() {
        #expect(ShortcutController.releaseAction(
            wasChorded: false,
            agentIsListening: false,
            dictationIsListening: true
        ) == .finishDictation)
        #expect(ShortcutController.releaseAction(
            wasChorded: false,
            agentIsListening: false,
            dictationIsListening: false
        ) == .registerQuickTap)
        #expect(ShortcutController.releaseAction(
            wasChorded: true,
            agentIsListening: true,
            dictationIsListening: false
        ) == .ignore)
        #expect(ShortcutController.shouldArmHold(inputMode: .hold, agentIsListening: false))
    }

    @Test("escape cancels only while a voice workflow is active")
    func escapeRouting() {
        #expect(ShortcutController.shouldCancelForEscape(
            keyCode: UInt16(kVK_Escape),
            dictationIsActive: true,
            agentIsActive: false
        ))
        #expect(ShortcutController.shouldCancelForEscape(
            keyCode: UInt16(kVK_Escape),
            dictationIsActive: false,
            agentIsActive: true
        ))
        #expect(!ShortcutController.shouldCancelForEscape(
            keyCode: UInt16(kVK_Escape),
            dictationIsActive: false,
            agentIsActive: false
        ))
        #expect(!ShortcutController.shouldCancelForEscape(
            keyCode: UInt16(kVK_Return),
            dictationIsActive: true,
            agentIsActive: false
        ))
    }
}
