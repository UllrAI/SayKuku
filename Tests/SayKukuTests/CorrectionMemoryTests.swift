import Foundation
import Testing
@testable import SayKuku

/// Simulates SayKuku writing `written` between `prefix` and `suffix`, after which the user edits the field to `edited`.
private func correction(
    prefix: String = "",
    written: String,
    suffix: String = "",
    edited: String
) -> CorrectionCandidate? {
    let start = prefix.utf16.count
    return CorrectionExtractor.extract(
        expected: prefix + written + suffix,
        actual: edited,
        writtenRange: start..<(start + written.utf16.count)
    )
}

@Suite("Correction extraction")
struct CorrectionExtractorTests {
    @Test("Chinese names are captured whole")
    func chineseName() {
        #expect(correction(written: "王小明", edited: "王晓明") == CorrectionCandidate(before: "王小明", after: "王晓明"))
        #expect(correction(written: "王小明，明天开会。", edited: "王晓明，明天开会。")
            == CorrectionCandidate(before: "王小明", after: "王晓明"))
    }

    @Test("adding or dropping Chinese characters is rewording")
    func chineseInsertionOrDeletion() {
        #expect(correction(written: "明天开会", edited: "明天下午开会") == nil)
        #expect(correction(written: "我那个觉得可以", edited: "我觉得可以") == nil)
    }

    @Test("long Chinese clauses narrow to the words around the edit")
    func longChineseClause() throws {
        let clause = "明天下午三点和王小明一起讨论项目进度"
        let edited = clause.replacingOccurrences(of: "小", with: "晓")
        let result = try #require(correction(written: clause, edited: edited))
        #expect(result.before.contains("小"))
        #expect(result.after.count >= 2)
        #expect(result.after.count < edited.count)
        #expect(result.before.replacingOccurrences(of: "小", with: "晓") == result.after)
    }

    @Test("English words are captured whole")
    func englishWord() {
        #expect(correction(written: "Deploy it on Kubernetis today.", edited: "Deploy it on Kubernetes today.")
            == CorrectionCandidate(before: "Kubernetis", after: "Kubernetes"))
        #expect(correction(written: "我们用Kubernetis部署", edited: "我们用Kubernetes部署")
            == CorrectionCandidate(before: "Kubernetis", after: "Kubernetes"))
        #expect(correction(written: "Kubernetess", edited: "Kubernetes")
            == CorrectionCandidate(before: "Kubernetess", after: "Kubernetes"))
    }

    @Test("several edits inside one word stay one pair")
    func editsWithinWord() {
        #expect(correction(written: "Kubrnetis", edited: "Kubernetes") == CorrectionCandidate(before: "Kubrnetis", after: "Kubernetes"))
    }

    @Test("edits spanning separate phrases are skipped")
    func editsAcrossPhrases() {
        #expect(correction(written: "王小明，李四", edited: "王晓明，李斯") == nil)
        #expect(correction(
            written: "王小明明天来。我们讨论Kubernetis部署。",
            edited: "王晓明明天来。我们讨论Kubernetes部署。"
        ) == nil)
    }

    @Test("punctuation, whitespace, case, and number edits are skipped")
    func nonSpellingEdits() {
        #expect(correction(written: "你好。", edited: "你好，") == nil)
        #expect(correction(written: "Hello, world", edited: "Hello world") == nil)
        #expect(correction(written: "Hello world", edited: "Hello  world") == nil)
        #expect(correction(written: "iphone", edited: "iPhone") == nil)
        #expect(correction(written: "Meet at 3 pm", edited: "Meet at 4 pm") == nil)
        #expect(correction(written: "好的👍", edited: "好的👌") == nil)
        #expect(correction(written: "王小明", edited: "王小明") == nil)
    }

    @Test("typing after the output is not a correction")
    func continuation() {
        #expect(correction(written: "你好。", edited: "你好，继续") == nil)
        #expect(correction(written: "你好。", edited: "你好呀，继续") == nil)
        #expect(correction(written: "Hello", edited: "Hello world") == nil)
        #expect(correction(written: "Hello", edited: "Helloworld") == nil)
    }

    @Test("edits outside the written text are ignored and expansion stays inside it")
    func writtenRangeLimits() {
        #expect(correction(prefix: "王小明说：", written: "你好", edited: "王晓明说：你好") == nil)
        #expect(correction(written: "你好", suffix: "，王小明", edited: "你好，王晓明") == nil)
        #expect(correction(prefix: "Kuber", written: "netis", edited: "Kubernetes")
            == CorrectionCandidate(before: "netis", after: "netes"))
    }

    @Test("surrogate pairs and emoji are never split")
    func graphemes() {
        #expect(correction(written: "𠮷野家", edited: "吉野家") == CorrectionCandidate(before: "𠮷野家", after: "吉野家"))
        #expect(correction(written: "Hi 👋 Bob", edited: "Hi 👋 Rob") == CorrectionCandidate(before: "Bob", after: "Rob"))
        #expect(correction(prefix: "👨‍👩‍👧 ", written: "王小明", edited: "👨‍👩‍👧 王晓明")
            == CorrectionCandidate(before: "王小明", after: "王晓明"))
    }

    @Test("overly long replacements are skipped")
    func lengthLimit() {
        let word = String(repeating: "a", count: CorrectionExtractor.maxLength) + "b"
        #expect(correction(written: word, edited: word.replacingOccurrences(of: "b", with: "c")) == nil)
    }
}

@Suite("Correction memory")
@MainActor
struct CorrectionMemoryTests {
    private func withState(_ body: (AppState) -> Void) {
        let environment = AppStateTestEnvironment()
        defer { environment.clean() }
        body(environment.makeState())
    }

    @Test("memory added without detail keeps it empty")
    func manualMemoryDetail() {
        withState { state in
            #expect(state.data.addMemory(name: "AniKuku", type: .project, detail: "  ") == nil)
            #expect(state.data.memoryEntities.first?.detail == "")
            #expect(state.data.addMemory(name: "WorkBuddy", type: .project) == nil)
            #expect(state.data.memoryEntities.first?.detail == "")
            #expect(state.data.addMemory(name: " ani kuku ", type: .term) == .duplicate(existingName: "AniKuku"))
            #expect(state.data.addMemory(name: "  ", type: .term) == .emptyName)
            #expect(state.data.memoryEntities.count == 2)
        }
    }

    @Test("accepted corrections take where they were made as the clue")
    func acceptedCorrection() {
        withState { state in
            let record = CorrectionRecord(raw: "王小明", corrected: "王晓明", lastApp: "TextEdit")
            state.data.corrections = [record]
            state.data.acceptCorrection(record.id)
            let entity = state.data.memoryEntities.first { $0.name == "王晓明" }
            #expect(entity?.detail == "TextEdit")
            #expect(entity?.aliases == ["王小明"])
            #expect(entity?.source == .correction)
            #expect(state.data.corrections.first?.status == .accepted)
        }
    }

    @Test("only pending corrections count as suggestions")
    func pendingSuggestions() {
        withState { state in
            let pending = CorrectionRecord(raw: "张月", corrected: "张越", lastApp: "Notes")
            let ignored = CorrectionRecord(raw: "work body", corrected: "WorkBuddy", lastApp: "Notes")
            state.data.corrections = [pending, ignored]
            state.data.ignoreCorrection(ignored.id)
            #expect(state.data.pendingCorrections.map(\.id) == [pending.id])
        }
    }

    @Test("the overlay asks about the same correction at most twice")
    func correctionPromptLimit() {
        withState { state in
            let change = CorrectionCandidate(before: "张月", after: "张越")
            state.workflow.noteCorrection(change, app: "Notes", windowTitle: "")
            #expect(state.workflow.overlayError == localized("Remember “\("张月")” as “\("张越")”?"))
            #expect(state.workflow.overlayButtons.map(\.title) == [localized("Not Now"), localized("Remember")])
            state.workflow.pressOverlayButton(at: 0)
            #expect(state.workflow.overlayError == nil)
            #expect(state.workflow.overlayButtons.isEmpty)

            state.workflow.noteCorrection(change, app: "Mail", windowTitle: "")
            #expect(state.workflow.overlayError != nil)
            state.workflow.pressOverlayButton(at: 0)

            state.workflow.noteCorrection(change, app: "Notes", windowTitle: "")
            #expect(state.workflow.overlayError == nil)
            #expect(state.data.corrections.count == 1)
            #expect(state.data.corrections.first?.count == 3)
            #expect(state.data.corrections.first?.promptCount == CorrectionRecord.promptLimit)
            #expect(state.data.pendingCorrections.count == 1)
            #expect(state.data.memoryEntities.isEmpty)
        }
    }

    @Test("Remember on the overlay saves the correction right away")
    func rememberFromOverlay() {
        withState { state in
            let change = CorrectionCandidate(before: "work body", after: "WorkBuddy")
            state.workflow.noteCorrection(change, app: "Notes", windowTitle: "")
            state.workflow.pressOverlayButton(at: 1)
            #expect(state.data.memoryEntities.map(\.name) == ["WorkBuddy"])
            #expect(state.data.memoryEntities.first?.aliases == ["work body"])
            #expect(state.data.corrections.first?.status == .accepted)
            #expect(state.workflow.overlayError == localized("Remembered"))
            #expect(state.workflow.overlayButtons.isEmpty)
            #expect(state.data.pendingCorrections.isEmpty)

            state.workflow.noteCorrection(change, app: "Notes", windowTitle: "")
            #expect(state.workflow.overlayButtons.isEmpty)
        }
    }

    @Test("the clue names the app and window title, unless window titles aren't shared")
    func correctionClue() {
        withState { state in
            state.workflow.noteCorrection(CorrectionCandidate(before: "张月", after: "张越"), app: "Notes", windowTitle: "Weekly sync")
            state.workflow.pressOverlayButton(at: 1)
            #expect(state.data.memoryEntities.first?.detail == "Notes · Weekly sync")

            state.settings.windowTitleAllowed = false
            state.workflow.noteCorrection(CorrectionCandidate(before: "work body", after: "WorkBuddy"), app: "Slack", windowTitle: "#product")
            state.workflow.pressOverlayButton(at: 1)
            #expect(state.data.memoryEntities.last?.detail == "Slack")
        }
    }

    @Test("a correction noticed while recording waits in Suggestions")
    func correctionDuringRecording() {
        withState { state in
            state.workflow.dictationPhase = .listening
            state.workflow.noteCorrection(CorrectionCandidate(before: "张月", after: "张越"), app: "Notes", windowTitle: "")
            #expect(state.workflow.overlayError == nil)
            #expect(state.data.corrections.first?.promptCount == 0)
            #expect(state.data.pendingCorrections.count == 1)
        }
    }

    @Test("a correction to an automatically learned name renames it instead of adding another")
    func selfHealingCorrection() {
        let learned = MemoryEntity(name: "张月", type: .person, aliases: ["张悦"], source: .correction)
        let entities = MemoryPipeline.learn("张月", as: "张越", clue: "Notes", into: [learned])
        #expect(entities.count == 1)
        #expect(entities.first?.id == learned.id)
        #expect(entities.first?.name == "张越")
        #expect(entities.first?.aliases == ["张悦", "张月"])
        #expect(entities.first?.type == .person)
        #expect(entities.first?.source == .correction)
        #expect(entities.first?.detail == "Notes")
    }

    @Test("a correction never renames an item the user saved")
    func correctionKeepsSavedItems() {
        let saved = MemoryEntity(name: "张月", type: .person)
        let entities = MemoryPipeline.learn("张月", as: "张越", clue: "Notes", into: [saved])
        #expect(entities.map(\.name) == ["张月", "张越"])
        #expect(entities.first == saved)
        #expect(entities.last?.aliases == ["张月"])
    }

    @Test("a mistaken learned item folds into the item it should have been")
    func correctionFoldsIntoExistingItem() {
        let saved = MemoryEntity(name: "张越", type: .person, aliases: ["Visoar"])
        let learned = MemoryEntity(name: "张月", type: .term, aliases: ["张悦"], source: .correction)
        let entities = MemoryPipeline.learn("张月", as: "张越", clue: "Notes", into: [saved, learned])
        #expect(entities.count == 1)
        #expect(entities.first?.id == saved.id)
        #expect(entities.first?.aliases == ["Visoar", "张悦", "张月"])
        #expect(entities.first?.source == .manual)
        #expect(entities.first?.detail == "Notes")
    }

    @Test("learning the same correction twice adds the alias once")
    func repeatedCorrection() {
        let once = MemoryPipeline.learn("work body", as: "WorkBuddy", clue: "Notes", into: [])
        let twice = MemoryPipeline.learn("work body", as: "WorkBuddy", clue: "Mail", into: once)
        #expect(twice == once)
        #expect(twice.first?.aliases == ["work body"])
        // A clue someone already has, or edited, is never replaced.
        #expect(twice.first?.detail == "Notes")
    }
}
