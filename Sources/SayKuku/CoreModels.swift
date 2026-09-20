import Foundation
import SwiftUI

enum QwenRegion: String, Codable, CaseIterable, Identifiable {
    case beijing
    case singapore

    var id: String { rawValue }
    var title: String { self == .beijing ? "北京" : "新加坡" }
    var legacyHost: String { self == .beijing ? "dashscope.aliyuncs.com" : "dashscope-intl.aliyuncs.com" }

    func host(workspaceID: String) -> String {
        guard !workspaceID.isEmpty else { return legacyHost }
        return self == .beijing
            ? "\(workspaceID).cn-beijing.maas.aliyuncs.com"
            : "\(workspaceID).ap-southeast-1.maas.aliyuncs.com"
    }
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
    @MainActor func title(_ appState: AppState) -> String { appState.usesChineseUI ? chineseTitle : englishTitle }
}

enum HistoryMode: String, Codable {
    case dictation, agent
    var filter: HistoryFilter { self == .dictation ? .dictation : .agent }
    var symbol: String { self == .dictation ? "mic.fill" : "sparkles" }
    var color: Color { self == .dictation ? KukuColor.coral : KukuColor.graphite }
    @MainActor func title(_ appState: AppState) -> String { self == .dictation ? "Voice Input" : "Voice Agent" }
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

    init(
        id: UUID = UUID(), mode: HistoryMode, app: String, createdAt: Date = .now,
        durationSeconds: Double, input: String, output: String,
        audioFilename: String? = nil, isStarred: Bool = false
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
    }

    var time: String { createdAt.formatted(date: .omitted, time: .shortened) }
    var duration: String { durationSeconds > 0 ? String(format: "%.1fs", durationSeconds) : "—" }
    var hasAudio: Bool { audioFilename != nil }
}

enum EntityType: String, Codable, CaseIterable, Identifiable {
    case person, organization, orgUnit, project, product, term, unknown
    var id: String { rawValue }
    @MainActor func title(_ appState: AppState) -> String {
        switch self {
        case .person: appState.text("人物", "Person")
        case .organization: appState.text("组织", "Organization")
        case .orgUnit: appState.text("部门", "Org unit")
        case .project: appState.text("项目", "Project")
        case .product: appState.text("产品", "Product")
        case .term: appState.text("术语", "Term")
        case .unknown: appState.text("未分类", "Unknown")
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

enum RelationshipType: String, Codable, CaseIterable {
    case belongsTo, worksOn, owns, relatedTo
}

struct KnowledgeRelationship: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var fromEntityID: UUID
    var type: RelationshipType
    var toEntityID: UUID
    var evidence: String
}

enum ImportStatus: String, Codable { case new = "NEW", merge = "MERGE", conflict = "CONFLICT", ignored = "IGNORED" }

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
}

struct ContextItem: Identifiable, Equatable {
    enum Kind: Equatable { case selectedText, app, window, clipboard, browser, session, knowledge }
    var id = UUID()
    var kind: Kind
    var symbol: String
    var title: String
    var value: String
}

struct AgentResponse: Codable, Equatable {
    enum Action: String, Codable { case writeText, openURL, webSearch, runShortcut }
    var transcript: String?
    var action: Action
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
