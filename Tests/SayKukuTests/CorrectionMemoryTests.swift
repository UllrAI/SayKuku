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

    @Test("knowledge added without detail keeps it empty")
    func manualKnowledgeDetail() {
        withState { state in
            #expect(state.addKnowledge(name: "AniKuku", type: .project, detail: "  ") == nil)
            #expect(state.knowledgeEntities.first?.detail == "")
            #expect(state.addKnowledge(name: "WorkBuddy", type: .product) == nil)
            #expect(state.knowledgeEntities.first?.detail == "")
            #expect(state.addKnowledge(name: " ani kuku ", type: .term) == .duplicate(existingName: "AniKuku"))
            #expect(state.addKnowledge(name: "  ", type: .term) == .emptyName)
            #expect(state.knowledgeEntities.count == 2)
        }
    }

    @Test("accepted corrections carry no placeholder detail")
    func acceptedCorrection() {
        withState { state in
            let record = CorrectionRecord(raw: "王小明", corrected: "王晓明", lastApp: "TextEdit")
            state.corrections = [record]
            state.acceptCorrection(record.id)
            let entity = state.knowledgeEntities.first { $0.name == "王晓明" }
            #expect(entity?.detail == "")
            #expect(entity?.aliases == ["王小明"])
            #expect(entity?.source == .correction)
            #expect(state.corrections.first?.status == .accepted)
        }
    }

    @Test("short-term sessions can be cleared")
    func clearSessions() {
        withState { state in
            state.sessions = [AgentSession(
                app: "com.apple.TextEdit",
                contextSummary: "",
                userCommand: "Summarize",
                response: "Done",
                expiresAt: .now.addingTimeInterval(60)
            )]
            state.clearSessions()
            #expect(state.sessions.isEmpty)
        }
    }
}
