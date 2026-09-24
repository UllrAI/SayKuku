import AppKit
import SwiftUI

struct MemoryView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedScope: MemoryScope = .corrections

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 0) {
            ScreenHeader(
                eyebrow: appState.text("记忆", "Memory"),
                title: appState.text("越用越准，但始终由你决定", "Gets better, always on your terms")
            ) {
                Toggle(appState.text("从纠正中学习", "Learn from corrections"), isOn: $appState.learnFromCorrections)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(size: 11, weight: .medium))
            }

            KukuPageTabs(
                items: MemoryScope.allCases,
                selection: $selectedScope,
                title: { $0.title(appState) }
            )

            Divider().opacity(0.55)

            ScrollView {
                KukuPageContent {
                    VStack(spacing: 14) {
                        if selectedScope == .corrections {
                            if appState.corrections.allSatisfy({ $0.status != .pending }) {
                                emptyView
                            } else {
                                CorrectionSummary()
                                ForEach(appState.corrections.filter { $0.status == .pending }) { item in
                                    CorrectionRow(item: item)
                                }
                            }
                        } else if selectedScope == .shortTerm {
                            SessionMemoryView()
                        } else {
                            LongTermMemoryView()
                        }
                    }
                }
                .padding(.vertical, 20)
            }
        }
    }

    private var emptyView: some View {
        ContentUnavailableView(
            appState.text("还没有纠正建议", "No correction suggestions yet"),
            systemImage: "sparkles",
            description: Text(appState.text("当你纠正识别结果时，建议会显示在这里，确认后才会保存。", "Corrections to recognition results appear here for your review before they are saved."))
        )
        .foregroundStyle(KukuColor.stone)
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}

private struct CorrectionSummary: View {
    @Environment(AppState.self) private var appState

    private var pendingCount: Int {
        appState.corrections.filter { $0.status == .pending }.count
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(KukuColor.coralSoft)
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(KukuColor.coral)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(appState.text("纠正建议", "Correction suggestions"))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(appState.text(
                    "有 \(pendingCount) 条建议待确认，确认后才会保存。",
                    pendingCount == 1
                        ? "1 suggestion needs your review before it's saved."
                        : "\(pendingCount) suggestions need your review before they're saved."
                ))
                    .font(.system(size: 11))
                    .foregroundStyle(KukuColor.stone)
            }
            Spacer()
        }
        .padding(15)
        .kukuSurface(radius: KukuLayout.radiusMedium)
    }
}

private struct CorrectionRow: View {
    @Environment(AppState.self) private var appState
    let item: CorrectionRecord

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 9) {
                    Text(item.raw)
                        .strikethrough()
                        .foregroundStyle(KukuColor.stone)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(KukuColor.coral)
                    Text(item.corrected)
                        .fontWeight(.semibold)
                }
                .font(.system(size: 15, design: .rounded))
                Text(appState.text(
                    "累计纠正 \(item.count) 次 · 最近在 \(item.lastApp)",
                    "Corrected \(item.count == 1 ? "once" : "\(item.count) times") · Last in \(item.lastApp)"
                ))
                    .font(.system(size: 10))
                    .foregroundStyle(KukuColor.stone)
            }
            Spacer()
            Button(appState.text("忽略", "Ignore")) { withAnimation(Motion.snappy) { appState.ignoreCorrection(item.id) } }
                .buttonStyle(HoverFillButtonStyle())
            Button(appState.text("加入知识", "Add to Knowledge")) { withAnimation(Motion.spring) { appState.acceptCorrection(item.id) } }
                .buttonStyle(TintButtonStyle())
        }
        .padding(14)
        .kukuSurface(radius: KukuLayout.radiusMedium)
    }
}

private struct SessionMemoryView: View {
    @Environment(AppState.self) private var appState

    private var items: [MemoryTimelineItem] {
        appState.sessions.filter { $0.expiresAt > .now }.map {
            MemoryTimelineItem(id: $0.id, title: appName(for: $0.app), detail: $0.userCommand + "\n" + $0.response, expiresAt: $0.expiresAt)
        }
        .sorted { $0.expiresAt < $1.expiresAt }
    }

    var body: some View {
        if items.isEmpty {
            ContentUnavailableView(
                appState.text("暂无短期记忆", "No short-term memory"),
                systemImage: "clock.arrow.circlepath",
                description: Text(appState.text(
                    "使用语音 Agent 后，最近的交流会在这里保留 30 分钟。",
                    "Recent Voice Agent exchanges appear here for 30 minutes."
                ))
            )
            .foregroundStyle(KukuColor.stone)
            .frame(maxWidth: .infinity, minHeight: 180)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Text(appState.text(
                        "下次在同一应用中使用语音 Agent 时，会参考这些交流；30 分钟后自动清除。",
                        "Voice Agent can use these exchanges in the same app. They expire after 30 minutes."
                    ))
                        .font(.system(size: 11))
                        .foregroundStyle(KukuColor.stone)
                    Spacer(minLength: 12)
                    Button(appState.text("全部清除", "Clear all")) {
                        withAnimation(Motion.snappy) { appState.clearSessions() }
                    }
                    .buttonStyle(HoverFillButtonStyle())
                }

                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        HStack(alignment: .top, spacing: 16) {
                            VStack(spacing: 5) {
                                Circle()
                                    .fill(index == 0 ? KukuColor.coral : KukuColor.stone.opacity(0.35))
                                    .frame(width: 9, height: 9)
                                if index < items.count - 1 {
                                    Rectangle().fill(KukuColor.line).frame(width: 1, height: 52)
                                }
                            }
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.title)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(item.detail)
                                    .font(.system(size: 11))
                                    .foregroundStyle(KukuColor.stone)
                                    .lineSpacing(3)
                            }
                            Spacer()
                            Text(item.expiresAt, style: .relative)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(KukuColor.stone)
                        }
                    }
                }
                .padding(17)
                .kukuSurface(radius: KukuLayout.radiusMedium)
            }
        }
    }

    /// Sessions store the bundle ID; show the app's name when it can be resolved.
    private func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        let name = FileManager.default.displayName(atPath: url.path(percentEncoded: false))
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}

private struct MemoryTimelineItem: Identifiable {
    let id: UUID
    let title: String
    let detail: String
    let expiresAt: Date
}

private struct LongTermMemoryView: View {
    @Environment(AppState.self) private var appState

    private var groups: [(String, String, String)] {
        let spellings = appState.knowledgeEntities.prefix(8).map(\.name).joined(separator: " · ")
        let relationships = appState.knowledgeRelationships.prefix(8).compactMap { relationship -> String? in
            guard let from = appState.knowledgeEntities.first(where: { $0.id == relationship.fromEntityID }),
                  let to = appState.knowledgeEntities.first(where: { $0.id == relationship.toEntityID }) else { return nil }
            return "\(from.name) · \(relationship.type.title(appState)) · \(to.name)"
        }.joined(separator: " · ")
        return [
            (appState.text("固定拼写", "Confirmed spellings"), spellings, "character.cursor.ibeam"),
            (appState.text("常用关系", "Relationships"), relationships, "point.3.connected.trianglepath.dotted")
        ].filter { !$0.1.isEmpty }
    }

    var body: some View {
        if groups.isEmpty {
            ContentUnavailableView(
                appState.text("暂无长期知识", "No long-term knowledge"),
                systemImage: "books.vertical",
                description: Text(appState.text(
                    "添加常用名称或确认纠正建议后，SayKuku 会在识别时参考它们。",
                    "Add familiar names or confirm corrections so SayKuku can recognize them next time."
                ))
            )
            .foregroundStyle(KukuColor.stone)
            .frame(maxWidth: .infinity, minHeight: 180)
        } else {
            VStack(spacing: 10) {
                ForEach(groups, id: \.0) { group in
                    HStack(spacing: 15) {
                        Image(systemName: group.2)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(KukuColor.coral)
                            .frame(width: 38, height: 38)
                            .background(KukuColor.coralSoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.0).font(.system(size: 13, weight: .semibold))
                            Text(group.1).font(.system(size: 11)).foregroundStyle(KukuColor.stone)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .kukuSurface(radius: KukuLayout.radiusMedium)
                }
            }
        }
    }
}

enum MemoryScope: String, CaseIterable, Identifiable {
    case corrections, shortTerm, longTerm
    var id: String { rawValue }
    @MainActor func title(_ appState: AppState) -> String {
        switch self {
        case .corrections: appState.text("纠正", "Corrections")
        case .shortTerm: appState.text("短期", "Short-term")
        case .longTerm: appState.text("长期", "Long-term")
        }
    }
}
