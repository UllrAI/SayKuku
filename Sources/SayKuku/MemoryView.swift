import AppKit
import SwiftUI

struct MemoryView: View {
    @Environment(AppState.self) private var appState
    @Binding var selectedScope: MemoryScope

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 0) {
            ScreenHeader(
                eyebrow: appState.text("记忆", "Memory"),
                title: appState.text("越用越懂你", "Learns as you go"),
                subtitle: appState.text(
                    "纠正建议经你确认才会保存，最近对话 30 分钟后自动清除。",
                    "Corrections are saved only after you approve them. Recent conversations clear after 30 minutes."
                )
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
                            let pending = appState.corrections.filter { $0.status == .pending }
                            if pending.isEmpty {
                                correctionsEmptyView
                            } else {
                                CorrectionSummary(pendingCount: pending.count)
                                ForEach(pending) { item in
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
                .padding(.top, 20)
                .padding(.bottom, 36)
            }
        }
    }

    @ViewBuilder
    private var correctionsEmptyView: some View {
        if appState.learnFromCorrections {
            ContentUnavailableView(
                appState.text("还没有纠正建议", "No correction suggestions yet"),
                systemImage: "sparkles",
                description: Text(appState.text(
                    "改正识别错的词后，SayKuku 会在这里给出建议，确认后才会保存。",
                    "When you fix a word SayKuku got wrong, a suggestion shows up here. Nothing is saved until you approve it."
                ))
            )
            .frame(maxWidth: .infinity, minHeight: 180)
        } else {
            FeatureOffView(
                title: appState.text("已关闭“从纠正中学习”", "Learning from corrections is off"),
                message: appState.text(
                    "开启后，你改正的识别结果会作为建议出现在这里。",
                    "Turn it on to see suggestions from words you fix."
                ),
                systemImage: "sparkles"
            ) { appState.learnFromCorrections = true }
        }
    }
}

/// Empty state for a tab whose feature is turned off, with a way to turn it back on.
private struct FeatureOffView: View {
    @Environment(AppState.self) private var appState
    let title: String
    let message: String
    let systemImage: String
    let turnOn: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            Button(appState.text("开启", "Turn On"), action: turnOn)
                .buttonStyle(HoverFillButtonStyle(prominent: true))
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}

private struct CorrectionSummary: View {
    @Environment(AppState.self) private var appState
    let pendingCount: Int

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
                        ? "1 suggestion needs your review before it’s saved."
                        : "\(pendingCount) suggestions need your review before they’re saved."
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
            Button(appState.text("忽略", "Ignore")) {
                withAnimation(Motion.snappy) { appState.ignoreCorrection(item.id) }
                appState.showToast(appState.text("已忽略这条建议", "Suggestion ignored"), symbol: "xmark.circle")
            }
            .buttonStyle(HoverFillButtonStyle())
            Button(appState.text("加入知识", "Add to Knowledge")) {
                withAnimation(Motion.spring) { appState.acceptCorrection(item.id) }
                appState.showToast(appState.text("已加入知识", "Added to Knowledge"), symbol: "checkmark.circle.fill")
            }
            .buttonStyle(TintButtonStyle())
        }
        .padding(14)
        .kukuSurface(radius: KukuLayout.radiusMedium)
    }
}

private struct SessionMemoryView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        // Refresh each minute so remaining times count down and expired turns drop out.
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let items = appState.sessions
            .filter { $0.expiresAt > now }
            .sorted { $0.createdAt > $1.createdAt }
        if items.isEmpty {
            emptyView
        } else {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Text(appState.text(
                        "在同一个 App 中再次使用语音 Agent 时，会参考这些对话，30 分钟后自动清除。",
                        "Voice Agent uses these in the same app. They’re cleared after 30 minutes."
                    ))
                        .font(.system(size: 11))
                        .foregroundStyle(KukuColor.stone)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 12)
                    Button(appState.text("全部清除", "Clear All")) {
                        withAnimation(Motion.snappy) { appState.clearSessions() }
                        appState.showToast(appState.text("已清除最近对话", "Recent conversations cleared"), symbol: "trash")
                    }
                    .buttonStyle(HoverFillButtonStyle())
                }

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, session in
                        SessionRow(session: session, isLatest: index == 0, isLast: index == items.count - 1, now: now)
                    }
                }
                .padding(17)
                .kukuSurface(radius: KukuLayout.radiusMedium)
            }
        }
    }

    @ViewBuilder
    private var emptyView: some View {
        if appState.continuousConversation {
            ContentUnavailableView(
                appState.text("还没有最近对话", "No recent conversations yet"),
                systemImage: "clock.arrow.circlepath",
                description: Text(appState.text(
                    "使用语音 Agent 后，最近的对话会在这里保留 30 分钟。",
                    "Your recent Voice Agent conversations stay here for 30 minutes."
                ))
            )
            .frame(maxWidth: .infinity, minHeight: 180)
        } else {
            FeatureOffView(
                title: appState.text("已关闭“连续对话”", "Continuous conversation is off"),
                message: appState.text(
                    "开启后，语音 Agent 会记住同一个 App 中最近的对话。",
                    "Turn it on so Voice Agent remembers recent conversations in the same app."
                ),
                systemImage: "clock.arrow.circlepath"
            ) { appState.continuousConversation = true }
        }
    }
}

private struct SessionRow: View {
    @Environment(AppState.self) private var appState
    let session: AgentSession
    let isLatest: Bool
    let isLast: Bool
    let now: Date

    private var minutesLeft: Int {
        max(1, Int((session.expiresAt.timeIntervalSince(now) / 60).rounded(.up)))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Circle()
                .fill(isLatest ? KukuColor.coral : KukuColor.stone.opacity(0.35))
                .frame(width: 9, height: 9)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 4) {
                Text(appName(for: session.app))
                    .font(.system(size: 13, weight: .semibold))
                if !session.userCommand.isEmpty {
                    Text(session.userCommand)
                        .font(.system(size: 12))
                        .foregroundStyle(KukuColor.ink)
                        .lineLimit(2)
                }
                if !session.response.isEmpty {
                    Text(session.response)
                        .font(.system(size: 11))
                        .foregroundStyle(KukuColor.stone)
                        .lineSpacing(3)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 12)
            Text(appState.text("还剩 \(minutesLeft) 分钟", "Expires in \(minutesLeft) min"))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(KukuColor.stone)
        }
        .padding(.bottom, isLast ? 0 : 12)
        .background(alignment: .topLeading) {
            // Timeline line from this dot down to the next one, whatever the row height.
            if !isLast {
                Rectangle()
                    .fill(KukuColor.line)
                    .frame(width: 1)
                    .padding(.top, 18)
                    .padding(.leading, 4)
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

private struct LongTermMemoryView: View {
    @Environment(AppState.self) private var appState

    private struct MemoryGroup {
        let title: String
        let symbol: String
        let lines: [String]
    }

    private var groups: [MemoryGroup] {
        let entities = appState.knowledgeEntities
        let names = entities.prefix(8).map(\.name).joined(separator: appState.text("、", ", "))
        let relationships = appState.knowledgeRelationships.prefix(8).compactMap { relationship -> String? in
            guard let from = entities.first(where: { $0.id == relationship.fromEntityID }),
                  let to = entities.first(where: { $0.id == relationship.toEntityID }) else { return nil }
            return "\(from.name) \(relationship.type.title(appState)) \(to.name)"
        }
        return [
            MemoryGroup(title: appState.text("已保存的名称", "Saved names"), symbol: "character.cursor.ibeam", lines: names.isEmpty ? [] : [names]),
            MemoryGroup(title: appState.text("常用关系", "Relationships"), symbol: "point.3.connected.trianglepath.dotted", lines: relationships)
        ].filter { !$0.lines.isEmpty }
    }

    var body: some View {
        let groups = self.groups
        if groups.isEmpty {
            ContentUnavailableView {
                Label(appState.text("还没有长期记忆", "No long-term memory yet"), systemImage: "books.vertical")
            } description: {
                Text(appState.text(
                    "你在“知识”中添加的名称和接受的纠正建议会显示在这里，识别时也会参考。",
                    "Names you add to Knowledge and corrections you accept show up here and help recognition."
                ))
            } actions: {
                Button(appState.text("打开“知识”", "Open Knowledge")) { appState.destination = .knowledge }
                    .buttonStyle(HoverFillButtonStyle())
            }
            .frame(maxWidth: .infinity, minHeight: 180)
        } else {
            VStack(spacing: 10) {
                ForEach(groups, id: \.title) { group in
                    HStack(spacing: 15) {
                        Image(systemName: group.symbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(KukuColor.coral)
                            .frame(width: 38, height: 38)
                            .background(KukuColor.coralSoft, in: RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.title).font(.system(size: 13, weight: .semibold))
                            ForEach(Array(group.lines.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(size: 11))
                                    .foregroundStyle(KukuColor.stone)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 12)
                        Button(appState.text("在“知识”中管理", "Manage in Knowledge")) { appState.destination = .knowledge }
                            .buttonStyle(TintButtonStyle())
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
        case .shortTerm: appState.text("短期", "Short-Term")
        case .longTerm: appState.text("长期", "Long-Term")
        }
    }
}
