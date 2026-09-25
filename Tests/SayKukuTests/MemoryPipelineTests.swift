import Foundation
import Testing
@testable import SayKuku

@Suite("Memory pipeline")
struct MemoryPipelineTests {
    @Test("normalization removes separators and case")
    func normalization() {
        #expect(MemoryNormalizer.key(" Bifro-MQ ") == "bifromq")
        #expect(MemoryNormalizer.key("Ani Kuku") == "anikuku")
    }

    @Test("normalized key follows the name and ignores the system locale")
    func derivedNormalizedKey() {
        var entity = MemoryEntity(name: "AniKuku", type: .project)
        entity.name = "Work Buddy"
        #expect(entity.normalizedKey == "workbuddy")
        #expect(MemoryNormalizer.key("İstanbul") == MemoryNormalizer.key("istanbul"))
        #expect(MemoryNormalizer.key("İstanbul") == "istanbul")
    }

    @Test("PII is redacted before model extraction")
    func redaction() {
        let result = MemoryPipeline.redactingPII(in: "王涛 18600000000 wang@example.com\n地址：北京市朝阳区测试路 1 号")
        #expect(!result.text.contains("18600000000"))
        #expect(!result.text.contains("wang@example.com"))
        #expect(result.ignored.count == 3)
        #expect(result.ignored.allSatisfy { $0.status == .ignored && $0.entity.name.isEmpty })
        #expect(!result.ignored.contains { $0.evidence.contains("18600000000") || $0.evidence.contains("wang@example.com") })
    }

    @Test("PII filtering covers IDs, bank cards, and international phones")
    func extendedRedaction() {
        let source = """
        身份证 11010119900307123X
        卡号 6222 0212 3456 7890 123，备用 6222021234567890
        电话+1 (415) 555-0100，手机 186 0000 0000
        住址：上海市徐汇区测试路 2 号
        """
        let result = MemoryPipeline.redactingPII(in: source)
        let sensitive = [
            "11010119900307123X", "6222 0212 3456 7890 123", "6222021234567890",
            "+1 (415) 555-0100", "186 0000 0000", "上海市徐汇区"
        ]
        for value in sensitive {
            #expect(!result.text.contains(value))
        }
        #expect(result.ignored.count == 6)
    }

    @Test("PII filtering leaves ordinary numbers alone")
    func ordinaryNumbersSurviveRedaction() {
        let source = "2024 年营收 12345678 元，订单 A12345，版本 1.2.3，编号 123456789012，时间 2024-09-24 10:00，C++ 20，得分 +12.5"
        let result = MemoryPipeline.redactingPII(in: source)
        #expect(result.text == source)
        #expect(result.ignored.isEmpty)
    }

    @Test("filtered values keep only a short hint")
    func maskedEvidence() {
        #expect(MemoryPipeline.masked("11010119900307123X") == "110••••23X")
        #expect(MemoryPipeline.masked("18600000000") == "18••••00")
        #expect(MemoryPipeline.masked("abc") == "••••")
        #expect(MemoryPipeline.displayEvidence("王涛 [FILTERED] 负责") == "王涛 •••• 负责")
    }

    @Test("exact aliases merge while similar names require confirmation")
    func deduplication() {
        let existing = [MemoryEntity(name: "WorkBuddy", type: .project, aliases: ["work body"])]
        let proposals = [
            ProposedEntity(name: "work body", type: .project, detail: "", aliases: [], evidence: "work body"),
            ProposedEntity(name: "WorkBudy", type: .project, detail: "", aliases: [], evidence: "WorkBudy"),
            ProposedEntity(name: "AniKuku", type: .project, detail: "", aliases: [], evidence: "AniKuku")
        ]
        let result = MemoryPipeline.analyze(proposals: proposals, existing: existing, ignored: [])
        let statuses = Dictionary(uniqueKeysWithValues: result.candidates.map { ($0.entity.name, $0.status) })
        #expect(statuses["work body"] == .merge)
        #expect(statuses["WorkBudy"] == .conflict)
        #expect(statuses["AniKuku"] == .new)
    }

    @Test("homophone Chinese names require confirmation")
    func pinyinConflict() {
        #expect(MemoryNormalizer.pinyinKey("张越") == "zhangyue")
        #expect(MemoryNormalizer.pinyinKey("张月") == "zhangyue")
        #expect(MemoryNormalizer.pinyinKey("WorkBuddy") == nil)

        let zhangYue = MemoryEntity(name: "张越", type: .person)
        let existing = [zhangYue, MemoryEntity(name: "王明", type: .person), MemoryEntity(name: "WorkBuddy", type: .project)]
        let proposals = [
            ProposedEntity(name: "张月", type: .person, detail: "", aliases: [], evidence: "张月"),
            ProposedEntity(name: "WorkBudy", type: .project, detail: "", aliases: [], evidence: "WorkBudy"),
            ProposedEntity(name: "李明", type: .person, detail: "", aliases: [], evidence: "李明")
        ]
        let result = MemoryPipeline.analyze(proposals: proposals, existing: existing, ignored: [])
        let candidates = Dictionary(uniqueKeysWithValues: result.candidates.map { ($0.entity.name, $0) })
        #expect(candidates["张月"]?.status == .conflict)
        #expect(candidates["张月"]?.matchedEntityID == zhangYue.id)
        #expect(candidates["WorkBudy"]?.status == .conflict)
        #expect(candidates["李明"]?.status == .new)
    }

    @Test("only selected candidates are committed")
    func commit() throws {
        let proposals = [
            ProposedEntity(name: "张越", type: .person, detail: "Founder", aliases: ["Visoar"], evidence: "负责人张越"),
            ProposedEntity(name: "AniKuku", type: .project, detail: "Project", aliases: [], evidence: "项目 AniKuku")
        ]
        let analysis = MemoryPipeline.analyze(proposals: proposals, existing: [], ignored: [])
        let selected = try #require(analysis.candidates.first { $0.entity.name == "AniKuku" })
        let result = MemoryPipeline.commit(analysis: analysis, selectedIDs: [selected.id], existing: [])
        #expect(result.map(\.name) == ["AniKuku"])
    }

    @Test("long imports are split without losing text")
    func chunking() {
        let source = String(repeating: "abcdef", count: 100)
        let chunks = MemoryPipeline.chunks(source, limit: 64)
        #expect(chunks.allSatisfy { $0.count <= 64 })
        #expect(chunks.joined() == source)
    }

    @Test("memory extraction tolerates missing fields and unknown types")
    func lenientMemoryExtraction() throws {
        let content = """
        ```json
        {"entities":[
          {"name":"WorkBuddy","type":"Product","evidence":"WorkBuddy 上线"},
          {"name":"Kuku","type":"company","detail":"团队","aliases":["库库"],"evidence":"Kuku 团队"},
          {"name":"Unclear","type":"misc","evidence":"Unclear name"},
          {"type":"person","evidence":"no name"},
          "not an object"
        ]}
        ```
        """
        let result = try #require(QwenReasoningClient.decodeMemoryExtraction(content))
        #expect(result == [
            ProposedEntity(name: "WorkBuddy", type: .project, detail: "", aliases: [], evidence: "WorkBuddy 上线"),
            ProposedEntity(name: "Kuku", type: .organization, detail: "团队", aliases: ["库库"], evidence: "Kuku 团队"),
            ProposedEntity(name: "Unclear", type: .other, detail: "", aliases: [], evidence: "Unclear name")
        ])
        #expect(QwenReasoningClient.decodeMemoryExtraction("not json") == nil)
    }

    @Test("memory edits preserve identity and normalize aliases")
    @MainActor
    func memoryEditing() {
        let environment = AppStateTestEnvironment()
        defer { environment.clean() }
        let originalDate = Date(timeIntervalSince1970: 1_700_000_000)
        let original = MemoryEntity(
            name: "AniKuku",
            detail: "Project",
            type: .project,
            aliases: ["Ani Kuku"],
            source: .importText,
            createdAt: originalDate
        )
        let state = environment.makeState()
        state.data.memoryEntities = [original, MemoryEntity(name: "WorkBuddy", type: .project)]

        #expect(state.data.updateMemory(
            id: original.id,
            name: " AniKuku Pro ",
            type: .project,
            detail: " Updated project ",
            aliases: ["Ani Kuku", " ani kuku ", "AniKuku Pro", ""]
        ) == nil)
        let edited = state.data.memoryEntities[0]
        #expect(edited.id == original.id)
        #expect(edited.name == "AniKuku Pro")
        #expect(edited.detail == "Updated project")
        #expect(edited.aliases == ["Ani Kuku"])
        #expect(edited.source == .importText)
        #expect(edited.createdAt == originalDate)
        #expect(state.data.updateMemory(
            id: original.id,
            name: "workbuddy",
            type: .project,
            detail: "",
            aliases: []
        ) == .duplicate(existingName: "WorkBuddy"))
        #expect(state.data.updateMemory(
            id: original.id,
            name: " !! ",
            type: .project,
            detail: "",
            aliases: []
        ) == .emptyName)
        #expect(state.data.memoryEntities[0].name == "AniKuku Pro")
    }
}
