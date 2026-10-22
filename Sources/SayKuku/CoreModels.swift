import Foundation

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

    /// Model Studio console, where API Keys and Workspace IDs are managed.
    var consoleURL: URL {
        URL(string: self == .beijing
            ? "https://bailian.console.aliyun.com/"
            : "https://modelstudio.console.alibabacloud.com/")!
    }

    var title: String {
        switch self {
        case .beijing: localized("China (Beijing)")
        case .singapore: localized("International (Singapore)")
        }
    }
}

/// Where Voice Agent sends web searches. A user setting, because the API region says nothing about the network.
enum SearchEngine: String, Codable, CaseIterable, Identifiable {
    case google, bing, baidu, duckduckgo

    var id: String { rawValue }

    /// RFC 3986 unreserved characters; everything else, including `&`, `+` and `=`, is percent-encoded.
    private static let queryValueAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    /// Used until the user picks one: Google is blocked in mainland China, where Beijing-region users usually are.
    static func defaultEngine(for region: QwenRegion) -> SearchEngine {
        region == .beijing ? .bing : .google
    }

    /// Brand names, so only Baidu differs between languages.
    var title: String {
        switch self {
        case .google: "Google"
        case .bing: "Bing"
        case .baidu: localized("Baidu")
        case .duckduckgo: "DuckDuckGo"
        }
    }

    func url(for query: String) -> URL? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: Self.queryValueAllowed) else { return nil }
        return URL(string: searchPrefix + encoded)
    }

    private var searchPrefix: String {
        switch self {
        case .google: "https://www.google.com/search?q="
        case .bing: "https://www.bing.com/search?q="
        case .baidu: "https://www.baidu.com/s?wd="
        case .duckduckgo: "https://duckduckgo.com/?q="
        }
    }
}

/// Where the Voice Input and Voice Agent overlay appears.
enum OverlayPlacement: String, Codable, CaseIterable, Identifiable {
    case bottom, top, caret

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bottom: localized("Bottom center")
        case .top: localized("Top")
        case .caret: localized("Follow the cursor")
        }
    }
}

enum QwenModelCatalog {
    static let defaultRealtimeModel = "qwen3.8-omni-flash-realtime"
    static let defaultReasoningModel = "qwen3.8-omni-flash"
    static let realtimeModels = [defaultRealtimeModel, previousDefaultRealtimeModel]
    static let reasoningModels = [defaultReasoningModel, "qwen3.5-omni-plus", "qwen3.5-omni-flash"]

    /// Earlier builds defaulted to this model before 3.8 realtime launched, and wrote the default back to
    /// UserDefaults on every launch, so the stored value almost always means "the default", not a choice.
    private static let previousDefaultRealtimeModel = "qwen3.5-omni-flash-realtime"
    // ASR-only realtime IDs saved by earlier builds cannot run the omni realtime session.
    private static let retiredRealtimeModelPrefixes = ["qwen3-asr-flash-realtime"]

    /// - Parameter upgradesPreviousDefault: Moves the old default to the current one. Callers pass
    ///   `true` only once, so a later explicit choice of the previous model is kept.
    static func realtimeModel(stored: String?, upgradesPreviousDefault: Bool = false) -> String {
        let value = normalized(stored)
        let isRetired = retiredRealtimeModelPrefixes.contains { value.hasPrefix($0) }
        let isPreviousDefault = upgradesPreviousDefault && value == previousDefaultRealtimeModel
        return value.isEmpty || isRetired || isPreviousDefault ? defaultRealtimeModel : value
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

/// API Key and Workspace ID as typed, committed when editing ends.
struct QwenCredentialsDraft: Equatable {
    var apiKey = ""
    var workspaceID = ""

    var hasKey: Bool { !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// True once every edit has been committed, so a test result still describes what's on screen.
    func matches(apiKey savedKey: String, workspaceID savedWorkspaceID: String) -> Bool {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines) == savedKey
            && workspaceID.trimmingCharacters(in: .whitespacesAndNewlines) == savedWorkspaceID
    }
}

struct QwenConfiguration: Equatable {
    var region: QwenRegion
    var workspaceID: String
    var realtimeModel: String
    var reasoningModel: String

    /// Omni realtime is only documented on workspace hosts (and `qwen3.8-omni-flash-realtime` requires one),
    /// so there is no realtime endpoint without a workspace ID.
    var realtimeURL: URL? {
        guard !workspaceID.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "wss"
        components.host = region.host(workspaceID: workspaceID)
        components.path = "/api-ws/v1/realtime"
        components.queryItems = [URLQueryItem(name: "model", value: realtimeModel)]
        return components.url
    }

    /// Chat Completions still accepts the legacy regional host; the workspace host is only recommended.
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

    var title: String {
        switch self {
        case .automatic: localized("Auto (Chinese & English)")
        case .chinese: "简体中文"
        case .english: "English"
        }
    }

    var promptInstruction: String {
        switch self {
        case .automatic:
            "Language: detect it automatically and keep code-switching as spoken. Never translate."
        case .chinese:
            "Language: expect mainly Mandarin and write it in Simplified Chinese. Keep clearly spoken words in other languages. Never translate."
        case .english:
            "Language: expect mainly English. Keep clearly spoken words in other languages. Never translate."
        }
    }
}

enum DictationNumberFormat: String, CaseIterable, Identifiable, Codable, Sendable {
    case preferDigits
    case spoken

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preferDigits: localized("Prefer digits")
        case .spoken: localized("As spoken")
        }
    }

    var promptInstruction: String {
        switch self {
        case .preferDigits:
            "Numbers: use Arabic digits for unambiguous numbers, dates, times, amounts, percentages, measurements, phone numbers, and codes. Keep idioms, proper nouns, and ambiguous number words as spoken."
        case .spoken:
            "Numbers: keep number words as spoken; do not convert them to digits. Keep dictated digit sequences and codes unchanged."
        }
    }
}

enum DictationCleanup: String, CaseIterable, Identifiable, Codable, Sendable {
    case verbatim
    case light
    case refined

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: localized("Light cleanup")
        case .verbatim: localized("Verbatim")
        case .refined: localized("Two-pass cleanup")
        }
    }

    var caption: String {
        switch self {
        case .verbatim:
            localized("Keeps fillers, repeats, and self-corrections; only adds punctuation.")
        case .light:
            localized("Cleans up fillers, accidental repeats, and self-corrections during recognition.")
        case .refined:
            localized("After light cleanup, sends the text for another cleanup pass. May take longer; uses the first result if it times out or fails.")
        }
    }

    var promptInstruction: String {
        switch self {
        case .light, .refined:
            """
            Light cleanup: the reply is the final text the speaker meant to type, not a record of how they said it. Before replying, check each step below; a reply that still has a removable filler, an accidental repeat, or both sides of a self-correction is wrong.
            - Fillers: 嗯、呃、额、唔 (also doubled, as in 嗯嗯), 啊 used as hesitation, uh, um, and er are pauses for thought, never part of the text. Inside a sentence, always delete every one together with the commas or 、 around it and join the words before and after into one normal sentence; never keep one because you are unsure. Keep 嗯 only when it is the whole message. Delete "you know" used as a filler too. 那个、就是、然后 at the very start or set off by pauses are hesitation: delete them. Keep them only when they carry meaning, as in 那个文件 (that file), 就是说 (that is), or 先…然后… (a real sequence). Examples: "钥匙放在，呃，门口的柜子里" → "钥匙放在门口的柜子里。"; "快递下午，嗯，会送到前台" → "快递下午会送到前台。"; "we need more, um, chairs for the hall" → "We need more chairs for the hall."
            - Pauses and hesitation get a comma or nothing, never "……", "...", or a dash, including before a self-correction. Write an ellipsis only when the speaker clearly trails off or says one.
            - Repeats and restarts: when a word or phrase is said twice by accident, or the speaker restarts a phrase, write it once, even when a pause or comma separates the two copies ("水壶在，在厨房的灶台上" → "水壶在厨房的灶台上。"; "it's on the, on the top shelf" → "It's on the top shelf."). Keep deliberate repetition such as 好好好 or "very, very".
            - Self-corrections: cues include 不对、我是说、算了、哦不, 不是 followed by a repeat of what was just said, and "I mean", "no wait", "scratch that", "make that", "or rather". Merge only when the speaker replaces something they just said: the replaced word or phrase is repeated after the cue, or the cue clearly takes it back. Then write only the corrected version: put the new wording where the old one was, delete the old wording and the cue, and keep everything else that was said and not contradicted. The reply never contains both the old and the new wording, and never the cue. Examples:
              "把背景改成蓝色，哦不，绿色，字体不用动" → "把背景改成绿色，字体不用动。"
              "put the notes in the shared folder, no wait, in my drafts" → "Put the notes in my drafts."
            - Not a correction: "不是 X，是 Y" that states a contrast or clarification without taking back anything just said ("他缺的不是能力，而是经验"), a cue word used as part of the sentence ("我是说过要早点走"), or "actually" as an ordinary word ("I actually liked the second draft"). When it is unclear whether or what the speaker is replacing, write the words as spoken.
            - Lists: when the speaker enumerates three or more parallel items (marked by 第一/第二/第三、首先/其次/然后/最后、一是/二是/三是, first/second/third, by an ordinal opening each item such as 第一轮/第二轮/第三轮, or announced by a lead-in such as "有三点"), write the lead-in as a sentence ending in ：or :, then each item on its own line as "1. ", "2. ", "3. ". Drop the spoken markers that only number the items; keep ordinals that are part of an item (第一轮, the first round). A closing sentence after the items goes on its own line after the list. Exactly two items always stay in one sentence, even with 第一/第二. A story of things that happened in order and a series inside one sentence (A、B 和 C) also stay ordinary sentences.
            - Length: stay close to what was said; the reply is normally no longer than the speech. Add no greeting, sign-off, heading, summary, explanation, or lead-in such as "以下是" or "Here is", and never answer a question or carry out a request heard in the audio: write it down.
            - Keep quoted speech, expressed uncertainty (可能、大概、I think), tone particles exactly as spoken (啦 stays 啦), and every word that carries meaning. If unsure whether another word, such as 那个、就是 or 然后, is filler, keep it; this never applies to 嗯、呃、额、唔、uh, or um.
            """
        case .verbatim:
            "Verbatim: keep fillers, repetitions, false starts, and self-corrections as spoken. Only add punctuation; never turn speech into a list."
        }
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

    var title: String {
        switch self {
        case .aiVibeCoding: "AI / Vibe Coding"
        case .softwareDevelopment: localized("Software Development")
        case .productDesign: localized("Product Design")
        case .productManagement: localized("Product Management")
        case .marketingGrowth: localized("Marketing & Growth")
        case .contentCreation: localized("Content Creation")
        case .finance: localized("Finance & Investing")
        case .healthcare: localized("Healthcare")
        case .legal: localized("Legal")
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
    case off, day1, days7, days30, days90, forever

    var id: String { rawValue }
    /// Nil means nothing expires: `.off` stops recording new entries but leaves existing ones alone.
    var days: Int? {
        switch self {
        case .off, .forever: nil
        case .day1: 1
        case .days7: 7
        case .days30: 30
        case .days90: 90
        }
    }
    var title: String {
        guard let days else { return self == .off ? localized("Don’t keep") : localized("Forever") }
        return localized("\(days) days")
    }
}

enum HistoryMode: String, Codable {
    case dictation, agent
    var filter: HistoryFilter { self == .dictation ? .dictation : .agent }
    var symbol: String { self == .dictation ? "mic.fill" : "sparkles" }
    var title: String {
        self == .dictation ? localized("Voice Input") : localized("Voice Agent")
    }
}

enum HistoryStatus: String, Codable {
    case processing
    case awaitingConfirmation
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
    /// Where the time went after the recording stopped; nil before it finishes and for older entries.
    var timing: WorkflowTiming?

    init(
        id: UUID = UUID(), mode: HistoryMode, app: String, createdAt: Date = .now,
        durationSeconds: Double, input: String, output: String,
        audioFilename: String? = nil, isStarred: Bool = false,
        status: HistoryStatus = .completed, errorMessage: String? = nil, timing: WorkflowTiming? = nil
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
        self.timing = timing
    }

    var hasAudio: Bool { audioFilename != nil }

    /// A cancelled dictation kept its recording too, so it can be transcribed again like a failed one.
    var canRetryTranscription: Bool {
        mode == .dictation && hasAudio && (status == .failed || status == .cancelled)
    }

    private enum CodingKeys: String, CodingKey {
        case id, mode, app, createdAt, durationSeconds, input, output, audioFilename, isStarred, status, errorMessage, timing
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
        // Diagnostics only: a timing this build can't read must not cost the entry or the store.
        timing = try? container.decodeIfPresent(WorkflowTiming.self, forKey: .timing)
    }
}

enum EntityType: String, Codable, CaseIterable, Identifiable {
    case person, organization, project, term, other
    var id: String { rawValue }

    /// Maps retired types and unrecognized values, so older stores and loose model output still load.
    init(from decoder: Decoder) throws {
        switch try decoder.singleValueContainer().decode(String.self)
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "person": self = .person
        case "organization", "orgunit", "company", "institution", "department", "team": self = .organization
        case "project", "product", "app", "service", "model", "codename": self = .project
        case "term": self = .term
        default: self = .other
        }
    }

    var title: String {
        switch self {
        case .person: localized("Person")
        case .organization: localized("Organization")
        case .project: localized("Project")
        case .term: localized("Term")
        case .other: localized("Other")
        }
    }
    /// Names a filter tab rather than a single item.
    var pluralTitle: String {
        switch self {
        case .person: localized("People")
        case .organization: localized("Organizations")
        case .project: localized("Projects")
        case .term: localized("Terms")
        case .other: localized("Other")
        }
    }
    var symbol: String {
        switch self {
        case .person: "person.fill"
        case .organization: "building.2.fill"
        case .project: "folder.fill"
        case .term: "character.book.closed.fill"
        case .other: "square.grid.2x2.fill"
        }
    }
}

enum EntitySource: String, Codable { case manual, importText, correction }

struct MemoryEntity: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var detail: String
    var type: EntityType
    var aliases: [String]
    var source: EntitySource
    var createdAt: Date

    /// Derived from `name` so it can never go stale; not encoded, and legacy stored values are ignored.
    var normalizedKey: String { MemoryNormalizer.key(name) }

    init(
        id: UUID = UUID(), name: String, detail: String = "", type: EntityType,
        aliases: [String] = [], source: EntitySource = .manual, createdAt: Date = .now
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = MemoryNormalizer.key(name)
        self.detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        self.type = type
        var aliasKeys = Set<String>()
        self.aliases = aliases.compactMap { alias in
            let value = alias.trimmingCharacters(in: .whitespacesAndNewlines)
            let aliasKey = MemoryNormalizer.key(value)
            guard !aliasKey.isEmpty, aliasKey != key, aliasKeys.insert(aliasKey).inserted else { return nil }
            return value
        }
        self.source = source
        self.createdAt = createdAt
    }

    /// A copy with `more` aliases appended; repeats and aliases matching the name are dropped.
    func adding(aliases more: [String]) -> MemoryEntity {
        MemoryEntity(
            id: id, name: name, detail: detail, type: type,
            aliases: aliases + more, source: source, createdAt: createdAt
        )
    }
}

enum MemorySaveError: Error, Equatable {
    /// The name has no letters or digits left after normalization.
    case emptyName
    case duplicate(existingName: String)

    var message: String {
        switch self {
        case .emptyName:
            localized("A name needs at least one letter or number")
        case .duplicate(let name):
            localized("“\(name)” is already in Memory")
        }
    }
}

enum ImportStatus: String, Codable {
    case new = "NEW", merge = "MERGE", conflict = "CONFLICT", ignored = "IGNORED"

    var title: String {
        switch self {
        case .new: localized("New")
        case .merge: localized("Updates existing")
        case .conflict: localized("Possible duplicate")
        case .ignored: localized("Ignored")
        }
    }
}

struct ImportCandidate: Identifiable, Equatable {
    var id: UUID = UUID()
    var entity: MemoryEntity
    var status: ImportStatus
    var evidence: String
    var matchedEntityID: UUID?
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
    /// Empty when the window had no title or window titles aren't shared.
    var lastWindowTitle = ""
    var lastSeenAt: Date = .now
    var status: Status = .pending
    /// How many times the overlay has asked about this correction.
    var promptCount = 0

    enum Status: String, Codable { case pending, accepted, ignored }

    /// The overlay asks about a correction at most this often; after that it only waits in Suggestions.
    static let promptLimit = 2

    var shouldPrompt: Bool { status == .pending && promptCount < Self.promptLimit }

    /// Where the correction was made, such as "Notes · Weekly sync", as the learned item's clue.
    var clue: String {
        [lastApp, lastWindowTitle].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private enum CodingKeys: String, CodingKey {
        case id, raw, corrected, count, lastApp, lastWindowTitle, lastSeenAt, status, promptCount
    }
}

extension CorrectionRecord {
    /// Records saved before `lastWindowTitle` and `promptCount` existed have no title and were never asked about.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        raw = try container.decode(String.self, forKey: .raw)
        corrected = try container.decode(String.self, forKey: .corrected)
        count = try container.decode(Int.self, forKey: .count)
        lastApp = try container.decode(String.self, forKey: .lastApp)
        lastWindowTitle = try container.decodeIfPresent(String.self, forKey: .lastWindowTitle) ?? ""
        lastSeenAt = try container.decode(Date.self, forKey: .lastSeenAt)
        status = try container.decode(Status.self, forKey: .status)
        promptCount = try container.decodeIfPresent(Int.self, forKey: .promptCount) ?? 0
    }
}

/// A text button on overlay feedback. The default action only closes the message.
struct OverlayButton {
    let title: String
    var action: @MainActor () -> Void = {}
}

/// One Voice Agent turn, kept in memory for continuous conversation.
struct AgentSession: Identifiable, Equatable {
    var id: UUID = UUID()
    var app: String
    var contextSummary: String
    var userCommand: String
    var response: String
    var createdAt: Date = .now
    var expiresAt: Date

    /// Turns kept per app for continuous conversation.
    static let turnLimit = 3
    /// How long a turn stays in the conversation.
    static let ttl: TimeInterval = 30 * 60

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
    enum Kind: Equatable {
        case selectedText, previousOutput, app, window, clipboard, browser, screen, session, domain, memory

        /// Fixed English name the model sees, independent of the UI language.
        var promptLabel: String {
            switch self {
            case .selectedText: "Selected text"
            case .previousOutput: "Previous SayKuku output"
            case .app: "Current app"
            case .window: "Window title"
            case .clipboard: "Clipboard"
            case .browser: "Browser page"
            case .screen: "Text on screen"
            case .session: "Recent conversation"
            case .domain: "Domains"
            case .memory: "Saved knowledge"
            }
        }
    }
    var id = UUID()
    var kind: Kind
    var symbol: String
    /// Localized UI label; the prompt uses `kind.promptLabel` instead.
    var title: String
    var value: String
    /// Whether `value` holds only the start of a longer text.
    var isClipped = false
}

struct AgentResponse: Codable, Equatable {
    enum Action: String, Codable {
        case writeText, answer, openURL, webSearch, runShortcut

        var title: String {
            switch self {
            case .writeText: localized("Write text")
            case .answer: localized("Answer")
            case .openURL: localized("Open link")
            case .webSearch: localized("Search the web")
            case .runShortcut: localized("Run shortcut")
            }
        }
    }
    enum Target: String, Codable { case current, previous }
    var transcript: String?
    var action: Action
    var target: Target?
    /// Display label only, so a reply without it still decodes.
    var intent: String?
    var output: String?
    var url: String?
    var query: String?
    var shortcutName: String?
    /// A fixed category for local usage totals; an omitted or unknown value never blocks an action.
    var purpose: String? = nil

    /// An empty writeText to the previous output deletes that output.
    var deletesPrevious: Bool { action == .writeText && target == .previous && output?.isEmpty == true }
}

extension AgentResponse {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        transcript = try container.decodeIfPresent(String.self, forKey: .transcript)
        action = try container.decode(Action.self, forKey: .action)
        target = try container.decodeIfPresent(Target.self, forKey: .target)
        intent = try container.decodeIfPresent(String.self, forKey: .intent)
        output = try container.decodeIfPresent(String.self, forKey: .output)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        query = try container.decodeIfPresent(String.self, forKey: .query)
        shortcutName = try container.decodeIfPresent(String.self, forKey: .shortcutName)
        // Optional statistics metadata must not turn an otherwise valid action into a failure.
        purpose = try? container.decode(String.self, forKey: .purpose)
    }
}

enum MemoryNormalizer {
    /// Fixed locale so keys stored or compared on one machine match on another (e.g. Turkish i/İ).
    static func key(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
            .lowercased()
    }

    /// Toneless pinyin, so homophones such as 张越 and 张月 compare equal; nil without Han characters.
    /// `key` folds the tone marks, so no separate diacritic pass is needed.
    static func pinyinKey(_ value: String) -> String? {
        guard value.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }),
              let latin = value.applyingTransform(.mandarinToLatin, reverse: false) else { return nil }
        let pinyin = Self.key(latin)
        return pinyin.isEmpty ? nil : pinyin
    }
}

/// Decodes a value or yields nil, so one bad array element does not fail the whole array.
struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}
