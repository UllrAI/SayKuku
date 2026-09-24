import Foundation
import SwiftUI

enum QwenRegion: String, Codable, CaseIterable, Identifiable {
    case beijing
    case singapore

    var id: String { rawValue }
    var legacyHost: String { self == .beijing ? "dashscope.aliyuncs.com" : "dashscope-intl.aliyuncs.com" }

    func host(workspaceID: String) -> String {
        guard !workspaceID.isEmpty else { return legacyHost }
        return self == .beijing
            ? "\(workspaceID).cn-beijing.maas.aliyuncs.com"
            : "\(workspaceID).ap-southeast-1.maas.aliyuncs.com"
    }

    func title(isChineseUI: Bool) -> String {
        switch self {
        case .beijing: isChineseUI ? "中国内地（北京）" : "China (Beijing)"
        case .singapore: isChineseUI ? "国际（新加坡）" : "International (Singapore)"
        }
    }
}

enum QwenModelCatalog {
    static let defaultRealtimeModel = "qwen3.5-omni-flash-realtime"
    static let defaultReasoningModel = "qwen3.8-omni-flash"
    static let realtimeModels = [defaultRealtimeModel]
    static let reasoningModels = [defaultReasoningModel, "qwen3.5-omni-plus", "qwen3.5-omni-flash"]

    // Realtime IDs saved by earlier builds that cannot run the omni realtime session.
    private static let retiredRealtimeModels: Set<String> = ["qwen3.8-omni-flash-realtime"]
    private static let retiredRealtimeModelPrefixes = ["qwen3-asr-flash-realtime"]

    static func realtimeModel(stored: String?) -> String {
        let value = normalized(stored)
        let isRetired = retiredRealtimeModels.contains(value)
            || retiredRealtimeModelPrefixes.contains { value.hasPrefix($0) }
        return value.isEmpty || isRetired ? defaultRealtimeModel : value
    }

    static func reasoningModel(stored: String?) -> String {
        let value = normalized(stored)
        return value.isEmpty ? defaultReasoningModel : value
    }

    /// Presets plus the current value, so a custom or older model stays visible in pickers.
    static func options(_ presets: [String], including current: String) -> [String] {
        presets.contains(current) || current.isEmpty ? presets : presets + [current]
    }

    private static func normalized(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

enum APIKeyDraftState: Equatable {
    case empty, saved, modified, cleared

    init(draft: String, saved: String) {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if value == saved { self = saved.isEmpty ? .empty : .saved }
        else { self = value.isEmpty ? .cleared : .modified }
    }

    var hasChanges: Bool { self == .modified || self == .cleared }
}

struct QwenConfiguration: Equatable {
    var region: QwenRegion
    var workspaceID: String
    var realtimeModel: String
    var reasoningModel: String

    var realtimeURL: URL? {
        var components = URLComponents()
        components.scheme = "wss"
        components.host = region.host(workspaceID: workspaceID)
        components.path = "/api-ws/v1/realtime"
        components.queryItems = [URLQueryItem(name: "model", value: realtimeModel)]
        return components.url
    }

    var chatCompletionsURL: URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = region.host(workspaceID: workspaceID)
        components.path = "/compatible-mode/v1/chat/completions"
        return components.url
    }
}

enum RecognitionLanguage: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case chinese
    case english

    var id: String { rawValue }

    func title(isChineseUI: Bool) -> String {
        switch self {
        case .automatic: isChineseUI ? "自动（中英混合）" : "Auto (Chinese & English)"
        case .chinese: "简体中文"
        case .english: "English"
        }
    }

    var promptInstruction: String {
        switch self {
        case .automatic:
            "Detect the spoken language automatically. Preserve the original language and natural code-switching. Never translate."
        case .chinese:
            "Treat Mandarin Chinese as the primary recognition language and output Chinese speech in Simplified Chinese. Preserve clearly spoken words in other languages. Never translate."
        case .english:
            "Treat English as the primary recognition language. Preserve clearly spoken words in other languages. Never translate."
        }
    }
}

enum DictationNumberFormat: String, CaseIterable, Identifiable, Sendable {
    case preferDigits
    case spoken

    var id: String { rawValue }

    func title(isChineseUI: Bool) -> String {
        switch self {
        case .preferDigits: isChineseUI ? "优先阿拉伯数字" : "Prefer digits"
        case .spoken: isChineseUI ? "保持口述" : "As spoken"
        }
    }

    var promptInstruction: String {
        switch self {
        case .preferDigits:
            "Use Arabic digits for unambiguous numbers, dates, times, amounts, percentages, measurements, phone numbers, and codes. Preserve idioms, proper nouns, and ambiguous number words as spoken."
        case .spoken:
            "Preserve number expressions as spoken instead of converting number words into digits. Keep explicitly dictated digit sequences, codes, and existing numeric forms unchanged."
        }
    }
}

enum DictationCleanup: String, CaseIterable, Identifiable, Sendable {
    case light
    case verbatim

    var id: String { rawValue }

    func title(isChineseUI: Bool) -> String {
        switch self {
        case .light: isChineseUI ? "轻整理" : "Light cleanup"
        case .verbatim: isChineseUI ? "原样" : "Verbatim"
        }
    }

    var promptInstruction: String {
        switch self {
        case .light:
            """
            LIGHT CLEANUP: Return the cleaned final utterance, not the raw speech trace. Silently remove clear, meaningless fillers (嗯、呃、啊、额、那个、就是、然后、uh、um、you know), accidental immediate repeats, and abandoned starts. For a clear self-correction, keep the final wording. Do this cleanup even when the audio model initially recognizes those filler words.
            Remove adjacent repeats of hesitation words and short fragments, even without a pause: "这个这个新版本" → "这个新版本", "我我觉得" → "我觉得", "然后，然后再提交" → "然后再提交". Also: "嗯，我觉得，呃，这个方案可以" → "我觉得这个方案可以。"; "周三，不对，周四见" → "周四见。"
            Keep meaningful uses of the same words: "那个方案" keeps 那个, "这就是原因" keeps 就是, and "然后提交" keeps 然后 when it marks sequence. Keep deliberate repetition, quoted speech, uncertainty, and all meaningful content. If unsure whether a word is filler or content, keep it. Never paraphrase or add information.
            """
        case .verbatim:
            "VERBATIM: Keep fillers, repetitions, false starts, and self-corrections as spoken. Add punctuation, but do not clean up or rewrite the speech."
        }
    }
}

enum SpeechDisfluencyCleaner {
    private static let repeatedLeadIn = try! NSRegularExpression(
        pattern: #"(这个|那个|就是|然后|其实|所以|我)(?:[ \t，,、]*\1)+"#
    )

    static func clean(_ text: String, mode: DictationCleanup) -> String {
        var result = ""
        var segment = ""
        var closingQuote: Character?
        let quotes: [Character: Character] = ["“": "”", "「": "」", "『": "』", "\"": "\"", "`": "`"]

        for character in text {
            if let quote = closingQuote {
                result.append(character)
                if character == quote { closingQuote = nil }
            } else if let close = quotes[character] {
                result += cleanSegment(segment, deduplicate: mode == .light)
                segment = ""
                result.append(character)
                closingQuote = close
            } else {
                segment.append(character)
            }
        }
        result += cleanSegment(segment, deduplicate: mode == .light)
        return result
    }

    private static func cleanSegment(_ segment: String, deduplicate: Bool) -> String {
        let range = NSRange(segment.startIndex..<segment.endIndex, in: segment)
        let text = deduplicate
            ? repeatedLeadIn.stringByReplacingMatches(in: segment, range: range, withTemplate: "$1")
            : segment
        let characters = Array(text)
        return String(characters.indices.map { index in
            let character = characters[index]
            let previous = index > 0 ? characters[index - 1] : nil
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            guard isChinese(previous) || isChinese(next) else { return character }
            switch character {
            case ",": return "，"
            case "?": return "？"
            case "!": return "！"
            case ";": return "；"
            case ":": return "："
            // Only a sentence-ending period becomes 。, so names like 报告.pdf stay intact.
            case "." where isChinese(previous) && !isASCIIAlphanumeric(next): return "。"
            default: return character
            }
        })
    }

    private static func isASCIIAlphanumeric(_ character: Character?) -> Bool {
        guard let character, character.isASCII else { return false }
        return character.isLetter || character.isNumber
    }

    private static func isChinese(_ character: Character?) -> Bool {
        character?.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) } ?? false
    }
}

enum DomainPreset: String, CaseIterable, Identifiable, Sendable {
    case aiVibeCoding
    case softwareDevelopment
    case productDesign
    case productManagement
    case marketingGrowth
    case contentCreation
    case finance
    case healthcare
    case legal

    var id: String { rawValue }

    func title(isChineseUI: Bool) -> String {
        switch self {
        case .aiVibeCoding: "AI / Vibe Coding"
        case .softwareDevelopment: isChineseUI ? "软件开发" : "Software Development"
        case .productDesign: isChineseUI ? "产品设计" : "Product Design"
        case .productManagement: isChineseUI ? "产品管理" : "Product Management"
        case .marketingGrowth: isChineseUI ? "市场与增长" : "Marketing & Growth"
        case .contentCreation: isChineseUI ? "内容创作" : "Content Creation"
        case .finance: isChineseUI ? "金融与投资" : "Finance & Investing"
        case .healthcare: isChineseUI ? "医疗健康" : "Healthcare"
        case .legal: isChineseUI ? "法律" : "Legal"
        }
    }

    var symbol: String {
        switch self {
        case .aiVibeCoding: "sparkles"
        case .softwareDevelopment: "chevron.left.forwardslash.chevron.right"
        case .productDesign: "scribble.variable"
        case .productManagement: "map"
        case .marketingGrowth: "chart.line.uptrend.xyaxis"
        case .contentCreation: "text.quote"
        case .finance: "chart.pie.fill"
        case .healthcare: "cross.case.fill"
        case .legal: "building.columns.fill"
        }
    }

    var promptName: String {
        switch self {
        case .aiVibeCoding: "AI and Vibe Coding"
        case .softwareDevelopment: "Software Development"
        case .productDesign: "Product Design"
        case .productManagement: "Product Management"
        case .marketingGrowth: "Marketing and Growth"
        case .contentCreation: "Content Creation"
        case .finance: "Finance and Investing"
        case .healthcare: "Healthcare"
        case .legal: "Legal"
        }
    }

    var vocabulary: [String] {
        switch self {
        case .aiVibeCoding: ["Vibe Coding", "AI Agent", "LLM", "prompt", "MCP", "Cursor", "Claude Code", "Codex"]
        case .softwareDevelopment: ["GitHub", "API", "SDK", "frontend", "backend", "TypeScript", "SwiftUI", "React"]
        case .productDesign: ["Figma", "UI", "UX", "prototype", "design system", "user flow"]
        case .productManagement: ["PRD", "roadmap", "MVP", "user story", "backlog", "OKR"]
        case .marketingGrowth: ["SEO", "SEM", "conversion rate", "campaign", "retention", "acquisition"]
        case .contentCreation: ["podcast", "newsletter", "copywriting", "storyboard", "thumbnail"]
        case .finance: ["cash flow", "EBITDA", "valuation", "portfolio", "dividend"]
        case .healthcare: ["diagnosis", "prescription", "clinical", "patient", "telemedicine"]
        case .legal: ["contract", "clause", "compliance", "liability", "jurisdiction"]
        }
    }
}

enum HistoryRetention: String, Codable, CaseIterable, Identifiable {
    case day1, days7, days30, days90, forever

    var id: String { rawValue }
    var days: Int? {
        switch self {
        case .day1: 1
        case .days7: 7
        case .days30: 30
        case .days90: 90
        case .forever: nil
        }
    }
    var chineseTitle: String {
        switch self {
        case .day1: "1 天"
        case .days7: "7 天"
        case .days30: "30 天"
        case .days90: "90 天"
        case .forever: "永久"
        }
    }
    var englishTitle: String {
        switch self {
        case .day1: "1 day"
        case .days7: "7 days"
        case .days30: "30 days"
        case .days90: "90 days"
        case .forever: "Forever"
        }
    }
    /// Option label for the "Delete history after" picker, where keeping history forever reads as "Never".
    @MainActor func title(_ appState: AppState) -> String {
        self == .forever ? appState.text("永不", "Never") : appState.text(chineseTitle, englishTitle)
    }
}

enum HistoryMode: String, Codable {
    case dictation, agent
    var filter: HistoryFilter { self == .dictation ? .dictation : .agent }
    var symbol: String { self == .dictation ? "mic.fill" : "sparkles" }
    @MainActor func title(_ appState: AppState) -> String {
        self == .dictation ? appState.voiceInputTitle : appState.voiceAgentTitle
    }
}

enum HistoryStatus: String, Codable {
    case processing
    case completed
    case failed
    case cancelled
}

struct HistoryEntry: Identifiable, Codable, Equatable {
    var id: UUID
    var mode: HistoryMode
    var app: String
    var createdAt: Date
    var durationSeconds: Double
    var input: String
    var output: String
    var audioFilename: String?
    var isStarred: Bool
    var status: HistoryStatus
    var errorMessage: String?

    init(
        id: UUID = UUID(), mode: HistoryMode, app: String, createdAt: Date = .now,
        durationSeconds: Double, input: String, output: String,
        audioFilename: String? = nil, isStarred: Bool = false,
        status: HistoryStatus = .completed, errorMessage: String? = nil
    ) {
        self.id = id
        self.mode = mode
        self.app = app
        self.createdAt = createdAt
        self.durationSeconds = durationSeconds
        self.input = input
        self.output = output
        self.audioFilename = audioFilename
        self.isStarred = isStarred
        self.status = status
        self.errorMessage = errorMessage
    }

    var hasAudio: Bool { audioFilename != nil }

    private enum CodingKeys: String, CodingKey {
        case id, mode, app, createdAt, durationSeconds, input, output, audioFilename, isStarred, status, errorMessage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        mode = try container.decode(HistoryMode.self, forKey: .mode)
        app = try container.decode(String.self, forKey: .app)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        durationSeconds = try container.decode(Double.self, forKey: .durationSeconds)
        input = try container.decode(String.self, forKey: .input)
        output = try container.decode(String.self, forKey: .output)
        audioFilename = try container.decodeIfPresent(String.self, forKey: .audioFilename)
        isStarred = try container.decode(Bool.self, forKey: .isStarred)
        status = try container.decodeIfPresent(HistoryStatus.self, forKey: .status) ?? .completed
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
    }
}

enum EntityType: String, Codable, CaseIterable, Identifiable {
    case person, organization, orgUnit, project, product, term, unknown
    var id: String { rawValue }
    @MainActor func title(_ appState: AppState) -> String {
        switch self {
        case .person: appState.text("人物", "Person")
        case .organization: appState.text("组织", "Organization")
        case .orgUnit: appState.text("部门", "Department")
        case .project: appState.text("项目", "Project")
        case .product: appState.text("产品", "Product")
        case .term: appState.text("术语", "Term")
        case .unknown: appState.text("未分类", "Uncategorized")
        }
    }
    var symbol: String {
        switch self {
        case .person: "person.fill"
        case .organization, .orgUnit: "building.2.fill"
        case .project: "folder.fill"
        case .product: "shippingbox.fill"
        case .term, .unknown: "character.book.closed.fill"
        }
    }
    var color: Color {
        switch self {
        case .person: KukuColor.coral
        case .organization, .orgUnit: Color(red: 0.34, green: 0.50, blue: 0.75)
        case .project: Color(red: 0.58, green: 0.43, blue: 0.72)
        case .product: KukuColor.amber
        case .term, .unknown: KukuColor.mint
        }
    }
    /// `color` for small labels, using the darker text variants of mint and amber.
    var textColor: Color {
        switch self {
        case .product: KukuColor.amberText
        case .term, .unknown: KukuColor.mintText
        default: color
        }
    }
    var filter: KnowledgeFilter {
        switch self {
        case .person: .people
        case .organization, .orgUnit: .organizations
        case .project, .product: .projects
        case .term, .unknown: .terms
        }
    }
}

enum EntitySource: String, Codable { case manual, importText, correction }

struct KnowledgeEntity: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var normalizedKey: String
    var detail: String
    var type: EntityType
    var aliases: [String]
    var source: EntitySource
    var createdAt: Date

    init(
        id: UUID = UUID(), name: String, detail: String = "", type: EntityType,
        aliases: [String] = [], source: EntitySource = .manual, createdAt: Date = .now
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = KnowledgeNormalizer.key(name)
        normalizedKey = key
        self.detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        self.type = type
        var aliasKeys = Set<String>()
        self.aliases = aliases.compactMap { alias in
            let value = alias.trimmingCharacters(in: .whitespacesAndNewlines)
            let aliasKey = KnowledgeNormalizer.key(value)
            guard !aliasKey.isEmpty, aliasKey != key, aliasKeys.insert(aliasKey).inserted else { return nil }
            return value
        }
        self.source = source
        self.createdAt = createdAt
    }
}

enum KnowledgeSaveError: Error, Equatable {
    /// The name has no letters or digits left after normalization.
    case emptyName
    case duplicate(existingName: String)

    @MainActor func message(_ appState: AppState) -> String {
        switch self {
        case .emptyName:
            appState.text("名称里要有文字或数字", "A name needs at least one letter or number")
        case .duplicate(let name):
            appState.text("已有同名条目“\(name)”", "“\(name)” is already in Knowledge")
        }
    }
}

enum RelationshipType: String, Codable, CaseIterable {
    case belongsTo, worksOn, owns, relatedTo

    @MainActor func title(_ appState: AppState) -> String {
        switch self {
        case .belongsTo: appState.text("属于", "belongs to")
        case .worksOn: appState.text("参与", "works on")
        case .owns: appState.text("负责", "owns")
        case .relatedTo: appState.text("相关", "related to")
        }
    }
}

struct KnowledgeRelationship: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var fromEntityID: UUID
    var type: RelationshipType
    var toEntityID: UUID
    var evidence: String
}

enum ImportStatus: String, Codable {
    case new = "NEW", merge = "MERGE", conflict = "CONFLICT", ignored = "IGNORED"

    @MainActor func title(_ appState: AppState) -> String {
        switch self {
        case .new: appState.text("新增", "New")
        case .merge: appState.text("更新已有条目", "Updates existing")
        case .conflict: appState.text("可能重复", "Possible duplicate")
        case .ignored: appState.text("已忽略", "Ignored")
        }
    }
}

struct ImportCandidate: Identifiable, Equatable {
    var id: UUID = UUID()
    var entity: KnowledgeEntity
    var status: ImportStatus
    var evidence: String
    var matchedEntityID: UUID?
}

struct ProposedRelationship: Codable, Equatable {
    var from: String
    var type: RelationshipType
    var to: String
    var evidence: String
}

struct ImportRelationshipCandidate: Identifiable, Equatable {
    var id: UUID = UUID()
    var relationship: ProposedRelationship
    var status: ImportStatus
}

struct ProposedEntity: Codable, Equatable {
    var name: String
    var type: EntityType
    var detail: String
    var aliases: [String]
    var evidence: String
}

struct CorrectionRecord: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var raw: String
    var corrected: String
    var count: Int = 1
    var lastApp: String
    var lastSeenAt: Date = .now
    var status: Status = .pending

    enum Status: String, Codable { case pending, accepted, ignored }
}

struct AgentSession: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var app: String
    var contextSummary: String
    var userCommand: String
    var response: String
    var createdAt: Date = .now
    var expiresAt: Date

    /// Turns kept per app for continuous conversation.
    static let turnLimit = 3

    /// Unexpired turns for `app`, oldest first.
    static func conversation(in sessions: [AgentSession], app: String, now: Date = .now) -> [AgentSession] {
        Array(sessions
            .filter { $0.app == app && $0.expiresAt > now }
            .sorted { $0.createdAt < $1.createdAt }
            .suffix(turnLimit))
    }

    /// Drops expired turns and keeps only the latest turns for the new turn's app.
    static func appending(_ turn: AgentSession, to sessions: [AgentSession], now: Date = .now) -> [AgentSession] {
        let otherApps = sessions.filter { $0.app != turn.app && $0.expiresAt > now }
        return otherApps + conversation(in: sessions, app: turn.app, now: now).suffix(turnLimit - 1) + [turn]
    }
}

struct ContextItem: Identifiable, Equatable {
    enum Kind: Equatable { case selectedText, previousOutput, app, window, clipboard, browser, session, domain, knowledge }
    var id = UUID()
    var kind: Kind
    var symbol: String
    var title: String
    var value: String
}

struct AgentResponse: Codable, Equatable {
    enum Action: String, Codable { case writeText, answer, openURL, webSearch, runShortcut }
    enum Target: String, Codable { case current, previous }
    var transcript: String?
    var action: Action
    var target: Target?
    var intent: String
    var output: String?
    var url: String?
    var query: String?
    var shortcutName: String?
}

enum KnowledgeNormalizer {
    static func key(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
            .lowercased()
    }
}
